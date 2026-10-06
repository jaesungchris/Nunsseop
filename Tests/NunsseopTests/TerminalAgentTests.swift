import Foundation
import Testing
@testable import Nunsseop

struct TerminalAgentParseTests {
    @Test func jsonLinesSplitAcrossChunks() {
        var lines = JSONLines()
        #expect(lines.append(Data("{\"a\":1}\n{\"b\"".utf8)).count == 1)
        let rest = lines.append(Data(":2}\nnot json\n".utf8))
        #expect(rest.count == 1)
        #expect(rest.first?["b"] as? Int == 2)
    }

    @Test func agentNamesMapToConnectedTools() {
        #expect(NotifyIntegration.forAgent("claude") == .claudeCode)
        #expect(NotifyIntegration.forAgent("Claude Code") == .claudeCode)
        #expect(NotifyIntegration.forAgent("codex") == .codex)
        #expect(NotifyIntegration.forAgent("pi") == nil)
        #expect(NotifyIntegration.forAgent(nil) == nil)
    }

    @Test func cmuxCreatedEventAndListLookup() throws {
        let frame: [String: Any] = ["type": "event", "name": "notification.created", "category": "notification",
                                    "payload": ["notification_id": "7ED5F805-CC6F-4B06-9701-AC798F63E209", "title": NSNull()]]
        #expect(Cmux.createdID(in: frame) == "7ED5F805-CC6F-4B06-9701-AC798F63E209")
        #expect(Cmux.createdID(in: ["type": "heartbeat"]) == nil)
        #expect(Cmux.createdID(in: ["type": "event", "name": "notification.read", "payload": ["notification_id": "x"]]) == nil)

        let list = Data("""
        {"notifications":[
          {"id":"7ed5f805-cc6f-4b06-9701-ac798f63e209","title":"Codex","subtitle":"Waiting","body":"Agent needs input","is_read":false},
          {"id":"READ","title":"Old","subtitle":"","body":"","is_read":true}]}
        """.utf8)
        #expect(Cmux.notice("7ED5F805-CC6F-4B06-9701-AC798F63E209", inList: list)
                == Cmux.Notice(title: "Codex", body: "Waiting · Agent needs input", id: "7ed5f805-cc6f-4b06-9701-ac798f63e209"))
        #expect(Cmux.notice("READ", inList: list) == nil)
        #expect(Cmux.notice("missing", inList: list) == nil)
        let wrapped = Data(#"{"result":{"notifications":[{"id":"A","title":"T","subtitle":"","body":"B"}]}}"#.utf8)
        #expect(Cmux.notice("A", inList: wrapped) == Cmux.Notice(title: "T", body: "B", id: "A"))
    }

    @Test func herdrRequestsAndEvents() throws {
        let line = Herdr.subscription("sub", panes: [Herdr.Pane(id: "w1:p1", status: "idle")])
        #expect(line.last == 0x0A)
        let request = try #require(try JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any])
        #expect(request["method"] as? String == "events.subscribe")
        let subscriptions = (request["params"] as? [String: Any])?["subscriptions"] as? [[String: Any]] ?? []
        #expect(subscriptions.map { $0["type"] as? String } == ["pane.created", "pane.closed", "pane.agent_status_changed"])
        #expect(subscriptions.last?["pane_id"] as? String == "w1:p1")

        let list: [String: Any] = ["id": "list", "result": ["type": "pane_list", "panes": [
            ["pane_id": "w1:p1", "agent_status": "working"], ["pane_id": "w1:p2", "agent_status": "done"]]]]
        #expect(Herdr.panes(in: list) == [Herdr.Pane(id: "w1:p1", status: "working"), Herdr.Pane(id: "w1:p2", status: "done")])
        #expect(Herdr.panes(in: ["id": "list", "error": ["code": "x"]]) == nil)

        #expect(Herdr.event(in: ["event": "pane.closed", "data": ["pane_id": "w1:p2"]]) == .panesChanged)
        let status: [String: Any] = ["event": "pane.agent_status_changed",
                                     "data": ["pane_id": "w1:p1", "workspace_id": "w1", "agent_status": "blocked",
                                              "agent": "claude", "display_agent": "Claude", "title": "fix login"]]
        #expect(Herdr.event(in: status) == .status(pane: "w1:p1", Herdr.Notice(agent: "Claude", status: "blocked", title: "fix login", pane: "w1:p1")))
        #expect(Herdr.event(in: ["id": "sub", "result": ["type": "subscription_started"]]) == nil)
    }

