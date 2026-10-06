import Foundation
import Testing
@testable import Nunsseop

struct ClaudeUsageAPITests {
    @Test func readsClaudeCodesKeychainEntry() throws {
        let nested = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-x","expiresAt":1791300000000,"refreshToken":"r","scopes":["user:inference"]}}"#.utf8)
        let credentials = try #require(ClaudeUsageAPI.credentials(from: nested))
        #expect(credentials.token == "sk-ant-oat01-x")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_791_300_000))
        #expect(ClaudeUsageAPI.credentials(from: Data(#"{"accessToken":"flat"}"#.utf8))?.token == "flat")
        #expect(ClaudeUsageAPI.credentials(from: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
        #expect(ClaudeUsageAPI.credentials(from: Data("not json".utf8)) == nil)
    }

    @Test func readsTheUsageResponse() throws {
        // As api.anthropic.com/api/oauth/usage answers, trimmed.
        let response = Data(#"""
        {"five_hour":{"utilization":12.0,"resets_at":"2026-10-06T20:00:00.498908+00:00","limit_dollars":null},
         "seven_day":{"utilization":48.0,"resets_at":"2026-10-07T22:00:00.498933+00:00"},
         "seven_day_opus":null,"extra_usage":{"is_enabled":false}}
        """#.utf8)
        let fetched = try #require(ClaudeUsageAPI.date("2026-10-06T18:00:00Z"))
        let limits = try #require(ClaudeUsageAPI.limits(from: response, fetchedAt: fetched))
        #expect(limits.session?.percent == 12)
        #expect(limits.weekly?.percent == 48)
        #expect(limits.session?.resetsAt == ClaudeUsageAPI.date("2026-10-06T20:00:00.498Z"))
        #expect(limits.updatedAt == fetched)
        // A window whose reset has passed has started over.
        let later = try #require(ClaudeUsageAPI.date("2026-10-06T21:00:00Z"))
        #expect(ClaudeUsageAPI.limits(from: response, fetchedAt: later)?.session?.percent == 0)
        #expect(ClaudeUsageAPI.limits(from: Data(#"{"type":"error"}"#.utf8), fetchedAt: fetched) == nil)
    }

    @Test func readsMicrosecondTimes() {
        let expected = Date(timeIntervalSince1970: 1_791_316_800.498)   // 2026-10-06T20:00:00.498Z
        #expect(ClaudeUsageAPI.date("2026-10-06T20:00:00.498908+00:00").map { abs($0.timeIntervalSince(expected)) < 0.001 } == true)
        #expect(ClaudeUsageAPI.date("2026-10-06T20:00:00.4+00:00") != nil)
        #expect(ClaudeUsageAPI.date("2026-10-06T20:00:00Z") == Date(timeIntervalSince1970: 1_791_316_800))
        #expect(ClaudeUsageAPI.date("yesterday") == nil)
    }

    @Test func userAgentNamesARealClaudeCodeVersion() {
        #expect(ClaudeUsageAPI.userAgent(version: "2.1.291") == "claude-code/2.1.291")
        #expect(ClaudeUsageAPI.userAgent(version: " 2.0.0-beta.1\n") == "claude-code/2.0.0-beta.1")
        #expect(ClaudeUsageAPI.userAgent(version: "2.1") == nil)
        #expect(ClaudeUsageAPI.userAgent(version: "2.1.0\r\nX-Evil: 1") == nil)
        #expect(ClaudeUsageAPI.userAgent(version: nil) == nil)
    }

    @Test func requestCarriesTheSignInOnlyToAnthropic() {
        let request = ClaudeUsageAPI.request(token: "tok", userAgent: "claude-code/2.1.291")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "claude-code/2.1.291")
        #expect(ClaudeUsageAPI.request(token: "tok", userAgent: nil).value(forHTTPHeaderField: "User-Agent") == nil)
    }

    @Test func sessionKeepsNothingOnDisk() {
        let configuration = ClaudeUsageAPI.session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(ClaudeUsageAPI.session.delegate != nil)   // refuses redirects
    }

    /// A redirect to another server isn't followed, so the token never reaches it.
    @Test func redirectsAreNotFollowed() async throws {
        let log = "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8)).log"
        let script = """
        import http.server, sys, threading
        log = sys.argv[1]
        class Other(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                open(log, "a").write("other got: " + str(self.headers.get("Authorization")) + "\\n")
                self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
            def log_message(self, *a): pass
        class First(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302); self.send_header("Location", "http://localhost:%d/steal" % other.server_port); self.end_headers()
            def log_message(self, *a): pass
        other = http.server.HTTPServer(("127.0.0.1", 0), Other)
        first = http.server.HTTPServer(("127.0.0.1", 0), First)
        threading.Thread(target=other.serve_forever, daemon=True).start()
        print(first.server_port, flush=True)
        first.serve_forever()
        """
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", script, log]
        let output = Pipe()
        server.standardOutput = output
        try server.run()
        defer { server.terminate(); try? FileManager.default.removeItem(atPath: log) }
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
        let port = try #require(Int(line.trimmingCharacters(in: .whitespacesAndNewlines)))

        var request = ClaudeUsageAPI.request(token: "secret-token", userAgent: nil)
        request.url = URL(string: "http://127.0.0.1:\(port)/api/oauth/usage")
        let (_, response) = try await ClaudeUsageAPI.session.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 302)
        #expect(!FileManager.default.fileExists(atPath: log))
    }

    /// Against the real endpoint with this Mac's sign-in; opt in with NUNSSEOP_LIVE_USAGE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NUNSSEOP_LIVE_USAGE"] == "1"))
    func liveLimits() throws {
        let limits = try #require(ClaudeUsageAPI.current())
        print("LIVE five-hour \(limits.session?.percent ?? -1)% weekly \(limits.weekly?.percent ?? -1)% resets \(String(describing: limits.session?.resetsAt))")
        #expect(limits.session != nil || limits.weekly != nil)
    }
}
