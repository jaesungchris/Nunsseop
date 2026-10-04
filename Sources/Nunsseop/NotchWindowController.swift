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
    private var clipboardObserver: AnyCancellable?
    private var settingsObservers: [AnyCancellable] = []

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
        #endif
    }

    #if DEBUG
    private var snapshotter: DebugSnapshotter?
    #endif

    func show() {
        panel.setFrame(model.geometry.panelFrame, display: true)
        panel.orderFrontRegardless()
        installMonitors()
        model.nowPlaying.start()
        model.hud.start()
        model.clipboard.start()
        model.tools.start()
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
        model.capsLock.start()
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
        settingsObservers.append(model.settings.$weatherCity
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.model.weather.setCity($0) })
        settingsObservers.append(model.settings.$lyricsEnabled.sink { [weak self] enabled in
            guard let self else { return }
            self.model.lyrics.isEnabled = enabled
            self.model.lyrics.update(for: enabled ? self.model.nowPlaying.track : nil)
        })
        model.notifyServer.onNotify = { [weak self] title, message in
            self?.model.hud.show(.notice(symbol: "sparkles", title: title, detail: message), duration: 6)
        }
        settingsObservers.append(model.settings.$screenshotsToShelf.sink { [weak self] in self?.model.screenshots.isEnabled = $0 })
        settingsObservers.append(model.settings.$localNotifications.sink { [weak self] enabled in
            if enabled { self?.model.notifyServer.start() } else { self?.model.notifyServer.stop() }
        })
        model.timer.onFinished = { [weak self] message in
            self?.model.hud.show(.notice(symbol: "timer", title: message, detail: nil), duration: 4)
        }
        clipboardObserver = model.settings.$clipboardTab
            .sink { [weak self] enabled in
                self?.model.clipboard.isEnabled = enabled
                if !enabled { self?.model.clipboard.clear() }
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
            .merge(with: model.settings.$displayName.map { _ in () })
            .dropFirst(2)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.relayout() }
            }
    }

    private func relayout() {
        guard let screen = NotchGeometry.pickScreen(preferredName: model.settings.displayName) else { return }
        model.geometry = NotchGeometry(screen: screen, pillWidth: model.settings.pillWidth)
        panel.setFrame(model.geometry.panelFrame, display: true)
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
            MainActor.assumeIsolated { self?.scrolled(event) }
            return event
        }) {
            monitors.append(scroll)
        }
    }

    /// Turns two-finger swipes over the notch into open/close and track skips.
    /// Each swipe fires at most once; it ends when the gesture ends or input pauses.
    private func scrolled(_ event: NSEvent) {
        let settings = model.settings
        guard settings.swipeToOpen || settings.swipeForTracks else { return }
        // Only trackpad swipes over the panel; not scrolling in other windows, wheels or momentum.
        guard event.window === panel, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
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
        let point = NSEvent.mouseLocation
        let collapsedRect = model.geometry.shapeRect(size: model.collapsedSize)
        let expandedRect = model.geometry.shapeRect(size: model.expandedSize)

        if model.isExpanded {
            let inside = expandedRect.insetBy(dx: -6, dy: -6).contains(point)
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
            let inside = collapsedRect.contains(point)
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