    @Test func herdrFindsNamedSessions() throws {
        let config = URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: config) }
        for name in ["work", "empty"] {
            try FileManager.default.createDirectory(at: config.appendingPathComponent("sessions/\(name)"), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: config.appendingPathComponent("sessions/work/herdr.sock").path, contents: nil)
        let sockets = Herdr.sockets(in: config)
        #expect(sockets.map(\.session) == [nil, "work"])
        #expect(sockets.map(\.url.lastPathComponent) == ["herdr.sock", "herdr.sock"])
        #expect(sockets.last?.url.deletingLastPathComponent().lastPathComponent == "work")
    }

    @Test func herdrCatchesChangesBetweenSubscriptions() {
        var states = Herdr.States()
        _ = states.reconcile([Herdr.Pane(id: "a", status: "working"), Herdr.Pane(id: "b", status: "blocked")])
        let missed = states.reconcile([Herdr.Pane(id: "a", status: "done", agent: "Pi"), Herdr.Pane(id: "b", status: "blocked"),
                                       Herdr.Pane(id: "c", status: "done")])
        // "a" finished while nothing listened; "b" didn't change; "c" is new, so its state is only learned.
        #expect(missed.map(\.id) == ["a"])
    }

    @Test func herdrAnnouncesOnlyChangesIntoDoneOrBlocked() {
        var states = Herdr.States()
        #expect(states.reconcile([Herdr.Pane(id: "a", status: "done"), Herdr.Pane(id: "b", status: "working")]).isEmpty)
        let steps = [("a", "done"), ("b", "working"), ("b", "blocked"), ("b", "blocked"), ("b", "working"), ("b", "done"),
                     ("new", "done")].map { states.update(pane: $0.0, to: $0.1) }
        // "a" was already done when listed; a pane created after the list counts.
        #expect(steps == [false, false, true, false, false, true, true])
    }
}

