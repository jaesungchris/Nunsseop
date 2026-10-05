import AppKit
import CoreAudio
import NunsseopAtomics
import UniformTypeIdentifiers

/// Per-app volume (experimental, macOS 14.2+). An app turned below 100% is captured by a Core Audio
/// process tap, which silences it while the tap is read, and played back through a private aggregate
/// device on the current output at the chosen gain. At 100% the tap is removed, so it costs nothing.
///
/// The tap uses "muted when tapped": CATapDescription.h says the app is muted only "for the duration
/// of the read activity on the tap". If Nunsseop quits or crashes, nothing reads the tap any more and
/// the app plays normally again. The tap and the aggregate device are private to this process.
@MainActor
final class AppVolumeModel: ObservableObject {
    struct App: Identifiable, Equatable {
        /// The app's bundle ID; its helper processes are grouped under it.
        let id: String
        let name: String
        let icon: NSImage
        var volume: Double
    }

    /// The audio processes of one app.
    struct Group: Equatable {
        let app: String
        var objects: [AudioObjectID]
        /// Whether any of them is playing sound right now.
        var sounding: Bool
    }

    /// Apps playing sound, and apps turned down that are still running.
    @Published private(set) var apps: [App] = []
    /// Set when a tap could not be made, which means audio recording isn't allowed.
    @Published private(set) var needsPermission = false
    /// Set when a tap has carried only silence for a while. That is what a tap without permission
    /// hears, but also what a paused tab or a quiet call sounds like, so the volume is left alone.
    @Published private(set) var mayNeedPermission = false
    /// The list in the Tools tab is open.
    @Published var isShowingList = false

