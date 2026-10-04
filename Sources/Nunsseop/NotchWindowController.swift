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
        if event.phase == .began || event.phase == .mayBegin {
            swipe = .zero
            swipeFired = false
        }
        // Convert to finger direction regardless of the natural scrolling setting.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        swipe.dx += event.scrollingDeltaX * sign * scale
        swipe.dy += event.scrollingDeltaY * sign * scale

        swipeIdleWork?.cancel()
        let idle = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.swipe = .zero
                self?.swipeFired = false
            }
        }
        swipeIdleWork = idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: idle)
        if event.phase == .ended || event.phase == .cancelled { idle.perform() }

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