/// The watchers against stand-ins: a herdr socket served by a small Python script, and a `cmux` script.
@MainActor
struct TerminalAgentWatcherTests {
    private func temporary(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))-\(name)")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        // Up to five seconds, stopping as soon as it holds.
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Serves a herdr socket at `socket` that lists one working pane and then reports it done.
    private func fakeHerdr(at socket: URL) async throws -> () -> Void {
        let script = temporary("herdr.py")
        try """
        import json, os, socket, sys, threading, time
        path = sys.argv[1]
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path); server.listen(4)
        def serve(conn):
            reader = conn.makefile("r")
            for line in reader:
                request = json.loads(line)
                def send(obj): conn.sendall((json.dumps(obj) + "\\n").encode())
                if request["method"] == "pane.list":
                    send({"id": request["id"], "result": {"type": "pane_list", "panes": [
                        {"pane_id": "w1:p1", "agent_status": "working"}]}})
                elif request["method"] == "events.subscribe":
                    send({"id": request["id"], "result": {"type": "subscription_started"}})
                    time.sleep(0.2)
                    send({"event": "pane.agent_status_changed", "data": {"pane_id": "w1:p1", "workspace_id": "w1",
                          "agent_status": "done", "agent": "pi", "display_agent": "Pi", "title": "refactor"}})
                    time.sleep(5)
        while True:
            conn, _ = server.accept()
            threading.Thread(target=serve, args=(conn,), daemon=True).start()
        """.write(to: script, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path, socket.path]
        try server.run()
        await waitUntil { FileManager.default.fileExists(atPath: socket.path) }
        return {
            server.terminate()
            try? FileManager.default.removeItem(at: socket)
            try? FileManager.default.removeItem(at: script)
        }
    }

    @Test func herdrWatcherListsSubscribesAndAnnounces() async throws {
        let socket = temporary("herdr.sock")
        let shutDown = try await fakeHerdr(at: socket)
        defer { shutDown() }

        let watcher = HerdrWatcher(socketURL: socket)
        var received: [Herdr.Notice] = []
        watcher.onNotice = { received.append($0) }
        watcher.start()
        defer { watcher.stop() }
        await waitUntil { !received.isEmpty }
        #expect(received == [Herdr.Notice(agent: "Pi", status: "done", title: "refactor", pane: "w1:p1", socket: socket)])
    }

    @Test func herdrSessionsTellWhichSessionANoticeCameFrom() async throws {
        let config = temporary("config")
        try FileManager.default.createDirectory(at: config.appendingPathComponent("sessions/work"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: config) }
        let shutDown = try await fakeHerdr(at: config.appendingPathComponent("sessions/work/herdr.sock"))
        defer { shutDown() }

        let sessions = HerdrSessions(config: config)
        var received: [(Herdr.Notice, String?)] = []
        sessions.onNotice = { received.append(($0, $1)) }
        sessions.start()
        defer { sessions.stop() }
        await waitUntil { !received.isEmpty }
        #expect(received.map(\.0) == [Herdr.Notice(agent: "Pi", status: "done", title: "refactor", pane: "w1:p1",
                                                    socket: config.appendingPathComponent("sessions/work/herdr.sock"))])
        #expect(received.map(\.1) == ["work"])
    }

    @Test func cmuxWatcherLooksUpCreatedNotifications() async throws {
        let cli = temporary("cmux")
        try """
        #!/bin/sh
        if [ "$1" = events ]; then
          echo '{"type":"event","name":"notification.created","category":"notification","payload":{"notification_id":"N1","title":null}}'
          sleep 30
        elif [ "$1" = rpc ]; then
          echo '{"notifications":[{"id":"N1","title":"Pi","subtitle":"","body":"Turn complete","is_read":false}]}'
        fi
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        defer { try? FileManager.default.removeItem(at: cli) }

        let watcher = CmuxWatcher(cli: cli)
        var received: [Cmux.Notice] = []
        watcher.onNotice = { received.append($0) }
        watcher.start()
        defer { watcher.stop() }
        await waitUntil { !received.isEmpty }
        #expect(received == [Cmux.Notice(title: "Pi", body: "Turn complete", id: "N1")])
    }
}

struct TmuxHookTests {
    @Test func hookCommandQuotesNamesForTheShell() {
        let command = Tmux.hookCommand(script: URL(fileURLWithPath: "/Users/a/Library/Application Support/Nunsseop/tmux-notify.sh"))
        #expect(command == #"run-shell -b "'/Users/a/Library/Application Support/Nunsseop/tmux-notify.sh' tmux #{q:session_name} #{q:window_name} #{q:pane_current_command} #{q:pane_id}""#)
    }

    @Test func recognisesItsOwnHookOnly() {
        let script = URL(fileURLWithPath: "/x/terminal-notify.sh")
        let current = "alert-bell[4775] " + Tmux.hookCommand(script: script)
        #expect(Tmux.isHooked("alert-activity\n\(current)\n", script: script))
        #expect(!Tmux.isHooked("alert-bell[0] run-shell 'say bell'\n", script: script))
        #expect(!Tmux.isHooked("alert-bell[12] " + Tmux.hookCommand(script: script) + "\n", script: script))
        // A hook from an older version, without the pane id, gets replaced.
        #expect(!Tmux.isHooked("alert-bell[4775] run-shell -b \"'/x/terminal-notify.sh' tmux #{q:session_name} #{q:window_name} #{q:pane_current_command}\"\n", script: script))
    }
}

/// Against a real tmux server on a socket of its own, so the user's tmux is never touched.
@MainActor
struct TmuxWatcherTests {
    private func tmux(_ socket: String, _ arguments: String...) -> String? {
        let process = Process()
        process.executableURL = Tmux.binary
        process.arguments = ["-L", socket] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    private func waitUntil(_ condition: () -> Bool) async {
        // Up to five seconds, stopping as soon as it holds.
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test(.enabled(if: Tmux.isInstalled)) func bellReachesTheScriptWithEscapedNamesAndHookComesOff() async throws {
        let id = UUID().uuidString.prefix(8)
        let socket = "nunsseop-test-\(id)"
        let log = URL(fileURLWithPath: "/tmp/nunsseop-test-\(id).log")
        let pwned = URL(fileURLWithPath: "/tmp/nunsseop-test-\(id).pwned")
        let script = URL(fileURLWithPath: "/tmp/nunsseop-test-\(id) script.sh")
        defer {
            _ = tmux(socket, "kill-server")
            let socketFile = URL(fileURLWithPath: "/private/tmp/tmux-\(getuid())/\(socket)")
            for url in [log, pwned, script, socketFile] { try? FileManager.default.removeItem(at: url) }
        }
        #expect(tmux(socket, "-f", "/dev/null", "new-session", "-d", "-s", "work", "-n", "api", "sleep 60") != nil)
        // A program can rename its window to anything; none of it may run.
        #expect(tmux(socket, "rename-window", "-t", "work:api", "api\"; touch \(pwned.path); echo '$(touch \(pwned.path))") != nil)

        let watcher = TmuxWatcher(socketName: socket, scriptURL: script,
                                  script: "#!/bin/sh\nprintf '%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"$4\" >> \(log.path)\n")
        watcher.start()
        await waitUntil { Tmux.isHooked(tmux(socket, "show-hooks", "-g") ?? "", script: script) }
        #expect(Tmux.isHooked(tmux(socket, "show-hooks", "-g") ?? "", script: script))

        _ = tmux(socket, "respawn-pane", "-k", "-t", "work:0", "printf '\\a'; sleep 60")
        await waitUntil { FileManager.default.fileExists(atPath: log.path) }
        let line = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(line.hasPrefix("tmux|work|api\"; touch \(pwned.path); echo '$(touch \(pwned.path))|"))
        #expect(!FileManager.default.fileExists(atPath: pwned.path))

        watcher.stop(waiting: true)
        #expect(!Tmux.isHooked(tmux(socket, "show-hooks", "-g") ?? "", script: script))
    }
}

/// The bell script as shipped, with `curl` replaced by a stand-in that records what it was given.
struct TerminalBellScriptTests {
    private func run(_ arguments: [String]) throws -> (args: [String], body: String) {
        let dir = URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let support = dir.appendingPathComponent("Library/Application Support/Nunsseop")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "secret-token".write(to: support.appendingPathComponent("notify-token"), atomically: true, encoding: .utf8)
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let curl = bin.appendingPathComponent("curl")
        try """
        #!/bin/sh
        for arg; do printf '%s\\n' "$arg"; done > "\(dir.path)/args"
        cat > "\(dir.path)/body"
        """.write(to: curl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
        let script = dir.appendingPathComponent("terminal-notify.sh")
        TerminalBell.install(at: script)

        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.environment = ["HOME": dir.path, "PATH": "\(bin.path):/usr/bin:/bin", "__CFBundleIdentifier": "com.mitchellh.ghostty"]
        try process.run()
        process.waitUntilExit()
        let args = try String(contentsOf: dir.appendingPathComponent("args"), encoding: .utf8).split(separator: "\n").map(String.init)
        let body = try String(contentsOf: dir.appendingPathComponent("body"), encoding: .utf8)
        return (args, body)
    }

    @Test func postsTheAgentAndWhereTheBellRang() throws {
        let sent = try run(["tmux", "work", "api", "claude"])
        #expect(sent.args.contains("http://127.0.0.1:\(NotifyServer.port)/notify"))
        #expect(sent.args.contains("Authorization: Bearer secret-token"))
        #expect(sent.args.contains("X-Title: claude"))
        #expect(sent.args.contains("X-Agent: claude"))
        #expect(sent.body == "work · api")
        #expect(sent.args.contains("X-App: com.mitchellh.ghostty"))
        #expect(sent.args.contains("X-Target: "))
        let withPane = try run(["tmux", "work", "api", "claude", "%12"])
        #expect(withPane.args.contains("X-Target: tmux:%12"))
        let hostile = try run(["tmux", "work", "api", "claude", "%1; touch x\r\nX-Evil: 1"])
        #expect(hostile.args.contains("X-Target: tmux:%1touchxX-Evil1"))
    }

    @Test func fallsBackToTheTerminalAndKeepsHeadersClean() throws {
        let sent = try run(["WezTerm", "", "build\r\nX-Evil: 1", "bad name\r\nX-Agent: claude"])
        #expect(sent.args.contains("X-Title: badnameX-Agentclaude"))
        #expect(!sent.args.contains { $0.contains("\r") || $0 == "X-Evil: 1" })
        #expect(sent.body == "build\r\nX-Evil: 1")
        let empty = try run(["WezTerm", "default", "", ""])
        #expect(empty.args.contains("X-Title: WezTerm"))
        #expect(empty.body == "default")
    }
}

struct WezTermSnippetTests {
    @Test func callsTheScriptWithoutAShell() {
        let snippet = WezTerm.snippet(script: URL(fileURLWithPath: "/Users/a/Library/Application Support/Nunsseop/terminal-notify.sh"))
        #expect(snippet.contains("wezterm.on('bell', function(window, pane)"))
        #expect(snippet.contains("wezterm.background_child_process({ [==[/Users/a/Library/Application Support/Nunsseop/terminal-notify.sh]==], 'WezTerm', window:active_workspace(), pane:get_title(), process, tostring(pane:pane_id()) })"))
        #expect(!snippet.contains("os.execute") && !snippet.contains("run_child_process"))
    }
}


struct NoticeClickTests {
    @Test func muxyGoesToTheNotificationsTab() throws {
        let entry: [[String: Any]] = [["id": "N", "title": "Pi", "body": "done", "isRead": false, "source": ["aiProvider": ["_0": "pi"]],
                                       "projectID": "AA2932BC-99A4-4172-845B-99E03F715C77",
                                       "worktreeID": "E8EE3F1F-3D0F-404B-83B7-8E89D7A0B59E",
                                       "tabID": "129BB77D-F173-4DB8-B231-6C7FF885213D"]]
        let notice = try #require(MuxyNotice.parse(JSONSerialization.data(withJSONObject: entry))?.first)
        #expect(notice.focusCommands == [
            "switch-project|AA2932BC-99A4-4172-845B-99E03F715C77",
            "switch-worktree|E8EE3F1F-3D0F-404B-83B7-8E89D7A0B59E|AA2932BC-99A4-4172-845B-99E03F715C77",
            "switch-tab|129BB77D-F173-4DB8-B231-6C7FF885213D",
        ])
    }

    @Test func muxyIdsThatCouldAddCommandsAreRefused() {
        let hostile = MuxyNotice(id: "N", title: "", body: "", isRead: false, provider: nil,
                                 projectID: "AA|close-pane", worktreeID: nil, tabID: "12\nkill-session")
        #expect(hostile.focusCommands.isEmpty)
        let partly = MuxyNotice(id: "N", title: "", body: "", isRead: false, provider: nil,
                                projectID: "AA2932BC", worktreeID: "x|y", tabID: nil)
        #expect(partly.focusCommands == ["switch-project|AA2932BC"])
        #expect(MuxyNotice(id: "N", title: "", body: "", isRead: false, provider: nil).focusCommands.isEmpty)
    }

    @Test func localNoticesLeadToTheirPaneOrApp() {
        #expect(TerminalFocus.action(app: nil, target: "tmux:%3") != nil)
        #expect(TerminalFocus.action(app: nil, target: "WezTerm:7") != nil)
        #expect(TerminalFocus.action(app: nil, target: nil) == nil)
        #expect(TerminalFocus.action(app: nil, target: "other:1") == nil)
        // Apps that aren't running aren't launched for a notice.
        #expect(TerminalFocus.action(app: "com.example.not-running", target: nil) == nil)
        #expect(TerminalFocus.action(app: "com.apple.finder", target: nil) != nil)
    }

    @Test func parentProcess() {
        #expect(TerminalFocus.parentPID(of: getpid()) == getppid())
        #expect(TerminalFocus.parentPID(of: -1) == nil)
    }

    @Test func socketClientReadsOneReplyPerLine() throws {
        let path = "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8)).sock"
        let script = """
        import socket, sys
        s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1)
        c, _ = s.accept(); f = c.makefile("rwb")
        for line in f:
            f.write(b"ok:" + line); f.flush()
        """
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", script, path]
        try server.run()
        defer { server.terminate(); try? FileManager.default.removeItem(atPath: path) }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: path) { usleep(20_000) }
        #expect(TerminalFocus.send(["switch-project|A", "switch-tab|B"], toSocket: path) == ["ok:switch-project|A", "ok:switch-tab|B"])
        #expect(TerminalFocus.send(["x"], toSocket: "/tmp/nunsseop-missing.sock").isEmpty)
    }

    @Test func muxyCommandsGetAConnectionEach() throws {
        // Like Muxy: one reply, then the connection closes.
        let path = "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8)).sock"
        let script = """
        import socket, sys
        s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(4)
        while True:
            c, _ = s.accept(); line = c.makefile("rb").readline()
            c.sendall(b"ok " + line); c.close()
        """
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", script, path]
        try server.run()
        defer { server.terminate(); try? FileManager.default.removeItem(atPath: path) }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: path) { usleep(20_000) }
        let commands = ["switch-project|A", "switch-worktree|B|A", "switch-tab|C"]
        #expect(MuxyNotice.send(commands, toSocket: path) == commands.map { "ok \($0)" })
        // On one connection only the first would get through.
        #expect(TerminalFocus.send(commands, toSocket: path).count == 1)
    }

    @MainActor @Test func clickingANoticeRunsItsActionInsteadOfOpening() {
        let hud = HUDCenter(settings: AppSettings.shared)
        var went = 0
        hud.show(.notice(symbol: "terminal", title: "Pi", detail: nil), duration: 6, action: { went += 1 })
        #expect(hud.action != nil)
        #expect(hud.performAction())
        #expect(went == 1)
        #expect(hud.event == nil && hud.action == nil)
        hud.show(.notice(symbol: "timer", title: "Done", detail: nil), duration: 6)
        #expect(!hud.performAction())
        #expect(hud.event != nil)
        // A notice that replaces a clickable one doesn't keep its action.
        hud.show(.notice(symbol: "terminal", title: "Pi", detail: nil), duration: 6, action: { went += 1 })
        hud.show(.volume(0.5, muted: false))
        #expect(hud.action == nil)
    }
}

/// tmux's focus against a real server on a socket of its own.
@MainActor
struct TmuxFocusTests {
    private func tmux(_ socket: String, _ arguments: String...) -> String? {
        TerminalFocus.run(Tmux.binary!, ["-L", socket] + arguments)
    }

    @Test(.enabled(if: Tmux.isInstalled)) func focusSelectsThePanesWindowAndPane() async throws {
        let socket = "nunsseop-test-\(UUID().uuidString.prefix(8))"
        defer {
            _ = tmux(socket, "kill-server")
            try? FileManager.default.removeItem(atPath: "/private/tmp/tmux-\(getuid())/\(socket)")
        }
        _ = tmux(socket, "-f", "/dev/null", "new-session", "-d", "-s", "work", "-n", "one", "sleep 60")
        _ = tmux(socket, "new-window", "-d", "-t", "work", "-n", "two", "sleep 60")
        _ = tmux(socket, "split-window", "-d", "-t", "work:two", "sleep 60")
        let panes = (tmux(socket, "list-panes", "-t", "work:two", "-F", "#{pane_id}") ?? "").split(separator: "\n").map(String.init)
        let target = try #require(panes.last)
        #expect(tmux(socket, "display-message", "-p", "#{window_name}")?.trimmingCharacters(in: .whitespacesAndNewlines) == "one")

        Tmux.focus(pane: target, socketName: socket)
        var active = ""
        for _ in 0..<100 {
            active = tmux(socket, "display-message", "-p", "#{window_name} #{pane_id}")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if active == "two \(target)" { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(active == "two \(target)")
        // Pane ids are numbers after %; anything else is ignored.
        Tmux.focus(pane: "%1; kill-server", socketName: socket)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(tmux(socket, "display-message", "-p", "#{window_name}") != nil)
    }
}
