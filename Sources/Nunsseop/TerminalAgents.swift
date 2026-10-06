import AppKit
import Network

extension NotifyIntegration {
    /// The tool an agent name from a terminal app (Muxy, herdr) stands for, whose own Nunsseop hook,
    /// when connected, already sends its notifications.
    static func forAgent(_ name: String?) -> NotifyIntegration? {
        switch name?.lowercased() {
        case "claude", "claude code": .claudeCode
        case "codex": .codex
        case "gemini", "gemini cli": .gemini
        case "opencode": .openCode
        default: nil
        }
    }
}

/// Splits a byte stream into newline-delimited JSON objects.
struct JSONLines {
    private var buffer = Data()

    /// A line longer than this is no frame any of these tools sends; it's thrown away.
    static let maxLine = 1 << 20

    mutating func append(_ data: Data) -> [[String: Any]] {
        buffer.append(data)
        var objects: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { objects.append(object) }
        }
        if buffer.count > Self.maxLine { buffer.removeAll() }
        return objects
    }
}

// MARK: - cmux

/// cmux's notifications, read through the `cmux` command inside the app, which finds the socket and its password.
/// The event stream leaves out titles and bodies, so each new notification is looked up in the list.
enum Cmux {
    static let bundleID = "com.cmuxterm.app"

    static var cli: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .appendingPathComponent("Contents/Resources/bin/cmux")
    }

    static var isInstalled: Bool { cli.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false }

    struct Notice: Equatable {
        let title: String
        let body: String
    }

    /// The notification id of a `notification.created` event frame.
    static func createdID(in frame: [String: Any]) -> String? {
        guard frame["type"] as? String == "event", frame["name"] as? String == "notification.created" else { return nil }
        return (frame["payload"] as? [String: Any])?["notification_id"] as? String
    }

    /// The unread notification with `id` in the output of `cmux rpc notification.list`.
    static func notice(_ id: String, inList data: Data) -> Notice? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let rows = object["notifications"] as? [[String: Any]]
            ?? (object["result"] as? [String: Any])?["notifications"] as? [[String: Any]] ?? []
        guard let row = rows.first(where: { ($0["id"] as? String)?.caseInsensitiveCompare(id) == .orderedSame }),
              row["is_read"] as? Bool != true else { return nil }
        let title = row["title"] as? String ?? "cmux"
        let subtitle = row["subtitle"] as? String ?? ""
        let body = row["body"] as? String ?? ""
        return Notice(title: title, body: [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

@MainActor
final class CmuxWatcher {
    var onNotice: ((Cmux.Notice) -> Void)?
    private let cli: URL?
    private var stream: Process?
    private var lines = JSONLines()
    private var running = false
    private var quitObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "nunsseop.cmux")

    init(cli: URL? = Cmux.cli) { self.cli = cli }

    func start() {
        guard !running else { return }
        running = true
        // The event stream is a child process, which would outlive Nunsseop otherwise.
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        launch()
    }

    func stop() {
        running = false
        if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
        quitObserver = nil
        if stream?.isRunning == true { stream?.terminate() }
        stream = nil
        lines = JSONLines()
    }

    /// Tries again after a pause, when the command couldn't start or stopped on its own.
    private func relaunch(after process: Process?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.stream === process else { return }
                self.stream = nil
                self.lines = JSONLines()
                self.launch()
            }
        }
    }

    private func launch() {
        guard running, stream == nil, let cli else { return }
        let process = Process()
        process.executableURL = cli
        // --reconnect keeps waiting while cmux isn't running and resumes after it restarts.
        process.arguments = ["events", "--name", "notification.created", "--reconnect", "--no-ack", "--no-heartbeat"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Empty means the end of the output; without this the handler keeps firing.
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(data) } }
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.relaunch(after: process) } }
        }
        stream = process
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            relaunch(after: process)
        }
    }

    private func received(_ data: Data) {
        for frame in lines.append(data) {
            if let id = Cmux.createdID(in: frame) { lookUp(id) }
        }
    }

    private func lookUp(_ id: String) {
        guard let cli else { return }
        queue.async { [weak self] in
            let process = Process()
            process.executableURL = cli
            process.arguments = ["rpc", "notification.list"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            // A cmux that doesn't answer mustn't hold up the lookups after it.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if process.isRunning { process.terminate() } }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let notice = Cmux.notice(id, inList: data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // cmux shows the notification itself while it's in front.
                    guard let self, self.running,
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Cmux.bundleID,
                          NotifyIntegration.forAgent(notice.title)?.isInstalled != true else { return }
                    self.onNotice?(notice)
                }
            }
        }
    }
}

// MARK: - herdr

