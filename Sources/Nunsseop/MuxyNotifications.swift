import AppKit

/// One entry of Muxy's notification list.
struct MuxyNotice: Equatable {
    let id: String
    let title: String
    let body: String
    let isRead: Bool
    /// The agent that sent it ("claude", "codex", "pi"...); nil for a terminal (OSC) notification.
    let provider: String?
    /// Where it came from in Muxy, to go back there.
    var projectID: String? = nil
    var worktreeID: String? = nil
    var tabID: String? = nil

    /// Muxy keeps its last 200 notifications, from every agent and terminal in it, in this file.
    static var feedURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Muxy/notifications.json")
    }

    static let bundleID = "com.muxy.app"

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            || FileManager.default.fileExists(atPath: feedURL.deletingLastPathComponent().path)
    }

    /// nil when the file isn't a list, as while Muxy is still writing it.
    static func parse(_ data: Data) -> [MuxyNotice]? {
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            let provider = ((entry["source"] as? [String: Any])?["aiProvider"] as? [String: Any])?["_0"] as? String
            return MuxyNotice(id: id, title: entry["title"] as? String ?? "Muxy", body: entry["body"] as? String ?? "",
                              isRead: entry["isRead"] as? Bool ?? false, provider: provider,
                              projectID: entry["projectID"] as? String, worktreeID: entry["worktreeID"] as? String,
                              tabID: entry["tabID"] as? String)
        }
    }

    /// The tool whose own Nunsseop hook, when connected, already sends this notification.
    var integration: NotifyIntegration? { NotifyIntegration.forAgent(provider) }

    static var socketURL: URL { feedURL.deletingLastPathComponent().appendingPathComponent("muxy.sock") }

    /// Commands for Muxy's local socket that select the notification's project, worktree and tab,
    /// as Muxy's own notification panel does. A tab is looked up in the active project, so that comes first.
    var focusCommands: [String] {
        guard let projectID else { return [] }
        let safe = { (id: String) in !id.isEmpty && id.allSatisfy { $0.isHexDigit || $0 == "-" } }
        guard safe(projectID) else { return [] }
        var commands = ["switch-project|\(projectID)"]
        if let worktreeID, safe(worktreeID) { commands.append("switch-worktree|\(worktreeID)|\(projectID)") }
        if let tabID, safe(tabID) { commands.append("switch-tab|\(tabID)") }
        return commands
    }

    /// Sends commands to Muxy's socket, which answers one command per connection and then closes it.
    @discardableResult
    static func send(_ commands: [String], toSocket socket: String = socketURL.path) -> [String] {
        commands.compactMap { TerminalFocus.send([$0], toSocket: socket).first }
    }

    /// Goes to the notification's tab and brings Muxy forward.
    func focus() {
        let commands = focusCommands
        DispatchQueue.global(qos: .userInitiated).async {
            Self.send(commands)
            DispatchQueue.main.async { TerminalFocus.activate(bundleID: Self.bundleID) }
        }
    }
}

/// Which of Muxy's notifications are new: the list read first is only remembered, so history isn't replayed.
struct MuxySeen {
    private var ids: Set<String>?

    /// Unread notifications that weren't in the list before.
    mutating func fresh(in notices: [MuxyNotice]) -> [MuxyNotice] {
        let current = Set(notices.map(\.id))
        defer { ids = current }
        guard let ids else { return [] }
        return notices.filter { !ids.contains($0.id) && !$0.isRead }
    }
}

/// Shows the notifications agents running in Muxy send, by watching Muxy's notification file.
@MainActor
final class MuxyWatcher {
    var onNotice: ((MuxyNotice) -> Void)?
    private var timer: Timer?
    private var modified: Date?
    private var seen = MuxySeen()

    func start() {
        guard timer == nil else { return }
        seen = MuxySeen()
        modified = nil
        check()
        // Only the modification date is read until it changes.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = 0.5
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let url = MuxyNotice.feedURL
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard date != modified else { return }
        // A file caught mid-write or replaced is read again next time, rather than taken as an empty list.
        guard let data = try? Data(contentsOf: url), let notices = MuxyNotice.parse(data) else { return }
        modified = date
        let fresh = seen.fresh(in: notices)
        // Muxy shows its own toast while it's in front. Several at once show as the newest, which Muxy lists first.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != MuxyNotice.bundleID,
              let newest = fresh.first(where: { $0.integration?.isInstalled != true }) else { return }
        onNotice?(newest)
    }
}
