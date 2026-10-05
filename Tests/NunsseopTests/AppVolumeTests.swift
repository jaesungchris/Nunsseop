import CoreAudio
import Foundation
import Testing
@testable import Nunsseop

struct AppVolumeGroupingTests {
    private func process(_ object: AudioObjectID, pid: pid_t, _ bundleID: String, output: Bool) -> CallMonitor.AudioProcess {
        CallMonitor.AudioProcess(pid: pid, bundleID: bundleID, isRunningInput: false, isRunningOutput: output, objectID: object)
    }

    /// Helpers named after their app, as an app lookup would find them.
    private func owner(_ process: CallMonitor.AudioProcess) -> String? {
        AppVolumeModel.installedApp(for: process.bundleID) { ["com.google.Chrome", "com.spotify.client"].contains($0) ? $0 : nil }
    }

    @Test func groupsHelpersUnderTheirApp() {
        let groups = AppVolumeModel.groups([
            process(10, pid: 100, "com.google.Chrome", output: false),
            process(11, pid: 101, "com.google.Chrome.helper", output: true),
            process(12, pid: 102, "com.google.Chrome.helper.Renderer", output: false),
            process(20, pid: 200, "com.spotify.client", output: false),
        ], own: 1, app: owner)
        #expect(groups == [
            AppVolumeModel.Group(app: "com.google.Chrome", objects: [10, 11, 12], sounding: true),
            AppVolumeModel.Group(app: "com.spotify.client", objects: [20], sounding: false),
        ])
    }

    @Test func leavesOutOwnProcessDaemonsAndMissingObjects() {
        let groups = AppVolumeModel.groups([
            process(30, pid: 1, "com.spotify.client", output: true),
            process(31, pid: 300, "com.apple.audio.coreaudiod", output: true),
            process(0, pid: 301, "com.spotify.client", output: true),
        ], own: 1, app: owner)
        #expect(groups.isEmpty)
    }

    @Test func findsTheInstalledAppByTrimmingTheBundleID() {
        let installed = ["com.google.Chrome": "/Applications/Google Chrome.app", "us.zoom.xos": "/Applications/zoom.us.app"]
        #expect(AppVolumeModel.installedApp(for: "com.google.Chrome.helper.Plugin") { installed[$0] } == "/Applications/Google Chrome.app")
        #expect(AppVolumeModel.installedApp(for: "us.zoom.xos") { installed[$0] } == "/Applications/zoom.us.app")
        #expect(AppVolumeModel.installedApp(for: "com.apple.CoreSpeech") { installed[$0] } == nil)
        // A lone top-level domain is never tried.
        #expect(AppVolumeModel.installedApp(for: "com") { $0 } == nil)
    }

    @Test func outermostAppOfAHelper() {
        #expect(AppVolumeModel.outermostApp(in: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app")
                == "/Applications/Google Chrome.app")
        #expect(AppVolumeModel.outermostApp(in: "/Applications/Spotify.app") == "/Applications/Spotify.app")
        #expect(AppVolumeModel.outermostApp(in: "/usr/libexec/daemon") == nil)
    }

    @Test func sliderMapsToSquaredGain() {
        #expect(AppVolumeModel.gain(for: 0) == 0)
        #expect(AppVolumeModel.gain(for: 0.5) == 0.25)
        #expect(AppVolumeModel.gain(for: 1) == 1)
        #expect(AppVolumeModel.gain(for: 1.4) == 1)
        #expect(AppVolumeModel.gain(for: -0.2) == 0)
    }
}

struct TapMixerTests {
    @Test func rampReachesTargetOnLastFrame() {
        #expect(TapMixer.gain(from: 1, to: 0, frame: 0, frames: 4) == 0.75)
        #expect(TapMixer.gain(from: 1, to: 0, frame: 1, frames: 4) == 0.5)
        #expect(TapMixer.gain(from: 1, to: 0, frame: 3, frames: 4) == 0)
        #expect(TapMixer.gain(from: 0.2, to: 0.2, frame: 0, frames: 4) == 0.2)
        #expect(TapMixer.gain(from: 0, to: 1, frame: 0, frames: 0) == 1)
    }

