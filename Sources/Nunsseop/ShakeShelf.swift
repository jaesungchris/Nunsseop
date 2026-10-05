import AppKit
import SwiftUI

/// Spots a quick left-right shake in a stream of pointer positions: enough direction reversals,
/// each after a stroke of at least `minStroke` points, inside `window` seconds.
struct ShakeDetector {
    var minStroke: CGFloat = 40
    var reversalsNeeded = 3
    var window: TimeInterval = 0.6

    private var anchor: CGFloat?
    /// The furthest point of the current stroke; a reversal is measured back from it.
    private var extreme: CGFloat = 0
    /// +1 moving right, -1 moving left, 0 before the first full stroke.
    private var direction: CGFloat = 0
    private var reversals: [TimeInterval] = []

    /// Feeds one horizontal position; returns true once when a shake completes.
    mutating func add(x: CGFloat, at time: TimeInterval) -> Bool {
        guard let anchor else {
            self.anchor = x
            extreme = x
            return false
        }
        if direction == 0 {
            if abs(x - anchor) >= minStroke {
                direction = x > anchor ? 1 : -1
                extreme = x
            }
            return false
        }
        if (x - extreme) * direction > 0 {
            extreme = x
        } else if (extreme - x) * direction >= minStroke {
            direction = -direction
            extreme = x
            reversals.append(time)
        }
        reversals.removeAll { time - $0 > window }
        if reversals.count >= reversalsNeeded {
            reset()
            return true
        }
        return false
    }

    mutating func reset() {
        anchor = nil
        direction = 0
        reversals.removeAll()
    }
}

/// Shaking the pointer while dragging files shows a small drop target beside it that adds them to the shelf.
@MainActor
final class ShakeShelf {
    static let tileSize = CGSize(width: 120, height: 90)

    private let shelf: ShelfStore
    private let hud: HUDCenter
    private let state = ShakeTileState()
    private lazy var panel = makePanel()
    private var monitor: Any?
    private var detector = ShakeDetector()
    /// The drag pasteboard's count when no drag was running; a higher count means this drag carries data.
    private var idleDragCount = 0
    private var hideWork: DispatchWorkItem?

    init(shelf: ShelfStore, hud: HUDCenter) {
        self.shelf = shelf
        self.hud = hud
    }

    func start() {
        guard monitor == nil else { return }
        idleDragCount = NSPasteboard(name: .drag).changeCount
        // Global mouse monitors need no Accessibility permission (only key monitors do).
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            let time = event.timestamp
            MainActor.assumeIsolated { self?.handle(type, at: time) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        detector.reset()
        hide(after: 0)
    }

    private func handle(_ type: NSEvent.EventType, at time: TimeInterval) {
        let point = NSEvent.mouseLocation
        if type == .leftMouseUp {
            detector.reset()
            idleDragCount = NSPasteboard(name: .drag).changeCount
            // A drop on the tile hides it right away; anywhere else it fades shortly after.
            if panel.isVisible { hide(after: 0.5) }
            return
        }
        if panel.isVisible {
            let away = panel.frame.insetBy(dx: -160, dy: -160).contains(point) == false
            if away { hide(after: 0.8) } else if !state.targeted { cancelHide() }
            return
        }
        guard detector.add(x: point.x, at: time), isDraggingFiles else { return }
        show(near: point)
    }

    /// Text selections and window moves don't write the drag pasteboard; file drags put file URLs on it.
    private var isDraggingFiles: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.changeCount != idleDragCount && pasteboard.types?.contains(.fileURL) == true
    }

    func show(near point: CGPoint) {
        cancelHide()
        state.targeted = false
        let size = Self.tileSize
        var origin = CGPoint(x: point.x + 24, y: point.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            // Flip to the left of the pointer rather than cover it near the right edge.
            if origin.x + size.width > visible.maxX { origin.x = point.x - 24 - size.width }
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
    }

    private func hide(after delay: TimeInterval) {
        guard panel.isVisible, hideWork == nil || delay == 0 else { return }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hideWork = nil
                self.panel.ignoresMouseEvents = true
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; self.panel.animator().alphaValue = 0 },
                                                     completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        // A new shake may have shown the tile again while it faded.
                        if self?.panel.ignoresMouseEvents == true { self?.panel.orderOut(nil) }
                    }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func dropped(_ urls: [URL]) {
        state.targeted = false
        hide(after: 0)
        guard !urls.isEmpty else { return }
        shelf.add(urls)
        let detail = urls.count == 1 ? urls[0].lastPathComponent : String(localized: "\(urls.count) files")
        hud.show(.notice(symbol: "tray.and.arrow.down.fill", title: String(localized: "Added to the shelf"), detail: detail),
                 duration: 3)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.tileSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        let target = ShakeDropView(frame: CGRect(origin: .zero, size: Self.tileSize))
        target.onTargeted = { [weak self] in
            self?.state.targeted = $0
            if $0 { self?.cancelHide() }
        }
        target.onDrop = { [weak self] in self?.dropped($0) }
        let hosting = NSHostingView(rootView: ShakeTile(state: state).environment(\.liquidGlass, AppSettings.shared.liquidGlass))
        hosting.frame = target.bounds
        hosting.autoresizingMask = [.width, .height]
        target.addSubview(hosting)
        panel.contentView = target
        return panel
    }

    #if DEBUG
    /// Shows the tile beside the pointer, plain then highlighted, and hands each to `capture`.
    func demo(capture: @escaping (String, NSView) -> Void) {
        show(near: NSEvent.mouseLocation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            if let view = panel.contentView { capture("shake-shelf", view) }
            state.targeted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                if let view = panel.contentView { capture("shake-shelf-targeted", view) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                    state.targeted = false
                    hide(after: 0)
                }
            }
        }
    }
    #endif
}

@MainActor
private final class ShakeTileState: ObservableObject {
    @Published var targeted = false
}

/// Takes file drops for the tile; the SwiftUI view inside only draws.
private final class ShakeDropView: NSView {
    var onTargeted: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] }
        onTargeted?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onTargeted?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        onDrop?(urls)
        return !urls.isEmpty
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}

private struct ShakeTile: View {
    @ObservedObject var state: ShakeTileState
    @Environment(\.liquidGlass) private var glass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 7) {
            Image(systemName: state.targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 24, weight: .medium))
            Text("Drop to Shelf")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white.opacity(state.targeted ? 1 : 0.8))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { background(shape) }
        .overlay(shape.strokeBorder(state.targeted ? Color.accentColor : .white.opacity(0.14), lineWidth: state.targeted ? 2 : 1))
        .scaleEffect(state.targeted ? 1 : 0.96)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: state.targeted)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func background(_ shape: RoundedRectangle) -> some View {
        let highlight = Color.accentColor.opacity(state.targeted ? 0.35 : 0)
        if glass, #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.55)), in: shape)
                .overlay(shape.fill(highlight))
        } else {
            shape.fill(Color.black.opacity(0.85)).overlay(shape.fill(highlight))
        }
    }
}
