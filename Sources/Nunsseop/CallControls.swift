import AppKit
import ApplicationServices

/// Microphone and camera toggles for a call, driven without bringing the call app to the front:
/// Zoom and FaceTime through their menu-bar items over Accessibility, Google Meet through
/// JavaScript in its browser tab. Every lookup fails closed: what can't be found isn't shown.
enum CallControls {
    enum Toggle: Equatable {
        /// Microphone live or camera sending.
        case on
        /// Muted, or camera off.
        case off
        /// The control exists but its state can't be read.
        case unknown
    }

    /// nil where the call offers no such control.
    struct State: Equatable {
        var mic: Toggle?
        var camera: Toggle?
    }

    enum Control { case mic, camera }

    /// A menu item's key equivalent. `modifiers` is AXMenuItemCmdModifiers: bit 0 Shift, bit 1 Option,
    /// bit 2 Control, bit 3 set when Command is not part of it.
    struct Shortcut: Equatable {
        let key: String
        let modifiers: Int

        func matches(key: String?, modifiers: Int?) -> Bool {
            key?.uppercased() == self.key && (modifiers ?? 0) == self.modifiers
        }
    }

    /// Titles a toggle's menu item carries in each state, in every language the app ships.
    struct Titles {
        var on: Set<String> = []
        var off: Set<String> = []
    }

    /// A menu item's state from its title, in whatever language the app runs, or from its check mark
    /// for apps that mark the item while muted. Titles found in both sets say nothing.
    static func toggle(title: String?, mark: String?, titles: Titles, markMeansOff: Bool) -> Toggle {
        if markMeansOff, let mark, !mark.isEmpty { return .off }
        guard let title = title.map(normalized) else { return .unknown }
        let on = titles.on.contains(title), off = titles.off.contains(title)
        if on != off { return on ? .on : .off }
        return .unknown
    }

    static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MARK: - Apps with menu items

    struct MenuApp: Equatable {
        let bundleID: String
        let mic: Shortcut
        let camera: Shortcut?
        let markMeansOff: Bool

        /// Zoom's in-meeting menu: Mute Audio ⌘⇧A and Stop Video ⌘⇧V; the titles flip with the state.
        static let zoom = MenuApp(bundleID: "us.zoom.xos", mic: Shortcut(key: "A", modifiers: 1),
                                  camera: Shortcut(key: "V", modifiers: 1), markMeansOff: false)
        /// FaceTime's Video › Mute ⌘⇧M. It has no menu item for the camera.
        static let faceTime = MenuApp(bundleID: "com.apple.FaceTime", mic: Shortcut(key: "M", modifiers: 1),
                                      camera: nil, markMeansOff: true)

        static func == (a: MenuApp, b: MenuApp) -> Bool { a.bundleID == b.bundleID }

        /// Read from the app's own localizations, once.
        func titles(for control: Control) -> Titles {
            switch (bundleID, control) {
            case (Self.zoom.bundleID, .mic): return Self.zoomTitles.mic
            case (Self.zoom.bundleID, .camera): return Self.zoomTitles.camera
            case (Self.faceTime.bundleID, .mic): return Self.faceTimeMicTitles
            default: return Titles()
            }
        }

        private static let zoomTitles: (mic: Titles, camera: Titles) = {
            var mic = Titles(), camera = Titles()
            for table in stringsTables(of: zoom.bundleID, file: "Localizable.strings") {
                func add(_ key: String, to set: inout Set<String>) {
                    set.insert(normalized(key))
                    if let value = table[key] as? String { set.insert(normalized(value)) }
                }
                add("Mute Audio", to: &mic.on)
                add("Unmute Audio", to: &mic.off)
                add("Stop Video", to: &camera.on)
                add("Start Video", to: &camera.off)
            }
            return (mic, camera)
        }()

        /// FaceTime keeps the title and checks the item while muted; an unchecked "Mute" means live.
        private static let faceTimeMicTitles: Titles = {
            guard let url = InstalledApps.url(for: faceTime.bundleID)?.appendingPathComponent("Contents/Resources/Localizable.loctable"),
                  let data = try? Data(contentsOf: url),
                  let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return Titles() }
            var titles = Titles(on: [normalized("Mute")])
            for case let strings as [String: Any] in table.values {
                if let mute = strings["Mute"] as? String { titles.on.insert(normalized(mute)) }
            }
            return titles
        }()

