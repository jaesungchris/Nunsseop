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
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(50)) }
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