    /// Runs the mixer on buffers holding `input` (interleaved) and returns each output buffer's samples.
    private func mix(input: [Float], inputChannels: Int, outputs: [Int], frames: Int, from: Float, to: Float,
                     extraInputs: [[Float]] = []) -> (heard: Bool, output: [[Float]]) {
        let allInputs = extraInputs.map { ($0, 1) } + [(input, inputChannels)]
        let inList = AudioBufferList.allocate(maximumBuffers: allInputs.count)
        let outList = AudioBufferList.allocate(maximumBuffers: outputs.count)
        var storage: [UnsafeMutablePointer<Float>] = []
        defer {
            storage.forEach { $0.deallocate() }
            free(inList.unsafeMutablePointer)
            free(outList.unsafeMutablePointer)
        }
        for (index, (samples, channels)) in allInputs.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
            data.initialize(from: samples, count: samples.count)
            storage.append(data)
            inList[index] = AudioBuffer(mNumberChannels: UInt32(channels), mDataByteSize: UInt32(samples.count * 4), mData: data)
        }
        for (index, channels) in outputs.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: frames * channels)
            data.initialize(repeating: 99, count: frames * channels)
            storage.append(data)
            outList[index] = AudioBuffer(mNumberChannels: UInt32(channels), mDataByteSize: UInt32(frames * channels * 4), mData: data)
        }
        let heard = TapMixer.render(input: inList.unsafePointer, output: outList.unsafeMutablePointer, from: from, to: to)
        let result = outputs.enumerated().map { index, channels in
            Array(UnsafeBufferPointer(start: outList[index].mData!.assumingMemoryBound(to: Float.self), count: frames * channels))
        }
        return (heard, result)
    }

    @Test func copiesStereoWithRampedGain() {
        let result = mix(input: [1, -1, 1, -1], inputChannels: 2, outputs: [2], frames: 2, from: 1, to: 0)
        #expect(result.heard)
        #expect(result.output == [[0.5, -0.5, 0, -0]])
    }

    @Test func steadyGainScalesEverySample() {
        let result = mix(input: [0.5, 0.25, 0.5, 0.25], inputChannels: 2, outputs: [2], frames: 2, from: 0.5, to: 0.5)
        #expect(result.output == [[0.25, 0.125, 0.25, 0.125]])
    }

    @Test func zeroGainIsSilentButStillHearsTheTap() {
        let result = mix(input: [0.3, 0.3], inputChannels: 2, outputs: [2], frames: 1, from: 0, to: 0)
        #expect(result.heard)
        #expect(result.output == [[0, 0]])
    }

    @Test func silenceIsNotHeard() {
        let result = mix(input: [0, 0, 0, 0], inputChannels: 2, outputs: [2], frames: 2, from: 1, to: 1)
        #expect(!result.heard)
        #expect(result.output == [[0, 0, 0, 0]])
    }

    @Test func extraOutputChannelsAreSilentAndSplitBuffersFollowChannelOrder() {
        // Two mono buffers take left and right; a third gets nothing.
        let result = mix(input: [0.2, 0.4], inputChannels: 2, outputs: [1, 1, 1], frames: 1, from: 1, to: 1)
        #expect(result.output == [[0.2], [0.4], [0]])
    }

    @Test func monoOutputGetsBothSides() {
        let result = mix(input: [0.2, 0.4], inputChannels: 2, outputs: [1], frames: 1, from: 1, to: 1)
        #expect(abs(result.output[0][0] - 0.3) < 1e-6)
    }

    @Test func usesTheLastInputBufferAsTheTap() {
        // A headset microphone comes first in the aggregate's input; it must not reach the output.
        let result = mix(input: [0.5, 0.5], inputChannels: 2, outputs: [2], frames: 1, from: 1, to: 1, extraInputs: [[0.9]])
        #expect(result.output == [[0.5, 0.5]])
    }
}
