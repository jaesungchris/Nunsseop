import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel never becomes active, so the first click must reach SwiftUI gestures directly.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchWindowController {
    private let model: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?
    private var openWork: DispatchWorkItem?
    private var swipe = CGVector.zero
    private var swipeFired = false
    private var swipeIdleWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var pillWidthObserver: AnyCancellable?
    private var updatesObserver: AnyCancellable?
    private var settingsObservers: [AnyCancellable] = []
    /// Keeps the AI limits fresh while an idle ear shows them.
    private var aiUsageTimer: Timer?
    private var hotKey: GlobalHotKey?
    private var resignObserver: NSObjectProtocol?

    /// A watcher that only feeds the notch: it runs while its setting is on and the panel is on screen.
    private struct Feature {
        let setting: KeyPath<AppSettings, Bool>
        let changes: KeyPath<AppSettings, Published<Bool>.Publisher>
        let start: () -> Void
        /// `hiding` is true when only the panel went away; the setting is still on.
        let stop: (_ hiding: Bool) -> Void
    }

    /// Everything else runs regardless of the panel: now playing, the HUD (it may be taking over the volume and
    /// brightness keys), tools, the screenshot and download watchers (they still fill the shelf), the AI usage
    /// timer, lyrics, weather and update checks.
    private lazy var features: [Feature] = {
        let model = model
        return [
            Feature(setting: \.clipboardTab, changes: \.$clipboardTab,
                    start: { model.clipboard.start() }, stop: { _ in model.clipboard.stop() }),
            Feature(setting: \.capsLockHUD, changes: \.$capsLockHUD,
                    start: { model.capsLock.start() }, stop: { _ in model.capsLock.stop() }),
            Feature(setting: \.localNotifications, changes: \.$localNotifications,
                    start: { model.notifyServer.start() }, stop: { _ in model.notifyServer.stop() }),
            Feature(setting: \.callIsland, changes: \.$callIsland,
                    start: { model.calls.start() }, stop: { _ in model.calls.stop() }),
            // Hiding keeps the last camera/mic state, so showing again during a call already announced stays quiet.
            Feature(setting: \.privacyIndicator, changes: \.$privacyIndicator,
                    start: { model.privacy.start() }, stop: { hiding in model.privacy.stop(clearing: !hiding) }),
            Feature(setting: \.peripheralBatteries, changes: \.$peripheralBatteries,
                    start: { model.peripherals.start() }, stop: { _ in model.peripherals.stop() }),
        ]
    }()

    /// Opens the notch on the Search tab with the keyboard focus in the search field.
    private func openSearch() {
        guard panel.isVisible else { return }
        if model.isExpanded && model.tab == .search {
            model.collapse()
            panel.ignoresMouseEvents = true
            return
        }
        model.tab = .search
        model.expand()
        model.pinned = true
        panel.ignoresMouseEvents = false
        panel.makeKey()
        model.search.focusToken += 1
    }

    init() {
        let geometry = NotchGeometry.pickScreen(preferredName: AppSettings.shared.displayName).map { NotchGeometry(screen: $0, pillWidth: AppSettings.shared.pillWidth) }
            ?? NotchGeometry(fallbackWidth: AppSettings.shared.pillWidth)
        model = NotchViewModel(geometry: geometry, settings: .shared)
        panel = NotchPanel(frame: geometry.panelFrame)

        let hosting = FirstMouseHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting

        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-dir"), i + 1 < CommandLine.arguments.count {
            snapshotter = DebugSnapshotter(directory: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
                                           view: hosting, model: model)
        }
        if CommandLine.arguments.contains("--demo-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsWindowController.shared.show() }
        }
        #endif
    }

    #if DEBUG
    private var snapshotter: DebugSnapshotter?
    #endif

    func show() {
        panel.setFrame(model.geometry.panelFrame, display: true)
        panel.orderFrontRegardless()
        updateVisibility()
        installMonitors()
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--demo-tab"), i + 1 < CommandLine.arguments.count,
           let tab = NotchTab(rawValue: CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                if let j = CommandLine.arguments.firstIndex(of: "--demo-timer-mode"), j + 1 < CommandLine.arguments.count,
                   let mode = TimerModel.Mode(rawValue: CommandLine.arguments[j + 1]) {
                    self.model.timer.mode = mode
                }
                self.model.tab = tab
                self.model.expand()
                self.model.pinned = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.model.expand()
                    self.snapshotter?.capture(label: "tab")
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--demo-search"), i + 1 < CommandLine.arguments.count {
            let query = CommandLine.arguments[i + 1]
            model.search.loadApps()
            model.search.query = query
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.model.tab = .search
                self.model.expand()
                self.model.search.query = query
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.model.tab = .search
                    self.model.expand()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.snapshotter?.capture(label: "search") }
                }
            }
        }
        #endif
        model.nowPlaying.start()
        model.hud.start()
        model.tools.start()
        model.tools.onNotice = { [weak self] symbol, title, detail in
            self?.model.hud.show(.notice(symbol: symbol, title: title, detail: detail), duration: 2.5)
        }
        model.screenshots.onScreenshot = { [weak self] url in
            guard let self else { return }
            self.model.shelf.add([url])
            self.model.hud.show(.notice(symbol: "camera.viewfinder", title: String(localized: "Screenshot added to the shelf"),
                                        detail: url.lastPathComponent), duration: 3)
        }
        model.screenshots.start()
        model.capsLock.onChange = { [weak self] on in
            guard let self, self.model.settings.capsLockHUD else { return }
            self.model.hud.show(.notice(symbol: on ? "capslock.fill" : "capslock",
                                        title: on ? String(localized: "Caps Lock on") : String(localized: "Caps Lock off"),
                                        detail: nil), duration: 1.2)
        }
        model.downloads.onStart = { [weak self] name in
            guard let self, self.model.settings.downloadAlerts else { return }
            self.model.hud.show(.notice(symbol: "arrow.down.circle", title: String(localized: "Downloading"), detail: name), duration: 3)
        }
        model.downloads.onFinish = { [weak self] url in
            guard let self else { return }
            if self.model.settings.downloadsToShelf { self.model.shelf.add([url]) }
            if self.model.settings.downloadAlerts {
                self.model.hud.show(.notice(symbol: "checkmark.circle.fill", title: String(localized: "Download finished"),
                                            detail: url.lastPathComponent), duration: 4)
            }
        }
        model.downloads.start()
        model.peripherals.onLow = { [weak self] device in
            self?.model.hud.show(.notice(symbol: device.symbol, title: String(localized: "Low battery"),
                                         detail: "\(device.name) \(device.percent)%"), duration: 5)
        }
        model.privacy.onChange = { [weak self] camera, mic in
            guard let self, self.model.settings.privacyIndicator else { return }
            let title = camera && mic ? String(localized: "Camera and microphone in use")
                : camera ? String(localized: "Camera in use") : String(localized: "Microphone in use")
            self.model.hud.show(.notice(symbol: camera ? "video.fill" : "mic.fill", title: title, detail: nil), duration: 3)
        }
        model.recorder.onFinished = { [weak self] url in
            guard let self, let url else { return }
            self.model.shelf.add([url])
            self.model.hud.show(.notice(symbol: "record.circle", title: String(localized: "Recording saved"),
                                        detail: url.lastPathComponent), duration: 4)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.pinned else { return }
                self.model.collapse()
                self.panel.ignoresMouseEvents = true
            }
        }
        settingsObservers.append(model.settings.$searchHotkey.combineLatest(model.settings.$searchHotKey, model.settings.$recordingShortcut)
            .sink { [weak self] enabled, combo, recording in
                guard let self else { return }
                self.hotKey = nil
                guard enabled && !recording else { return }
                self.hotKey = GlobalHotKey(combo: combo) { [weak self] in self?.openSearch() }
                self.model.settings.searchShortcutTaken = self.hotKey?.isRegistered != true
            })
        model.search.onFinish = { [weak self] in
            guard let self, self.model.isExpanded else { return }
            self.model.collapse()
            self.panel.ignoresMouseEvents = true
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, let self else { return event }
            MainActor.assumeIsolated { self.model.collapse(); self.panel.ignoresMouseEvents = true }
            return nil
        }) {
            monitors.append(keys)
        }
        settingsObservers.append(model.settings.$weatherCity.combineLatest(model.settings.$headerWeather,
                                                                           model.settings.$idleLeft, model.settings.$idleRight)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] city, header, left, right in
                self?.model.weather.setCity(header || left == .weather || right == .weather ? city : "")
            })
        settingsObservers.append(model.settings.$idleLeft.combineLatest(model.settings.$idleRight)
            .map { $0.usesAIUsage || $1.usesAIUsage }
            .removeDuplicates()
            .sink { [weak self] shown in
                guard let self else { return }
                self.aiUsageTimer?.invalidate()
                self.aiUsageTimer = nil
                guard shown else { return }
                self.model.aiUsage.refresh(includeTokens: false)
                self.aiUsageTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.model.aiUsage.refresh(includeTokens: false) }
                }
                self.aiUsageTimer?.tolerance = 2
            })
        settingsObservers.append(model.settings.$lyricsEnabled.sink { [weak self] enabled in
            guard let self else { return }
            self.model.lyrics.isEnabled = enabled
            self.model.lyrics.update(for: enabled ? self.model.nowPlaying.track : nil)
        })
        model.notifyServer.onNotify = { [weak self] title, message in
            self?.model.hud.show(.notice(symbol: "sparkles", title: title, detail: message), duration: 6)
        }
        // App volume taps run whenever the setting is on; the list of apps refreshes only while the Tools tab shows.
        settingsObservers.append(model.settings.$perAppVolume.combineLatest(model.$isExpanded, model.$tab)
            .sink { [weak self] enabled, expanded, tab in
                self?.model.appVolume.update(enabled: enabled, listing: expanded && tab == .tools)
            })
        settingsObservers.append(model.settings.$cleanLinks.sink { [weak self] in self?.model.clipboard.cleansLinks = $0 })
        settingsObservers.append(model.settings.$screenshotsToShelf.sink { [weak self] in self?.model.screenshots.isEnabled = $0 })
        model.timer.onFinished = { [weak self] message in
            self?.model.hud.show(.notice(symbol: "timer", title: message, detail: nil), duration: 4)
        }
        // The publisher sends the new value before the setting changes, so the value is passed along.
        for feature in features {
            settingsObservers.append(model.settings[keyPath: feature.changes].sink { [weak self] enabled in
                guard let self else { return }
                if enabled && self.panel.isVisible { feature.start() } else { feature.stop(false) }
            })
        }
        updatesObserver = model.settings.$checkForUpdates
            .removeDuplicates()
            .sink { UpdateChecker.shared.startAutomaticChecks(enabled: $0) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        pillWidthObserver = model.settings.$pillWidth.map { _ in () }
            .merge(with: model.settings.$displayName.map { _ in () }, model.settings.$showInClamshell.map { _ in () })
            .dropFirst(3)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.relayout() }
            }
    }

    /// Puts every app back to full volume before quitting.
    func prepareToQuit() {
        model.appVolume.shutdown()
    }

    private func relayout() {
        guard let screen = NotchGeometry.pickScreen(preferredName: model.settings.displayName) else { return }
        model.geometry = NotchGeometry(screen: screen, pillWidth: model.settings.pillWidth)
        panel.setFrame(model.geometry.panelFrame, display: true)
        updateVisibility()
    }

    /// Hides the notch in clamshell mode when the user turned that off.
    private func updateVisibility() {
        let hidden = !model.settings.showInClamshell && NotchGeometry.lidIsClosed
        if hidden {
            model.collapse()
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            // Nothing can be shown while hidden, so stop the watchers that only feed the notch.
            for feature in features { feature.stop(true) }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
            for feature in features where model.settings[keyPath: feature.setting] { feature.start() }
        }
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) {
            monitors.append(local)
        }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let overHeader = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                self.scrolled(event)
                return self.isWheelOverHeader(event)
            }
            return overHeader ? (Self.sideways(event) ?? event) : event
        }) {
            monitors.append(scroll)
        }
    }

    /// A mouse wheel turned over the expanded header scrolls the tab row sideways.
    private func isWheelOverHeader(_ event: NSEvent) -> Bool {
        event.window === panel && model.isExpanded && !event.hasPreciseScrollingDeltas
            && event.scrollingDeltaX == 0 && event.scrollingDeltaY != 0
            && panel.frame.height - event.locationInWindow.y < max(model.geometry.collapsedSize.height, 24) + 6
    }

    nonisolated private static func sideways(_ event: NSEvent) -> NSEvent? {
        guard let copy = event.cgEvent?.copy() else { return nil }
        for (vertical, horizontal) in [(CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventDeltaAxis2),
                                       (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
                                       (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2)] {
            copy.setIntegerValueField(horizontal, value: copy.getIntegerValueField(vertical))
            copy.setIntegerValueField(vertical, value: 0)
        }
        return NSEvent(cgEvent: copy)
    }

    /// Turns two-finger swipes over the notch into open/close and track skips.
    /// Each swipe fires at most once; it ends when the gesture ends or input pauses.
    private func scrolled(_ event: NSEvent) {
        let settings = model.settings
        guard settings.swipeToOpen || settings.swipeForTracks else { return }
        // Only trackpad swipes over the panel; not scrolling in other windows, wheels or momentum.
        guard event.window === panel, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        // Scrolling over the timer's time changes its length instead.
        if TimeScrollTarget.isHovered { return }
        // The expanded header scrolls its tabs sideways, so swipes there are left to it.
        let fromTop = panel.frame.height - event.locationInWindow.y
        if model.isExpanded && fromTop < max(model.geometry.collapsedSize.height, 24) + 6 { return }
        if event.phase == .began || event.phase == .mayBegin {
            swipe = .zero
            swipeFired = false
        }
        // Convert to finger direction regardless of the natural scrolling setting.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        swipe.dx += event.scrollingDeltaX * sign
        swipe.dy += event.scrollingDeltaY * sign

        swipeIdleWork?.cancel()
        let idle = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.swipe = .zero
                self?.swipeFired = false
            }
        }
        swipeIdleWork = idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: idle)

        guard !swipeFired else { return }
        let threshold: CGFloat = 40
        if abs(swipe.dy) > threshold && abs(swipe.dy) > abs(swipe.dx) * 1.5, settings.swipeToOpen {
            swipeFired = true
            if swipe.dy > 0 { model.expand() } else { model.collapse() }
        } else if abs(swipe.dx) > threshold && abs(swipe.dx) > abs(swipe.dy) * 1.5,
                  settings.swipeForTracks, model.isExpanded, model.tab == .home, model.nowPlaying.track != nil {
            swipeFired = true
            model.nowPlaying.send(swipe.dx < 0 ? .next : .previous)
        }
    }

    private func pointerMoved() {
        guard panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        // Every shape fits in the panel, so away from it the pointer is outside without working out the shape's size.
        let nearPanel = panel.frame.insetBy(dx: -8, dy: -8).contains(point)

        if model.isExpanded {
            let inside = nearPanel && model.geometry.shapeRect(size: model.expandedSize).insetBy(dx: -6, dy: -6).contains(point)
            if model.pinned {
                if inside { model.pinned = false }
                panel.ignoresMouseEvents = false
                return
            }
            panel.ignoresMouseEvents = !inside
            if inside {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.model.collapse()
                        self?.collapseWork = nil
                        self?.panel.ignoresMouseEvents = true
                    }
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
        } else {
            let inside = nearPanel && model.geometry.shapeRect(size: model.collapsedSize).contains(point)
            panel.ignoresMouseEvents = !inside
            if !inside {
                openWork?.cancel()
                openWork = nil
            } else if openWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.openWork = nil
                        guard let self, self.model.geometry.shapeRect(size: self.model.collapsedSize)
                            .contains(NSEvent.mouseLocation) else { return }
                        self.model.expand()
                    }
                }
                openWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + model.settings.openDelay, execute: work)
            }
        }
    }
}