    nonisolated static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true } else { return false }
    }

    /// Our aggregate devices start with this UID, so device lists and the microphone check can skip them.
    nonisolated static let deviceUIDPrefix = "io.github.namekun.Nunsseop.app-volume."

    private var isEnabled = false
    private var isListing = false
    private var timer: Timer?
    private var scanning = false
    private var scanAgain = false
    /// Slider positions below 100%, by app.
    private var volumes: [String: Double] = [:]
    private var taps: [String: ProcessTap] = [:]
    /// Every app with audio processes at the last scan, sounding or not.
    private var groups: [String: Group] = [:]
    /// The app each process object belongs to; nil for daemons.
    private var owners: [AudioObjectID: String?] = [:]
    /// Once a tap has carried sound, audio recording is evidently allowed.
    private var permissionConfirmed = false
    /// Apps whose tap couldn't be made on a new output device; they get one more try on the next device change.
    private var retryOnOutputChange: Set<String> = []
    private var listeners: [(selector: AudioObjectPropertySelector, block: AudioObjectPropertyListenerBlock)] = []
    #if DEBUG
    private var isDemo = false
    #endif

    /// `listing` is true while the Tools tab is on screen; the list is refreshed only then.
    func update(enabled: Bool, listing: Bool) {
        if enabled != isEnabled {
            isEnabled = enabled
            if !enabled {
                stopAll()
                volumes = [:]
                apps = []
                needsPermission = false
                mayNeedPermission = false
            }
        }
        #if DEBUG
        if enabled && CommandLine.arguments.contains("--demo-app-volume") {
            showDemo()
            return
        }
        #endif
        let listing = enabled && listing && Self.isSupported
        guard listing != isListing else { return }
        isListing = listing
        timer?.invalidate()
        timer = nil
        guard listing else {
            isShowingList = false
            return
        }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        timer?.tolerance = 0.2
    }

    func setVolume(_ volume: Double, for app: String) {
        let volume = min(max(volume, 0), 1)
        needsPermission = false
        if let index = apps.firstIndex(where: { $0.id == app }) { apps[index].volume = volume }
        #if DEBUG
        if isDemo { return }
        #endif
        volumes[app] = volume < 1 ? volume : nil
        if let tap = taps[app] {
            tap.setGain(Self.gain(for: volume))
        } else if volume < 1 {
            startTap(for: app)
        }
    }

    /// Back at 100% the tap goes once the slider is let go, so dragging through 100% doesn't rebuild it.
    func finishEditing(_ app: String) {
        if volumes[app] == nil { removeTap(for: app) }
    }

    /// Removes every tap and waits until they are gone; for quitting.
    func shutdown() {
        stopAll()
        ProcessTap.waitForPendingWork()
    }

    /// Sliders move in amplitude squared, which sounds closer to even steps than a straight line.
    nonisolated static func gain(for volume: Double) -> Float {
        let volume = Float(min(max(volume, 0), 1))
        return volume * volume
    }

    // MARK: Processes

    private func scan() {
        guard !scanning else {
            scanAgain = true
            return
        }
        scanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let processes = CallMonitor.audioProcesses()
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                if let processes, self.isEnabled { self.apply(processes) }
                if self.scanAgain {
                    self.scanAgain = false
                    self.scan()
                }
            }
        }
    }

    private func apply(_ processes: [CallMonitor.AudioProcess]) {
        owners = owners.filter { id, _ in processes.contains { $0.objectID == id } }
        let found = Self.groups(processes, own: getpid()) { process in
            if let owner = owners[process.objectID] { return owner }
            let owner = Self.appBundleID(for: process)
            owners[process.objectID] = owner
            return owner
        }
        groups = Dictionary(uniqueKeysWithValues: found.map { ($0.app, $0) })

        // A tap follows its app's processes: none left means the app quit, a new one (say a browser's
        // new helper) has to join the tap.
        for (app, tap) in taps {
            guard let group = groups[app] else {
                removeTap(for: app)
                volumes[app] = nil
                continue
            }
            if Set(group.objects) != Set(tap.objects) {
                startTap(for: app)
            } else if tap.heard {
                permissionConfirmed = true
                mayNeedPermission = false
            } else if !permissionConfirmed && group.sounding && Date().timeIntervalSince(tap.startedAt) > 3 {
                // Without permission the tap carries only silence, but so does a paused tab or a quiet
                // call: only a hint shows, and the tap and the volume stay.
                mayNeedPermission = true
            }
        }

        for app in retryOnOutputChange where groups[app] == nil {
            removeTap(for: app)
            volumes[app] = nil
        }

        guard isListing else { return }
        let listed: [App] = found.filter { $0.sounding || volumes[$0.app] != nil }.map { group in
            let info = Self.appInfo(group.app)
            return App(id: group.app, name: info.name, icon: info.icon, volume: volumes[group.app] ?? 1)
        }
        .sorted { (a: App, b: App) in a.name.localizedStandardCompare(b.name) == .orderedAscending }
        if listed != apps { apps = listed }
    }

    /// Groups processes by app, leaving out this app's own and processes that belong to no app.
    nonisolated static func groups(_ processes: [CallMonitor.AudioProcess], own: pid_t,
                                   app: (CallMonitor.AudioProcess) -> String?) -> [Group] {
        var groups: [String: Group] = [:]
        for process in processes where process.pid != own && process.objectID != 0 {
            guard let id = app(process) else { continue }
            groups[id, default: Group(app: id, objects: [], sounding: false)].objects.append(process.objectID)
            if process.isRunningOutput { groups[id]?.sounding = true }
        }
        return groups.values.sorted { $0.app < $1.app }
    }

    /// The app a process belongs to: helpers map to the app around them; daemons and parts of macOS
    /// (login window, Control Center, the charging chime) to nothing.
    nonisolated static func appBundleID(for process: CallMonitor.AudioProcess) -> String? {
        if let call = CallMonitor.appBundleID(for: process.bundleID) { return call }
        let url: URL?
        if process.bundleID.lowercased().hasPrefix("com.apple.webkit.") {
            // WebKit's processes play for whichever app hosts the web view: Safari, Mail, Messages or any
            // app with a WKWebView. Without that app they are left out rather than guessed.
            guard let host = responsiblePID(for: process.pid), host != process.pid else { return nil }
            url = NSRunningApplication(processIdentifier: host)?.bundleURL
        } else {
            url = NSRunningApplication(processIdentifier: process.pid)?.bundleURL
                ?? installedApp(for: process.bundleID, lookup: InstalledApps.url(for:))
        }
        guard let path = url?.path, let app = outermostApp(in: path), !app.hasPrefix("/System/Library/"),
              let id = Bundle(path: app)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
        return id
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// The private libSystem call macOS uses to tie XPC services to the app they work for; looked up at run time.
    private nonisolated static let responsibleFunction: ResponsibleFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    /// The process macOS holds responsible for `pid`, or nil when it can't be told.
    nonisolated static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard pid > 0, let responsible = responsibleFunction?(pid), responsible > 0 else { return nil }
        return responsible
    }

    /// The outermost .app bundle in a path, so a helper inside an app maps to that app.
    nonisolated static func outermostApp(in path: String) -> String? {
        let path = path.hasSuffix("/") ? path : path + "/"
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.upperBound].dropLast())
    }

    /// Looks up the bundle ID, then ever shorter forms of it, until an app is found:
    /// "com.google.Chrome.helper" finds "com.google.Chrome".
    nonisolated static func installedApp<App>(for bundleID: String, lookup: (String) -> App?) -> App? {
        var parts = bundleID.split(separator: ".")
        while parts.count >= 2 {
            if let app = lookup(parts.joined(separator: ".")) { return app }
            parts.removeLast()
        }
        return nil
    }

    private static func appInfo(_ bundleID: String) -> (name: String, icon: NSImage) {
        guard let url = InstalledApps.url(for: bundleID) else { return (bundleID, NSWorkspace.shared.icon(for: .application)) }
        return (InstalledApps.name(at: url), InstalledApps.icon(at: url))
    }

    // MARK: Taps

    /// Makes the app's tap, replacing one it has. The listeners stay, as this also runs from one of them.
    /// `mayRetry` is set after an output device change: a tap that can't be made then is tried once more
    /// on the next change before the volume is given up.
    private func startTap(for app: String, mayRetry: Bool = false) {
        let old = taps.removeValue(forKey: app)
        retryOnOutputChange.remove(app)
        guard let group = groups[app], let volume = volumes[app], let output = Self.defaultOutputUID() else {
            old?.stop()
            updateListeners()
            return
        }
        // A replacement starts at the volume the old tap plays at, and the old tap goes only after the new
        // one has started (both on the same serial queue), so the app is never heard at full volume between them.
        let gain = Self.gain(for: volume)
        let tap = ProcessTap(objects: group.objects, gain: gain, startingGain: old == nil ? 1 : gain)
        taps[app] = tap
        updateListeners()
        tap.start(output: output) { [weak self] started in
            guard let self, self.taps[app] === tap, !started else { return }
            if mayRetry {
                // The listeners stay, as the retry waits for them.
                self.taps.removeValue(forKey: app)?.stop()
                self.retryOnOutputChange.insert(app)
            } else {
                self.failed(app)
            }
        }
        old?.stop()
        // Checks that the tap carries sound once it has had time to start.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.scan() }
    }

    private func removeTap(for app: String) {
        taps.removeValue(forKey: app)?.stop()
        retryOnOutputChange.remove(app)
        updateListeners()
    }

    /// The tap couldn't be made: the slider goes back and the list asks for permission.
    private func failed(_ app: String) {
        removeTap(for: app)
        volumes[app] = nil
        if let index = apps.firstIndex(where: { $0.id == app }) { apps[index].volume = 1 }
        needsPermission = true
    }

    private func stopAll() {
        for app in Array(taps.keys) { removeTap(for: app) }
        retryOnOutputChange = []
        updateListeners()
    }

    /// While any tap runs or waits for a retry: a new output device gets new taps, and process changes are followed at once.
    private func updateListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if taps.isEmpty && retryOnOutputChange.isEmpty {
            for listener in listeners {
                var address = Self.address(listener.selector)
                AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener.block)
            }
            listeners = []
        } else if listeners.isEmpty {
            let outputChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // An app already retried once reports failure this time.
                    let retrying = self.retryOnOutputChange
                    for app in Set(self.taps.keys).union(retrying) { self.startTap(for: app, mayRetry: !retrying.contains(app)) }
                }
            }
            let processesChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scan() }
            }
            listeners = [(kAudioHardwarePropertyDefaultOutputDevice, outputChanged),
                         (kAudioHardwarePropertyProcessObjectList, processesChanged)]
            for listener in listeners {
                var address = Self.address(listener.selector)
                AudioObjectAddPropertyListenerBlock(system, &address, .main, listener.block)
            }
        }
    }

    // MARK: Devices

    private nonisolated static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated static func uid(of device: AudioObjectID, selector: AudioObjectPropertySelector = kAudioDevicePropertyDeviceUID) -> String? {
        var address = address(selector)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard device != 0, AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    /// One of the aggregate devices made here for a tap.
    nonisolated static func isOwnDevice(_ device: AudioObjectID) -> Bool {
        uid(of: device)?.hasPrefix(deviceUIDPrefix) == true
    }

    private static func defaultOutputUID() -> String? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        return uid(of: device)
    }

    #if DEBUG
    /// `--demo-app-volume` fills the list with made-up apps for snapshots; nothing is tapped.
    private func showDemo() {
        isDemo = true
        guard apps.isEmpty else { return }
        let demo: [(String, String, Double)] = [("com.spotify.client", "Spotify", 1), ("com.google.Chrome", "Google Chrome", 0.45),
                                                ("com.apple.Safari", "Safari", 1), ("com.hnc.Discord", "Discord", 0.7),
                                                ("us.zoom.xos", "zoom.us", 1)]
        apps = demo.map { id, name, volume in
            App(id: id, name: name, icon: InstalledApps.icon(for: id) ?? NSWorkspace.shared.icon(for: .application), volume: volume)
        }
        isShowingList = true
    }
    #endif
}

