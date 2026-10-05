import AppKit
import CoreAudio
import IOKit.pwr_mgt
import SwiftUI

/// Output device switching, microphone mute, keep-awake, drive ejection, color picking and text capture.
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
    /// Hex codes of recently picked colors, newest first.
    @Published private(set) var pickedColors: [String] = []
    @Published private(set) var isCapturingText = false
    /// Confirms a copy in the notch: symbol, title, detail.
    var onNotice: ((String, String, String?) -> Void)?

    private var assertionID: IOPMAssertionID = 0
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
            // The per-app volume devices are only for this app.
            guard streamSize > 0, !AppVolumeModel.isOwnDevice(id) else { return nil }
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
        return Self.volumeMute(for: input)?.isMuted ?? false
    }

    /// Uses the device's mute switch when it has one, otherwise drops input volume to zero.
    func toggleMic() {
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let muting = !inputIsMuted
        var mute = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(input, &mute),
           AudioObjectIsPropertySettable(input, &mute, &settable) == noErr, settable.boolValue {
            var value: UInt32 = muting ? 1 : 0
            AudioObjectSetPropertyData(input, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else if let fallback = Self.volumeMute(for: input) {
            if muting { fallback.mute() } else { fallback.unmute() }
        }
        micMuted = inputIsMuted
    }

    /// The zero-volume mute for inputs without a mute switch. The volume before muting is kept in
    /// UserDefaults by device, so the mute lasts across relaunches until the user unmutes.
    struct VolumeMute {
        var volume: () -> Float32?
        /// Returns false when the device refused the volume.
        var setVolume: (Float32) -> Bool
        var saved: () -> Float32?
        var setSaved: (Float32?) -> Void

        var isMuted: Bool { volume() == 0 && saved() != nil }

        func mute() {
            guard let current = volume() else { return }
            let previous = saved()
            // A volume already at zero under a saved one is this mute, so keep the volume saved before it.
            if current > 0 || previous == nil { setSaved(current) }
            if !setVolume(0) { setSaved(previous) }
        }

        func unmute() {
            // If the user raised the volume meanwhile, it stays; only the saved value goes.
            if let restore = saved(), volume() == 0, !setVolume(restore) { return }
            setSaved(nil)
        }
    }

    private static func volumeMute(for device: AudioDeviceID) -> VolumeMute? {
        guard let uid = uid(of: device) else { return nil }
        return VolumeMute(volume: { inputVolume(of: device) },
                          setVolume: { setInputVolume($0, of: device) },
                          saved: { savedInputVolume(for: uid) },
                          setSaved: { setSavedInputVolume($0, for: uid) })
    }

    private static let savedInputVolumesKey = "savedInputVolumes"

    static func savedInputVolumes(_ defaults: UserDefaults = .standard) -> [String: Float32] {
        (defaults.dictionary(forKey: savedInputVolumesKey) as? [String: NSNumber] ?? [:]).mapValues(\.floatValue)
    }

    static func savedInputVolume(for uid: String, defaults: UserDefaults = .standard) -> Float32? {
        savedInputVolumes(defaults)[uid]
    }

    static func setSavedInputVolume(_ volume: Float32?, for uid: String, defaults: UserDefaults = .standard) {
        var saved = savedInputVolumes(defaults)
        saved[uid] = volume
        if saved.isEmpty {
            defaults.removeObject(forKey: savedInputVolumesKey)
        } else {
            defaults.set(saved.mapValues { NSNumber(value: $0) }, forKey: savedInputVolumesKey)
        }
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        var address = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard device != 0, AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func inputVolume(of device: AudioDeviceID) -> Float32? {
        var address = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func setInputVolume(_ volume: Float32, of device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        var volume = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume) == noErr
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

    // MARK: Color picker

    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            let channel = { (value: CGFloat) in Int((min(1, max(0, value)) * 255).rounded()) }
            let hex = String(format: "#%02X%02X%02X", channel(color.redComponent), channel(color.greenComponent),
                             channel(color.blueComponent))
            Task { @MainActor in self?.copyColor(hex) }
        }
    }

    func copyColor(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        pickedColors.removeAll { $0 == hex }
        pickedColors.insert(hex, at: 0)
        if pickedColors.count > 5 { pickedColors.removeLast(pickedColors.count - 5) }
        onNotice?("eyedropper", String(localized: "Copied \(hex)"), nil)
    }

    // MARK: Text capture

    /// Lets the user select a screen region, reads its text and copies it. Cancelling does nothing.
    func captureText() {
        guard !isCapturingText else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nunsseop-text-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.global(qos: .userInitiated).async {
                let captured = FileManager.default.fileExists(atPath: url.path)
                let text = captured ? TextRecognizer.recognize(imageAt: url) : ""
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async { self?.finishCapture(text, captured: captured) }
            }
        }
        do {
            try process.run()
            isCapturingText = true
        } catch {
            return
        }
    }

    private func finishCapture(_ text: String, captured: Bool) {
        isCapturingText = false
        guard captured else { return }
        guard !text.isEmpty else {
            // Without Screen Recording, other apps' windows come out blank, so nothing is read.
            if ScreenRecorder.hasPermission {
                onNotice?("text.viewfinder", String(localized: "No text found"), nil)
            } else {
                onNotice?("text.viewfinder", String(localized: "No text found"),
                          String(localized: "Allow Screen Recording to read other apps’ windows"))
                CGRequestScreenCaptureAccess()
            }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        onNotice?("text.viewfinder", String(localized: "Text copied"), flat.count > 40 ? flat.prefix(40) + "…" : flat)
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
    /// Set while per-app volume is turned on.
    let appVolume: AppVolumeModel?

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
            .overlay(alignment: .topTrailing) {
                if let appVolume { AppVolumeButton(model: appVolume).padding(8) }
            }

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

            // The tiles narrow first so this column keeps room for both capture buttons.
            VStack(spacing: 8) {
                captureStrip
                drivesCard
            }
        }
        .overlay(alignment: .topLeading) {
            if let appVolume { AppVolumeOverlay(model: appVolume) }
        }
        .foregroundStyle(.white)
    }

    /// Color picker and text capture, with the recently picked colors.
    private var captureStrip: some View {
        HStack(spacing: 6) {
            pickColorButton
            captureTextButton
            Spacer(minLength: 0)
            // Only as many swatches as fit, newest first.
            ViewThatFits(in: .horizontal) {
                ForEach((0...tools.pickedColors.count).reversed(), id: \.self) { count in
                    HStack(spacing: 4) {
                        ForEach(tools.pickedColors.prefix(count), id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                                .frame(width: 14, height: 14)
                                .contentShape(Circle())
                                .onTapGesture { tools.copyColor(hex) }
                                .help(Text(hex))
                        }
                    }
                }
            }
        }
        .padding(8)
        .surface(RoundedRectangle(cornerRadius: 14))
    }

    private var pickColorButton: some View {
        CaptureButton(symbol: "eyedropper", help: String(localized: "Pick a color from the screen")) { tools.pickColor() }
    }

    private var captureTextButton: some View {
        CaptureButton(symbol: "text.viewfinder", help: String(localized: "Capture text from the screen"),
                      active: tools.isCapturingText) { tools.captureText() }
    }

    private var drivesCard: some View {
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surface(RoundedRectangle(cornerRadius: 14))
    }
}