/// herdr's socket API: newline-delimited JSON over `~/.config/herdr/herdr.sock`. Agent states are
/// subscribed per pane, so the subscription is renewed whenever panes come and go.
enum Herdr {
    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/herdr/herdr.sock")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: socketURL.deletingLastPathComponent().path)
    }

    struct Pane: Equatable {
        let id: String
        let status: String
        var agent: String? = nil
        var title: String? = nil
    }

    /// An agent in a pane that just finished or is waiting for the user.
    struct Notice: Equatable {
        let agent: String
        let status: String
        let title: String?
    }

    static func request(_ id: String, _ method: String, _ params: [String: Any] = [:]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])) ?? Data()
        data.append(0x0A)
        return data
    }

    /// Pane lifecycle plus the agent state of every listed pane.
    static func subscription(_ id: String, panes: [Pane]) -> Data {
        let lifecycle: [[String: Any]] = [["type": "pane.created"], ["type": "pane.closed"]]
        let states: [[String: Any]] = panes.map { ["type": "pane.agent_status_changed", "pane_id": $0.id] }
        return request(id, "events.subscribe", ["subscriptions": lifecycle + states])
    }

    /// The panes in a `pane.list` response.
    static func panes(in response: [String: Any]) -> [Pane]? {
        guard let rows = (response["result"] as? [String: Any])?["panes"] as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            (row["pane_id"] as? String).map {
                Pane(id: $0, status: row["agent_status"] as? String ?? "unknown",
                     agent: row["display_agent"] as? String ?? row["agent"] as? String, title: row["title"] as? String)
            }
        }
    }

    enum Event: Equatable {
        case panesChanged
        case status(pane: String, Notice)
    }

    static func event(in frame: [String: Any]) -> Event? {
        let data = frame["data"] as? [String: Any] ?? [:]
        switch frame["event"] as? String {
        case "pane.created", "pane.closed":
            return .panesChanged
        case "pane.agent_status_changed":
            guard let pane = data["pane_id"] as? String, let status = data["agent_status"] as? String else { return nil }
            let agent = data["display_agent"] as? String ?? data["agent"] as? String ?? "herdr"
            return .status(pane: pane, Notice(agent: agent, status: status, title: data["title"] as? String))
        default:
            return nil
        }
    }

    /// The last known state of each pane; only a change into `done` (finished, not yet seen) or `blocked`
    /// (waiting for the user) is announced.
    struct States {
        private(set) var byPane: [String: String] = [:]

        /// Takes a fresh pane list as the known states. Panes already known that moved into `done` or `blocked`
        /// while no subscription was listening (between two subscriptions) are returned to announce.
        mutating func reconcile(_ panes: [Pane]) -> [Pane] {
            let known = byPane
            byPane = Dictionary(panes.map { ($0.id, $0.status) }, uniquingKeysWith: { $1 })
            return panes.filter { pane in
                guard let before = known[pane.id] else { return false }
                return (pane.status == "done" || pane.status == "blocked") && before != pane.status
            }
        }

        mutating func update(pane: String, to status: String) -> Bool {
            defer { byPane[pane] = status }
            return (status == "done" || status == "blocked") && byPane[pane] != status
        }
    }
}

@MainActor
final class HerdrWatcher {
    var onNotice: ((Herdr.Notice) -> Void)?
    private let socketURL: URL
    private var connection: NWConnection?
    private var lines = JSONLines()
    private var states = Herdr.States()
    private var retry: Timer?
    private var running = false
    private let queue = DispatchQueue(label: "nunsseop.herdr")

    init(socketURL: URL = Herdr.socketURL) { self.socketURL = socketURL }

    func start() {
        guard !running else { return }
        running = true
        connect()
        // herdr's server may start later or restart; a closed connection is opened again from here.
        retry = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.connection == nil { self?.connect() } }
        }
        retry?.tolerance = 2
    }

    func stop() {
        running = false
        retry?.invalidate()
        retry = nil
        drop()
    }

    private func drop() {
        connection?.cancel()
        connection = nil
        lines = JSONLines()
    }

    /// Lists the panes on one connection, then subscribes on a new one: a subscription takes its connection over.
    private func connect() {
        guard running, connection == nil, FileManager.default.fileExists(atPath: socketURL.path) else { return }
        open { [weak self] frame in
            guard let self, frame["id"] as? String == "list" else { return }
            self.drop()
            guard let panes = Herdr.panes(in: frame) else { return }
            for pane in self.states.reconcile(panes) {
                self.announce(Herdr.Notice(agent: pane.agent ?? "herdr", status: pane.status, title: pane.title))
            }
            self.open(sending: Herdr.subscription("sub", panes: panes)) { [weak self] frame in self?.handle(frame) }
        }
        connection?.send(content: Herdr.request("list", "pane.list"), completion: .contentProcessed { _ in })
    }

    private func open(sending first: Data? = nil, _ onFrame: @escaping (([String: Any]) -> Void)) {
        let connection = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            // A socket left behind by a server that quit can leave the connection waiting for good.
            case .failed, .cancelled, .waiting:
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if self?.connection === connection { self?.drop() } }
                }
            default: break
            }
        }
        self.connection = connection
        connection.start(queue: queue)
        if let first { connection.send(content: first, completion: .contentProcessed { _ in }) }
        receive(on: connection, onFrame)
    }

    private func receive(on connection: NWConnection, _ onFrame: @escaping (([String: Any]) -> Void)) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.connection === connection else { return }
                    // Frames after one that moved on to a new connection belong to the old one.
                    for frame in self.lines.append(data ?? Data()) where self.connection === connection { onFrame(frame) }
                    // A frame may have moved on to a new connection; only this one is dropped or read further.
                    guard self.connection === connection else { return }
                    if isComplete || error != nil {
                        self.drop()
                    } else {
                        self.receive(on: connection, onFrame)
                    }
                }
            }
        }
    }

    private func handle(_ frame: [String: Any]) {
        switch Herdr.event(in: frame) {
        case .panesChanged:
            // Subscribe again with the new pane list.
            drop()
            connect()
        case .status(let pane, let notice):
            if states.update(pane: pane, to: notice.status) { announce(notice) }
        case nil:
            // A rejected subscription (a pane closed meanwhile): the timer subscribes again with a fresh list.
            if frame["error"] != nil { drop() }
        }
    }

    private func announce(_ notice: Herdr.Notice) {
        guard NotifyIntegration.forAgent(notice.agent)?.isInstalled != true else { return }
        onNotice?(notice)
    }
}
