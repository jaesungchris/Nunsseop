import AppKit
import ApplicationServices

/// Where the frontmost app's menu titles sit in the menu bar, so the collapsed notch can keep its left side off them.
/// Read through Accessibility, and only when Nunsseop already has that permission; without it `frames` stays empty.
@MainActor
final class AppMenuWatcher: ObservableObject {
    /// The frontmost app's menu titles in screen coordinates (origin at the bottom left), Apple menu included.
    @Published private(set) var frames: [CGRect] = []

    private var cache: [pid_t: [CGRect]] = [:]
    private var frontmost: pid_t?
    private var reading = false
    private var observer: NSObjectProtocol?
    private let queue = DispatchQueue(label: "nunsseop.appmenus", qos: .utility)

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app?.processIdentifier) }
        }
        activated(NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    private func activated(_ pid: pid_t?) {
        frontmost = pid
        // The last reading for this app answers at once; a fresh one follows, as menus can change while it runs.
        frames = pid.flatMap { cache[$0] } ?? []
        refresh()
    }

    /// Reads the frontmost app's menus again off the main thread; called when it activates and when the notch grows ears.
    func refresh() {
        guard let pid = frontmost, !reading, AXIsProcessTrusted() else { return }
        reading = true
        // Accessibility reports positions from the top left of the main display.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        queue.async { [weak self] in
            let frames = Self.menuFrames(of: pid, flippedAt: top)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reading = false
                    self.cache[pid] = frames
                    if self.frontmost == pid {
                        if self.frames != frames { self.frames = frames }
                    } else {
                        // Another app came forward while this one was read.
                        self.refresh()
                    }
                }
            }
        }
    }

    /// An app that doesn't answer within the timeout counts as having no menus.
    nonisolated private static func menuFrames(of pid: pid_t, flippedAt top: CGFloat) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items.compactMap { item in
            var position = CGPoint.zero, size = CGSize.zero
            guard let positionValue = attribute(kAXPositionAttribute, of: item),
                  AXValueGetValue(positionValue, .cgPoint, &position),
                  let sizeValue = attribute(kAXSizeAttribute, of: item),
                  AXValueGetValue(sizeValue, .cgSize, &size),
                  size.width > 0, size.height > 0 else { return nil }
            return CGRect(x: position.x, y: top - position.y - size.height, width: size.width, height: size.height)
        }
    }

    nonisolated private static func attribute(_ name: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