private struct CaptureButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(active ? Color.accentColor : .white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }
}

private extension Color {
    /// From "#RRGGBB".
    init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
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
            // A single word shrinks rather than breaking mid-word on a narrow tile.
            Text(title).font(.system(size: 12, weight: .semibold))
                .lineLimit(title.contains(" ") ? 2 : 1).minimumScaleFactor(0.75)
            detail.foregroundStyle(.white.opacity(0.6))
        }
        .padding(12)
        .frame(minWidth: 80, maxWidth: 98, alignment: .leading)
        .frame(maxHeight: .infinity)
        .surface(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: action)
        // Laid out before the capture column, which gets what is left but never less than it needs.
        .layoutPriority(1)
    }
}

/// Opens the app volume list from the Output tile.
private struct AppVolumeButton: View {
    @ObservedObject var model: AppVolumeModel

    var body: some View {
        let turnedDown = model.apps.contains { $0.volume < 1 }
        Button { model.isShowingList.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(turnedDown ? Color.accentColor : .white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text("App volume"))
    }
}

/// The apps playing sound, each with a volume slider, laid over the left of the Tools tab.
private struct AppVolumeOverlay: View {
    @ObservedObject var model: AppVolumeModel
    private static let rowHeight: CGFloat = 20
    private static let rowSpacing: CGFloat = 3

    var body: some View {
        if model.isShowingList {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("App volume", systemImage: "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button { model.isShowingList = false } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
                            .background(Circle().fill(.white.opacity(0.12))).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(Text("Close"))
                }
                if model.needsPermission {
                    Text("Nunsseop needs permission to record system audio to change an app’s volume.")
                        .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                } else if model.mayNeedPermission {
                    Text("No sound has come through yet. If the app is playing, Nunsseop may need permission to record system audio.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                } else if model.apps.isEmpty {
                    Text("No apps are playing sound").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                if !model.apps.isEmpty {
                    // Four rows show; more scroll.
                    let shown = CGFloat(min(model.apps.count, 4))
                    ScrollView(.vertical) {
                        VStack(spacing: Self.rowSpacing) {
                            ForEach(model.apps) { app in row(app) }
                        }
                    }
                    .scrollIndicators(model.apps.count > 4 ? .automatic : .never)
                    .frame(maxHeight: shown * Self.rowHeight + (shown - 1) * Self.rowSpacing)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 280, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.09)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
    }

    private func row(_ app: AppVolumeModel.App) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
            Text(app.name).font(.system(size: 11)).lineLimit(1).frame(width: 74, alignment: .leading)
            Slider(value: Binding(get: { app.volume }, set: { model.setVolume($0, for: app.id) }), in: 0...1) { editing in
                if !editing { model.finishEditing(app.id) }
            }
            .controlSize(.mini)
            Text("\(Int((app.volume * 100).rounded()))%")
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
    }
}
