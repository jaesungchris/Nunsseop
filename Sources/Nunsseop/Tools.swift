import AppKit
import CoreAudio
import IOKit.pwr_mgt
import SwiftUI

/// Output device switching, microphone mute, keep-awake and drive ejection.
@MainActor
final class ToolsModel: ObservableObject {
    struct AudioDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    struct Drive: Identifiable, Hashable {
        let id: URL
        let name: String
    }

    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var currentOutput: AudioDeviceID = 0
    @Published private(set) var micMuted = false
    @Published private(set) var keepAwake = false
    @Published private(set) var drives: [Drive] = []
    @Published private(set) var ejectError: String?

    private var assertionID: IOPMAssertionID = 0
    private var savedInputVolume: Float32?
    private var observers: [NSObjectProtocol] = []

    func start() {
        refreshAudio()
        refreshDrives()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDrives() }
            })
        }
    }

    // MARK: Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var address = address(selector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    func refreshAudio() {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        outputs = ids.compactMap { id in
            var streams = Self.address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize)
            guard streamSize > 0 else { return nil }
            var nameAddress = Self.address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return AudioDevice(id: id, name: name?.takeRetainedValue() as String? ?? "Audio device")
        }
        currentOutput = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        micMuted = inputIsMuted
    }

    func selectOutput(_ device: AudioDevice) {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        refreshAudio()
    }

    private var inputIsMuted: Bool {
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        var mute = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        if AudioObjectHasProperty(input, &mute) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(input, &mute, 0, nil, &size, &value)
            if value != 0 { return true }
        }
        return savedInputVolume != nil
    }

    /// Uses the device's mute switch when it has one, otherwise drops input volume to zero.
    func toggleMic() {
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let muting = !micMuted
        var mute = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(input, &mute),
           AudioObjectIsPropertySettable(input, &mute, &settable) == noErr, settable.boolValue {
            var value: UInt32 = muting ? 1 : 0
            AudioObjectSetPropertyData(input, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else {
            var volume = Self.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
            var size = UInt32(MemoryLayout<Float32>.size)
            if muting {
                var current: Float32 = 0
                AudioObjectGetPropertyData(input, &volume, 0, nil, &size, &current)
                savedInputVolume = current
                var zero: Float32 = 0
                AudioObjectSetPropertyData(input, &volume, 0, nil, size, &zero)
            } else if var restore = savedInputVolume {
                AudioObjectSetPropertyData(input, &volume, 0, nil, size, &restore)
            }
        }
        if !muting { savedInputVolume = nil }
        micMuted = muting
    }

    // MARK: Keep awake

    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertionID)
            keepAwake = false
        } else {
            let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Nunsseop keep awake" as CFString, &assertionID)
            keepAwake = ok == kIOReturnSuccess
        }
    }

    // MARK: Drives

    func refreshDrives() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        drives = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsEjectable == true || (values.volumeIsRemovable == true && values.volumeIsInternal != true)
            else { return nil }
            return Drive(id: url, name: values.volumeName ?? url.lastPathComponent)
        }
    }

    func eject(_ drive: Drive) {
        ejectError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: drive.id)
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self.ejectError = message }
            }
        }
    }
}

struct ToolsTab: View {
    @ObservedObject var tools: ToolsModel
    @ObservedObject var recorder: ScreenRecorder
    let recordAudio: Bool

    var body: some View {
        HStack(spacing: 10) {
            ToolTile(symbol: "hifispeaker.fill", title: String(localized: "Output"), active: false) {
                Menu {
                    ForEach(tools.outputs) { device in
                        Button {
                            tools.selectOutput(device)
                        } label: {
                            if device.id == tools.currentOutput { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                        }
                    }
                } label: {
                    Text(tools.outputs.first { $0.id == tools.currentOutput }?.name ?? "—")
                        .font(.system(size: 11)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize(horizontal: false, vertical: true)
            } action: { tools.refreshAudio() }

            ToolTile(symbol: tools.micMuted ? "mic.slash.fill" : "mic.fill", title: String(localized: "Microphone"),
                     active: tools.micMuted) {
                Text(tools.micMuted ? String(localized: "Muted") : String(localized: "On")).font(.system(size: 11))
            } action: { tools.toggleMic() }

            ToolTile(symbol: tools.keepAwake ? "cup.and.saucer.fill" : "moon.zzz.fill", title: String(localized: "Keep awake"),
                     active: tools.keepAwake) {
                Text(tools.keepAwake ? String(localized: "On") : String(localized: "Off")).font(.system(size: 11))
            } action: { tools.toggleKeepAwake() }

            ToolTile(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle", title: String(localized: "Record screen"),
                     active: recorder.isRecording) {
                if let started = recorder.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(TimerModel.format(context.date.timeIntervalSince(started))).font(.system(size: 11).monospacedDigit())
                    }
                } else {
                    Text(ScreenRecorder.hasPermission ? String(localized: "Start") : String(localized: "Needs permission"))
                        .font(.system(size: 11))
                }
            } action: { recorder.toggle(withAudio: recordAudio) }

            VStack(alignment: .leading, spacing: 6) {
                Label("Drives", systemImage: "externaldrive.fill").font(.system(size: 11, weight: .semibold))
                if tools.drives.isEmpty {
                    Text("No external drives").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                ForEach(tools.drives) { drive in
                    HStack {
                        Text(drive.name).font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        Button { tools.eject(drive) } label: { Image(systemName: "eject.fill").font(.system(size: 10)) }
                            .buttonStyle(.plain)
                            .help(Text("Eject"))
                    }
                }
                if let error = tools.ejectError {
                    Text(error).font(.system(size: 9)).foregroundStyle(.red.opacity(0.8)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .surface(RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(.white)
    }
}

private struct ToolTile<Detail: View>: View {
    let symbol: String
    let title: String
    let active: Bool
    @ViewBuilder let detail: Detail
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(active ? Color.accentColor : .white.opacity(0.12)))
            Spacer(minLength: 0)
            Text(title).font(.system(size: 12, weight: .semibold))
            detail.foregroundStyle(.white.opacity(0.6))
        }
        .padding(12)
        .frame(width: 98, alignment: .leading)
        .frame(maxHeight: .infinity)
        .surface(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: action)
    }
}