        private static func stringsTables(of bundleID: String, file: String) -> [NSDictionary] {
            guard let resources = InstalledApps.url(for: bundleID)?.appendingPathComponent("Contents/Resources"),
                  let folders = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
            else { return [] }
            return folders.filter { $0.pathExtension == "lproj" }
                .compactMap { NSDictionary(contentsOf: $0.appendingPathComponent(file)) }
        }
    }

    private struct MenuItem {
        let element: AXUIElement
        let title: String?
        let mark: String?
    }

    /// Menu items found by a walk of the menu bar, reused by later reads until they stop answering.
    /// Touched only on the serial queue that reads and presses.
    final class ItemCache: @unchecked Sendable {
        fileprivate var pid: pid_t = 0
        fileprivate var elements: [Shortcut: AXUIElement] = [:]
        fileprivate var walkedAt = Date.distantPast
    }

    /// Each element gets its own timeout (elements handed back by Accessibility don't inherit one), so an
    /// app that hangs costs half a second per question rather than the default six.
    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// The enabled menu-bar items of the running app with these shortcuts, found without opening any menu.
    /// Items found before are only read again; the menu bar is walked when one stops answering.
    private static func menuItems(of app: MenuApp, for shortcuts: [Shortcut], cache: ItemCache) -> [Shortcut: MenuItem]? {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?.processIdentifier
        else { return nil }
        if cache.pid == pid, let items = cachedItems(for: shortcuts, in: cache) { return items }
        let found = walk(pid, for: shortcuts)
        cache.pid = pid
        cache.elements = found?.mapValues(\.element) ?? [:]
        cache.walkedAt = Date()
        return found
    }

    /// The cached items, read again; nil when one no longer answers as the same enabled item. A shortcut the
    /// last walk didn't find counts as still missing for a while, so an app without it isn't walked every poll.
    private static func cachedItems(for shortcuts: [Shortcut], in cache: ItemCache) -> [Shortcut: MenuItem]? {
        guard !cache.elements.isEmpty else { return nil }
        var items: [Shortcut: MenuItem] = [:]
        for shortcut in shortcuts {
            guard let element = cache.elements[shortcut] else {
                if Date().timeIntervalSince(cache.walkedAt) < 10 { continue }
                return nil
            }
            guard shortcut.matches(key: attribute(element, "AXMenuItemCmdChar") as? String,
                                   modifiers: attribute(element, "AXMenuItemCmdModifiers") as? Int),
                  attribute(element, kAXEnabledAttribute) as? Bool == true else { return nil }
            items[shortcut] = MenuItem(element: element, title: attribute(element, kAXTitleAttribute) as? String,
                                       mark: attribute(element, "AXMenuItemMarkChar") as? String)
        }
        return items
    }

    /// Walks the menu bar for the items; gives up after a couple of seconds so a slow app can't hold the queue.
    private static func walk(_ pid: pid_t, for shortcuts: [Shortcut]) -> [Shortcut: MenuItem]? {
        let root = AXUIElementCreateApplication(pid)
        guard let bar = attribute(root, kAXMenuBarAttribute) else { return nil }
        let deadline = Date().addingTimeInterval(2)
        var found: [Shortcut: MenuItem] = [:]
        // Menu bar › menu title › menu › item, and one level of submenus below that.
        func scan(_ menu: AXUIElement, depth: Int) {
            for item in children(menu) {
                guard found.count < shortcuts.count, Date() < deadline else { return }
                let key = attribute(item, "AXMenuItemCmdChar") as? String
                let modifiers = attribute(item, "AXMenuItemCmdModifiers") as? Int
                if let shortcut = shortcuts.first(where: { $0.matches(key: key, modifiers: modifiers) }), found[shortcut] == nil,
                   attribute(item, kAXEnabledAttribute) as? Bool == true {
                    found[shortcut] = MenuItem(element: item, title: attribute(item, kAXTitleAttribute) as? String,
                                               mark: attribute(item, "AXMenuItemMarkChar") as? String)
                }
                if depth > 0 { children(item).forEach { scan($0, depth: depth - 1) } }
            }
        }
        for title in children(bar as! AXUIElement) {
            children(title).forEach { scan($0, depth: 1) }
        }
        return found
    }

    // MARK: - Google Meet

    /// Meet's microphone and camera buttons carry data-is-muted. Both must be found, in that order, or nothing is.
    private static func meetJS(clicking index: Int?) -> String {
        let click = index.map { "b[\($0)].click();" } ?? ""
        return """
        (() => { const b = [...document.querySelectorAll('[data-is-muted]')].filter(e => \
        (e.tagName === 'BUTTON' || e.getAttribute('role') === 'button') && e.getClientRects().length > 0); \
        if (b.length !== 2) return ''; \(click) \
        return JSON.stringify(b.map(e => e.getAttribute('data-is-muted'))); })()
        """
    }

    /// The tab's answer: a JSON array of the microphone's and camera's data-is-muted, "true" or "false".
    static func meetState(_ result: String?) -> State? {
        guard let data = result?.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String], values.count == 2 else { return nil }
        func toggle(_ value: String) -> Toggle? {
            switch value {
            case "true": return .off
            case "false": return .on
            default: return nil
            }
        }
        guard let mic = toggle(values[0]), let camera = toggle(values[1]) else { return nil }
        return State(mic: mic, camera: camera)
    }

    // MARK: - Targets

    enum Target: Equatable {
        case menu(MenuApp)
        case meet(browserBundleID: String)

        init?(_ call: CallMonitor.Call) {
            switch call.bundleID {
            case MenuApp.zoom.bundleID: self = .menu(.zoom)
            case MenuApp.faceTime.bundleID: self = .menu(.faceTime)
            default:
                // Meet is driven through `execute javascript`, which only Chromium browsers have.
                guard call.appName == "Google Meet", let browser = CallMonitor.browser(for: call.bundleID),
                      browser.dialect == .chromium else { return nil }
                self = .meet(browserBundleID: call.bundleID)
            }
        }

        /// Blocks on Accessibility or AppleScript; call off the main thread. nil when nothing can be controlled.
        func read(cache: ItemCache) -> State? {
            switch self {
            case .menu(let app):
                let shortcuts = [app.mic] + (app.camera.map { [$0] } ?? [])
                guard let items = menuItems(of: app, for: shortcuts, cache: cache) else { return nil }
                func toggle(_ shortcut: Shortcut?, _ control: Control) -> Toggle? {
                    guard let shortcut, let item = items[shortcut] else { return nil }
                    return CallControls.toggle(title: item.title, mark: item.mark, titles: app.titles(for: control),
                                               markMeansOff: app.markMeansOff)
                }
                let state = State(mic: toggle(app.mic, .mic), camera: toggle(app.camera, .camera))
                return state.mic == nil && state.camera == nil ? nil : state
            case .meet(let id):
                return BrowserMedia.all.first { $0.bundleID == id }.flatMap { meetState($0.runInTabs(onHost: "meet.google.com", meetJS(clicking: nil))) }
            }
        }

        /// Blocks like `read`.
        func press(_ control: Control, cache: ItemCache) {
            switch self {
            case .menu(let app):
                guard let shortcut = control == .mic ? app.mic : app.camera,
                      let item = menuItems(of: app, for: [shortcut], cache: cache)?[shortcut] else { return }
                AXUIElementPerformAction(item.element, kAXPressAction as CFString)
            case .meet(let id):
                _ = BrowserMedia.all.first { $0.bundleID == id }?.runInTabs(onHost: "meet.google.com", meetJS(clicking: control == .mic ? 0 : 1))
            }
        }
    }
}

