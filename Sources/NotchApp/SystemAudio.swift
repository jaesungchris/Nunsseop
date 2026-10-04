import AudioToolbox
import CoreAudio
import Foundation

/// Default output device volume and mute, with change callbacks.
@MainActor
final class SystemAudio {
    var onVolumeChange: ((Float, Bool) -> Void)?
    var onOutputDeviceChange: (() -> Void)?

    private var device = AudioDeviceID(0)
    private let listenerQueue = DispatchQueue.main
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        bind(to: Self.defaultOutputDevice())
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress,
                                            listenerQueue) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.bind(to: Self.defaultOutputDevice())
                self.onOutputDeviceChange?()
            }
        }
    }

    var volume: Float {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &value)
        return value
    }

    var isMuted: Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &value)
        return value != 0
    }

    func setVolume(_ newValue: Float) {
        var value = Float32(min(1, max(0, newValue)))
        AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if value > 0 && isMuted { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func bind(to newDevice: AudioDeviceID) {
        if let volumeListener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, listenerQueue, volumeListener)
        }
        if let muteListener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, listenerQueue, muteListener)
        }
        device = newDevice
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onVolumeChange?(self.volume, self.isMuted)
            }
        }
        volumeListener = changed
        muteListener = changed
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, listenerQueue, changed)
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, listenerQueue, changed)
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &size, &id)
        return id
    }
}
