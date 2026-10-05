import Testing
@testable import Nunsseop

/// An input device without a mute switch, and the stored volume, kept in memory.
private final class FakeMic {
    var volume: Float32?
    var settable: Bool
    var saved: Float32?

    init(volume: Float32?, settable: Bool = true, saved: Float32? = nil) {
        self.volume = volume
        self.settable = settable
        self.saved = saved
    }

    var mute: ToolsModel.VolumeMute {
        ToolsModel.VolumeMute(volume: { self.volume },
                              setVolume: { value in
                                  guard self.settable else { return false }
                                  self.volume = value
                                  return true
                              },
                              saved: { self.saved },
                              setSaved: { self.saved = $0 })
    }
}

@MainActor
struct MicVolumeMuteTests {
    @Test func muteSavesVolumeAndUnmuteRestoresIt() {
        let mic = FakeMic(volume: 0.7)
        mic.mute.mute()
        #expect(mic.volume == 0)
        #expect(mic.saved == 0.7)
        #expect(mic.mute.isMuted)
        mic.mute.unmute()
        #expect(mic.volume == 0.7)
        #expect(mic.saved == nil)
        #expect(!mic.mute.isMuted)
    }

    @Test func savedValueAloneReportsMutedAfterRelaunch() {
        #expect(FakeMic(volume: 0, saved: 0.5).mute.isMuted)
        #expect(!FakeMic(volume: 0.3, saved: 0.5).mute.isMuted)
        #expect(!FakeMic(volume: 0).mute.isMuted)
    }

    @Test func secondMuteAtZeroKeepsEarlierSavedVolume() {
        let mic = FakeMic(volume: 0, saved: 0.6)
        mic.mute.mute()
        #expect(mic.saved == 0.6)
        #expect(mic.volume == 0)
    }

    @Test func unmuteRestoresOnlyWhileStillAtZero() {
        let mic = FakeMic(volume: 0.4, saved: 0.8)
        mic.mute.unmute()
        #expect(mic.volume == 0.4)
        #expect(mic.saved == nil)
    }

    @Test func deviceThatCannotBeSetDoesNotReportMuted() {
        let mic = FakeMic(volume: 0.5, settable: false)
        mic.mute.mute()
        #expect(mic.volume == 0.5)
        #expect(mic.saved == nil)
        #expect(!mic.mute.isMuted)
    }

    @Test func failedSetKeepsEarlierSavedVolume() {
        let mic = FakeMic(volume: 0.5, settable: false, saved: 0.9)
        mic.mute.mute()
        #expect(mic.saved == 0.9)
    }

    @Test func deviceWithoutVolumeIsLeftAlone() {
        let mic = FakeMic(volume: nil)
        mic.mute.mute()
        #expect(mic.saved == nil)
        #expect(!mic.mute.isMuted)
    }
}
