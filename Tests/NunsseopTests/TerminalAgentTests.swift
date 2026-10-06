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
                == Cmux.Notice(title: "Codex", body: "Waiting · Agent needs input"))
        #expect(Cmux.notice("READ", inList: list) == nil)
        #expect(Cmux.notice("missing", inList: list) == nil)
        let wrapped = Data(#"{"result":{"notifications":[{"id":"A","title":"T","subtitle":"","body":"B"}]}}"#.utf8)
        #expect(Cmux.notice("A", inList: wrapped) == Cmux.Notice(title: "T", body: "B"))
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
        #expect(Herdr.event(in: status) == .status(pane: "w1:p1", Herdr.Notice(agent: "Claude", status: "blocked", title: "fix login")))
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
        #expect(received == [Herdr.Notice(agent: "Pi", status: "done", title: "refactor")])
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
        #expect(received.map(\.0) == [Herdr.Notice(agent: "Pi", status: "done", title: "refactor")])
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
        #expect(received == [Cmux.Notice(title: "Pi", body: "Turn complete")])
    }
}

struct TmuxHookTests {
    @Test func hookCommandQuotesNamesForTheShell() {
        let command = Tmux.hookCommand(script: URL(fileURLWithPath: "/Users/a/Library/Application Support/Nunsseop/tmux-notify.sh"))
        #expect(command == #"run-shell -b "'/Users/a/Library/Application Support/Nunsseop/tmux-notify.sh' tmux #{q:session_name} #{q:window_name} #{q:pane_current_command}""#)
    }

    @Test func recognisesItsOwnHookOnly() {
        let script = URL(fileURLWithPath: "/x/tmux-notify.sh")
        #expect(Tmux.isHooked("alert-activity\nalert-bell[4775] run-shell -b \"'/x/tmux-notify.sh' #{q:session_name}\"\n", script: script))
        #expect(!Tmux.isHooked("alert-bell[0] run-shell 'say bell'\n", script: script))
        #expect(!Tmux.isHooked("alert-bell[12] run-shell -b \"'/x/tmux-notify.sh'\"\n", script: script))
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
        process.environment = ["HOME": dir.path, "PATH": "\(bin.path):/usr/bin:/bin"]
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
        #expect(snippet.contains("wezterm.background_child_process({ [==[/Users/a/Library/Application Support/Nunsseop/terminal-notify.sh]==], 'WezTerm', window:active_workspace(), pane:get_title(), process })"))
        #expect(!snippet.contains("os.execute") && !snippet.contains("run_child_process"))
    }
}
