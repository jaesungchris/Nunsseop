import Foundation
import os

/// Claude's limits straight from Anthropic, asked with the sign-in Claude Code keeps in the Keychain, so they're
/// current whatever spends them (Claude Code, apps built on the Agent SDK, claude.ai), not only while the
/// oh-my-claudecode HUD runs. Off until the user agrees. The token is only read: an expired one is skipped, never
/// refreshed, since Claude Code rotates it and a second writer could log it out; the limits then stop updating until
/// Claude Code signs in again. It goes nowhere but api.anthropic.com, and Nunsseop names itself, not Claude Code.
enum ClaudeUsageAPI {
    static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// How often the limits are asked for: a client that isn't Claude Code gets about one request an hour.
    static let interval: TimeInterval = 3600
    /// After a refusal (429) at least this long passes before asking again, longer if the server says so.
    static let backoff: TimeInterval = 600

    struct Credentials: Equatable {
        let token: String
        let expiresAt: Date?
    }

    private struct State {
        var limits: AIUsageModel.Limits?
        var nextAttempt = Date.distantPast
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Follows no redirects, so the sign-in can't be carried to another host, and keeps no cache or cookies,
    /// so the request with its Authorization header is never written to disk.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// Whether to ask at all (Settings › Services); read from the background, so it's stored atomically.
    private static let enabledFlag = OSAllocatedUnfairLock(initialState: true)
    static var isEnabled: Bool {
        get { enabledFlag.withLock { $0 } }
        set { enabledFlag.withLock { $0 = newValue } }
    }

    // MARK: Parsing

    /// Claude Code's Keychain entry: `{"claudeAiOauth": {"accessToken", "expiresAt" (ms)}}`.
    static func credentials(from data: Data) -> Credentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = json["claudeAiOauth"] as? [String: Any] ?? json
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(token: token, expiresAt: expires)
    }

    /// The 5-hour and 7-day windows of a usage response.
    static func limits(from data: Data, fetchedAt: Date) -> AIUsageModel.Limits? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> AIUsageModel.Window? {
            guard let entry = json[key] as? [String: Any], let percent = entry["utilization"] as? Double else { return nil }
            let resets = (entry["resets_at"] as? String).flatMap(date)
            if let resets, resets < fetchedAt { return AIUsageModel.Window(percent: 0, resetsAt: nil) }
            return AIUsageModel.Window(percent: percent, resetsAt: resets)
        }
        let session = window("five_hour"), weekly = window("seven_day")
        guard session != nil || weekly != nil else { return nil }
        return AIUsageModel.Limits(session: session, weekly: weekly, updatedAt: fetchedAt)
    }

    /// ISO 8601 times with up to microseconds (`2026-10-06T20:00:00.498908+00:00`), which ISO8601DateFormatter
    /// doesn't read beyond milliseconds, so the fraction is cut to three digits first.
    static func date(_ text: String) -> Date? {
        var text = text
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let digits = text[text.index(after: dot)..<end]
            text.replaceSubrange(dot..<end, with: "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        let fractional = ISO8601DateFormatter(), whole = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? whole.date(from: text)
    }

    /// Nunsseop and its version, rather than borrowing Claude Code's name.
    static var userAgent: String {
        "Nunsseop/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")"
    }

    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Windows whose reset time has passed have started over, however long ago the limits were fetched
    /// (an expired sign-in or a run of refusals can keep them from being fetched again).
    static func fresh(_ limits: AIUsageModel.Limits, now: Date) -> AIUsageModel.Limits {
        func reset(_ window: AIUsageModel.Window?) -> AIUsageModel.Window? {
            guard let window, let resets = window.resetsAt, resets < now else { return window }
            return AIUsageModel.Window(percent: 0, resetsAt: nil)
        }
        var limits = limits
        limits.session = reset(limits.session)
        limits.weekly = reset(limits.weekly)
        return limits
    }

    // MARK: Asking

    /// The last limits, asking Anthropic again when they're due.
    static func current(now: Date = .now) async -> AIUsageModel.Limits? {
        guard isEnabled else { return nil }
        let due = state.withLock { state -> Bool in
            guard now >= state.nextAttempt else { return false }
            state.nextAttempt = now.addingTimeInterval(interval)
            return true
        }
        if due { await fetch(now: now) }
        return state.withLock { $0.limits }.map { fresh($0, now: now) }
    }

    private static func fetch(now: Date) async {
        guard let credentials = keychainCredentials(now: now) else {
            // Not signed in, or the sign-in expired: asked again later, not on every refresh.
            state.withLock { $0.nextAttempt = now.addingTimeInterval(backoff) }
            return
        }
        guard let (data, response) = try? await session.data(for: request(token: credentials.token)),
              let response = response as? HTTPURLResponse else { return }
        switch response.statusCode {
        case 200:
            if let limits = limits(from: data, fetchedAt: .now) { state.withLock { $0.limits = limits } }
        case 429:
            // Capped, so an odd retry-after can't switch this off until relaunch.
            let asked = response.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? 0
            let wait = min(max(backoff, asked.isFinite ? asked : 0), interval * 4)
            state.withLock { $0.nextAttempt = now.addingTimeInterval(wait) }
        default:
            // 401/403: a token that stopped working; Claude Code will sign in again, and it's asked later.
            state.withLock { $0.nextAttempt = now.addingTimeInterval(backoff) }
        }
    }

    /// The user's own entry first: an older one under the account "Claude Code" can linger, long expired.
    private static func keychainCredentials(now: Date) -> Credentials? {
        for account in [NSUserName(), nil] {
            var arguments = ["find-generic-password", "-s", "Claude Code-credentials"]
            if let account { arguments += ["-a", account] }
            guard let output = run("/usr/bin/security", arguments + ["-w"]),
                  let credentials = credentials(from: Data(output.utf8)) else { continue }
            if let expires = credentials.expiresAt, expires <= now { continue }
            return credentials
        }
        return nil
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // A child that ignores SIGTERM gets SIGKILL, so a hung `security` can't stall every refresh.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