extension CallControls.Shortcut: Hashable {}

/// Follows the current call and polls its controls every 2 s while it lasts.
@MainActor
final class CallControlsModel: ObservableObject {
    @Published private(set) var state: CallControls.State?

    private var target: CallControls.Target?
    /// The current target's menu items; a new target starts a new one.
    private var cache = CallControls.ItemCache()
    private var timer: Timer?
    private var polling = false
    private let queue = DispatchQueue(label: "nunsseop.call-controls")

    func follow(_ call: CallMonitor.Call?) {
        let target = call.flatMap(CallControls.Target.init)
        guard target != self.target else { return }
        self.target = target
        cache = CallControls.ItemCache()
        timer?.invalidate()
        timer = nil
        state = nil
        guard target != nil else { return }
        #if DEBUG
        if CommandLine.arguments.contains("--demo-call") {
            // A muted microphone and a live camera, where the app has one; the buttons flip them locally.
            if case .menu(let app) = target {
                state = CallControls.State(mic: .off, camera: app.camera == nil ? nil : .on)
            } else {
                state = CallControls.State(mic: .off, camera: .on)
            }
            return
        }
        #endif
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.3
    }

    func toggle(_ control: CallControls.Control) {
        guard let target else { return }
        #if DEBUG
        if CommandLine.arguments.contains("--demo-call"), var state {
            func flip(_ toggle: CallControls.Toggle?) -> CallControls.Toggle? { toggle.map { $0 == .off ? .on : .off } }
            if control == .mic { state.mic = flip(state.mic) } else { state.camera = flip(state.camera) }
            self.state = state
            return
        }
        #endif
        let cache = cache
        queue.async { [weak self] in
            target.press(control, cache: cache)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.poll() }
        }
    }

    private func poll() {
        guard !polling, let target else { return }
        polling = true
        let cache = cache
        queue.async { [weak self] in
            let state = target.read(cache: cache)
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                // The call may have ended or changed while the app was asked.
                guard self.target == target, self.state != state else { return }
                self.state = state
            }
        }
    }
}