/// One process tap and the private aggregate device that plays it back. Made and torn down on a
/// serial queue; the IO thread reads the gain without locks or allocations.
final class ProcessTap: @unchecked Sendable {
    let objects: [AudioObjectID]
    let startedAt = Date()

    /// [0] target gain and [1] "sound seen", shared atomically; [2] the gain in use, IO thread only.
    private let state = UnsafeMutablePointer<Float>.allocate(capacity: 3)
    // Touched only on `queue`.
    private var tapID = AudioObjectID(0)
    private var deviceID = AudioObjectID(0)
    private var procID: AudioDeviceIOProcID?

    private static let queue = DispatchQueue(label: "nunsseop.app-volume", qos: .userInitiated)

    /// `startingGain` is where the first buffer's ramp begins: full volume, where an untapped app was,
    /// or the gain of the tap this one replaces.
    init(objects: [AudioObjectID], gain: Float, startingGain: Float = 1) {
        self.objects = objects
        state.initialize(from: [gain, 0, startingGain], count: 3)
    }

    func setGain(_ gain: Float) {
        nunsseop_atomic_store_float(state, gain)
    }

    /// Whether the tap has carried any sound yet.
    var heard: Bool {
        nunsseop_atomic_load_float(state + 1) != 0
    }

    func start(output deviceUID: String, completion: @escaping @MainActor (Bool) -> Void) {
        Self.queue.async {
            let started = self.make(output: deviceUID)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(started) } }
        }
    }

    /// Call once; the tap can't be used afterwards.
    func stop() {
        Self.queue.async {
            self.destroy()
            self.state.deallocate()
        }
    }

    static func waitForPendingWork() {
        queue.sync {}
    }

    private func make(output deviceUID: String) -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "Nunsseop app volume"
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
              let tapUID = AppVolumeModel.uid(of: tapID, selector: kAudioTapPropertyUID) else {
            destroy()
            return false
        }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Nunsseop app volume",
            kAudioAggregateDeviceUIDKey: AppVolumeModel.deviceUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        var procID: AudioDeviceIOProcID?
        guard AudioHardwareCreateAggregateDevice(composition as CFDictionary, &deviceID) == noErr,
              AudioDeviceCreateIOProcID(deviceID, Self.ioProc, UnsafeMutableRawPointer(state), &procID) == noErr,
              let procID else {
            destroy()
            return false
        }
        self.procID = procID
        useOnlyTapInput(procID)
        guard AudioDeviceStart(deviceID, procID) == noErr else {
            destroy()
            return false
        }
        return true
    }

    private func destroy() {
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        if deviceID != 0 {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = 0
        }
        if #available(macOS 14.2, *), tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
    }

    /// An output with a microphone, such as a headset, adds its input to the aggregate device. Only the
    /// tap, the last input stream, is turned on, so the microphone isn't started.
    ///
    /// The sub-device's inputs stay in the aggregate all the same. Keeping them out entirely (say, so
    /// Bluetooth headphones are never asked for their microphone and drop to the call profile) has no
    /// documented setting: AudioHardware.h describes kAudioSubDeviceInputChannelsKey only as reporting a
    /// sub-device's channel count, not as something to set, so it isn't relied on here.
    private func useOnlyTapInput(_ procID: AudioDeviceIOProcID) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return }
        let streams = Int(size) / MemoryLayout<AudioStreamID>.size
        guard streams > 1,
              let countOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mNumberStreams),
              let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) else { return }
        let byteCount = flagsOffset + streams * MemoryLayout<UInt32>.size
        let usage = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { usage.deallocate() }
        usage.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        usage.storeBytes(of: UInt32(streams), toByteOffset: countOffset, as: UInt32.self)
        for stream in 0..<streams {
            usage.storeBytes(of: UInt32(stream == streams - 1 ? 1 : 0), toByteOffset: flagsOffset + stream * MemoryLayout<UInt32>.size, as: UInt32.self)
        }
        var usageAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIOProcStreamUsage, mScope: kAudioObjectPropertyScopeInput,
                                                      mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(deviceID, &usageAddress, 0, nil, UInt32(byteCount), usage)
    }

    /// Runs on the real-time IO thread: no locks, no allocations, no Objective-C.
    private static let ioProc: AudioDeviceIOProc = { _, _, input, _, output, _, clientData in
        guard let state = clientData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let target = nunsseop_atomic_load_float(state)
        if TapMixer.render(input: input, output: output, from: state[2], to: target) {
            nunsseop_atomic_store_float(state + 1, 1)
        }
        state[2] = target
        return noErr
    }
}

