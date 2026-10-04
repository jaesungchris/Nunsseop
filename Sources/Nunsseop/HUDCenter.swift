import AppKit
import Combine

enum HUDEvent: Equatable {
    case volume(Float, muted: Bool)
    case brightness(Float)
    case keyboard(Float)
    case power(PowerState)
    case headphones(HeadphoneBattery)
}

/// Collects system events (volume, brightness, power, headphones) and exposes
/// the one the notch should briefly show.
@MainActor
final class HUDCenter: ObservableObject {
    @Published private(set) var event: HUDEvent?
    @Published private(set) var power: PowerState?
    @Published private(set) var interceptorNeedsPermission = false

    private let settings: AppSettings
    private let audio = SystemAudio()
    private let powerMonitor = PowerMonitor()
    private let interceptor = MediaKeyInterceptor()
    private var dismissWork: DispatchWorkItem?
    private var lastHeadphones: HeadphoneBattery?
    private var headphoneCheckInFlight = false
    private let ddcQueue = DispatchQueue(label: "nunsseop.ddc")
    /// External displays answering DDC, with the last known brightness as a fraction of their maximum.
    private var externalDisplays: [(service: CFTypeRef, max: Int)] = []
    private var externalLevel: Float?
    private var lastKeyboardLevel: Float = 0.5
    private var pendingExternalLevel: Float?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        audio.onVolumeChange = { [weak self] volume, muted in
            guard let self, self.settings.volumeHUDEnabled else { return }
            self.show(.volume(volume, muted: muted))
        }
        audio.onOutputDeviceChange = { [weak self] in self?.checkHeadphones(after: 4) }
        audio.start()

        powerMonitor.onChange = { [weak self] state in
            guard let self else { return }
            let pluggedChanged = self.power?.onAC != state.onAC
            self.power = state
            if pluggedChanged && self.settings.chargingHUDEnabled { self.show(.power(state), duration: 2.5) }
        }
        powerMonitor.start()
        power = powerMonitor.state

        // The tap callback runs on the main run loop.
        interceptor.handlesVolume = { [weak self] in MainActor.assumeIsolated { self?.audio.canSetVolume ?? false } }
        interceptor.handlesBrightness = { [weak self] in
            MainActor.assumeIsolated { BuiltInBrightness.isAvailable || self?.externalTarget != nil }
        }
        interceptor.handlesKeyboard = { KeyboardBacklight.isAvailable }
        refreshExternalDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExternalDisplays() }
        }
        interceptor.onKey = { [weak self] key, fine in self?.handle(key, fine: fine) }
        settings.$replaceSystemHUD
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setInterception(enabled) }
            .store(in: &cancellables)

        checkHeadphones(after: 1)

        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--demo-hud"), i + 1 < CommandLine.arguments.count {
            let demo: HUDEvent = switch CommandLine.arguments[i + 1] {
            case "power": .power(PowerState(percent: 76, isCharging: true, onAC: true))
            case "brightness": .brightness(0.6)
            case "keyboard": .keyboard(0.7)
            default: .headphones(HeadphoneBattery(name: "AirPods Pro", levels: [(String(localized: "Left"), 90), (String(localized: "Right"), 85), (String(localized: "Case"), 60)]))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.show(demo, duration: 30) }
        }
        #endif
    }

    func retryInterception() {
        setInterception(settings.replaceSystemHUD)
    }

    private func setInterception(_ enabled: Bool) {
        guard enabled else {
            interceptor.stop()
            interceptorNeedsPermission = false
            return
        }
        if !MediaKeyInterceptor.isTrusted {
            MediaKeyInterceptor.requestTrust()
            interceptorNeedsPermission = true
            return
        }
        interceptorNeedsPermission = !interceptor.start()
    }

    private func handle(_ key: MediaKey, fine: Bool) {
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .volumeUp:
            audio.setVolume(audio.volume + step)
        case .volumeDown:
            audio.setVolume(audio.volume - step)
        case .mute:
            audio.setMuted(!audio.isMuted)
        case .brightnessUp, .brightnessDown:
            let delta = key == .brightnessUp ? step : -step
            if BuiltInBrightness.isAvailable && (pointerIsOnBuiltInDisplay || externalTarget == nil),
               let level = BuiltInBrightness.level {
                let new = min(1, max(0, level + delta))
                BuiltInBrightness.set(new)
                show(.brightness(new))
            } else if let level = externalLevel, let display = externalTarget {
                let new = min(1, max(0, level + delta))
                externalLevel = new
                show(.brightness(new))
                // Coalesce key repeats: only the latest value is written.
                let alreadyQueued = pendingExternalLevel != nil
                pendingExternalLevel = new
                guard !alreadyQueued else { return }
                ddcQueue.async { [weak self] in
                    let value = DispatchQueue.main.sync { () -> Float? in
                        MainActor.assumeIsolated {
                            defer { self?.pendingExternalLevel = nil }
                            return self?.pendingExternalLevel
                        }
                    }
                    if let value {
                        ExternalBrightness.set(Int((Float(display.max) * value).rounded()), on: display.service)
                    }
                }
            }
        case .keyboardUp, .keyboardDown, .keyboardToggle:
            guard let level = KeyboardBacklight.level else { return }
            let new: Float
            switch key {
            case .keyboardUp: new = min(1, level + step)
            case .keyboardDown: new = max(0, level - step)
            default: new = level > 0 ? 0 : lastKeyboardLevel
            }
            if level > 0 { lastKeyboardLevel = level }
            KeyboardBacklight.set(new)
            show(.keyboard(new))
        }
        // Volume HUDs come from the audio listener; show one even if it stays silent at the limits.
        if key == .volumeUp || key == .volumeDown || key == .mute {
            show(.volume(audio.volume, muted: audio.isMuted))
        }
    }

    /// DDC services can't be matched to screens here, so external brightness is only
    /// handled when exactly one external screen is connected and it answers DDC.
    private var externalTarget: (service: CFTypeRef, max: Int)? {
        let externalScreens = NSScreen.screens.filter { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
        guard externalScreens.count <= 1, externalDisplays.count == 1 else { return nil }
        return externalDisplays[0]
    }

    private var pointerIsOnBuiltInDisplay: Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// Finds external displays that answer DDC and reads their brightness once.
    private func refreshExternalDisplays() {
        ddcQueue.async { [weak self] in
            var found: [(service: CFTypeRef, max: Int)] = []
            var level: Float?
            for service in ExternalBrightness.services() {
                guard let reading = ExternalBrightness.level(of: service) else { continue }
                found.append((service, reading.max))
                if level == nil { level = Float(reading.current) / Float(reading.max) }
            }
            DispatchQueue.main.async {
                self?.externalDisplays = found
                self?.externalLevel = level
            }
        }
    }

    private func checkHeadphones(after delay: Double) {
        guard settings.headphoneHUDEnabled, !headphoneCheckInFlight else { return }
        headphoneCheckInFlight = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            let battery = HeadphoneBatteryReader.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.headphoneCheckInFlight = false
                defer { self.lastHeadphones = battery }
                guard let battery, battery.name != self.lastHeadphones?.name else { return }
                self.show(.headphones(battery), duration: 3.5)
            }
        }
    }

    func show(_ newEvent: HUDEvent, duration: Double = 1.6) {
        dismissWork?.cancel()
        event = newEvent
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.event = nil }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