/// The IO thread's work: the tap's audio to the output, scaled by a gain that ramps across each buffer.
enum TapMixer {
    /// The gain for `frame` of a buffer of `frames`, moving in a straight line from `from` to reach `to`
    /// on the last frame, so a gain change never jumps (which would click).
    static func gain(from: Float, to: Float, frame: Int, frames: Int) -> Float {
        guard frames > 0, from != to else { return to }
        return from + (to - from) * Float(frame + 1) / Float(frames)
    }

    /// Writes every output buffer from the tap, the last input buffer (interleaved Float32). Output channels
    /// past the tap's get silence; a mono output gets both sides. Returns whether the tap had any sound.
    static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
                       from: Float, to: Float) -> Bool {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        var source: UnsafeMutablePointer<Float>?
        var sourceChannels = 0
        var sourceFrames = 0
        if inputs.count > 0 {
            let tap = inputs[inputs.count - 1]
            if tap.mNumberChannels > 0, let data = tap.mData {
                source = data.assumingMemoryBound(to: Float.self)
                sourceChannels = Int(tap.mNumberChannels)
                sourceFrames = Int(tap.mDataByteSize) / (MemoryLayout<Float>.size * sourceChannels)
            }
        }
        var outputChannels = 0
        for buffer in outputs { outputChannels += Int(buffer.mNumberChannels) }
        let downmix = outputChannels == 1 && sourceChannels > 1

        var heard = false
        var firstChannel = 0
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            defer { firstChannel += channels }
            guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for frame in 0..<frames {
                let frameGain = gain(from: from, to: to, frame: frame, frames: frames)
                for channel in 0..<channels {
                    var sample: Float = 0
                    if let source, frame < sourceFrames {
                        let base = frame * sourceChannels
                        if downmix {
                            sample = (source[base] + source[base + 1]) * 0.5
                        } else if firstChannel + channel < sourceChannels {
                            sample = source[base + firstChannel + channel]
                        }
                    }
                    if sample != 0 { heard = true }
                    data[frame * channels + channel] = sample * frameGain
                }
            }
        }
        return heard
    }
}
