import Foundation
import SwiftUI

/// Usage of AI coding tools, read only from files those tools already keep on this Mac.
/// Claude: the limits the oh-my-claudecode HUD caches, when present, and token totals from
/// Claude Code's conversation logs. Codex: the limits it records in its session logs.
@MainActor
final class AIUsageModel: ObservableObject {
    struct Window: Equatable {
        let percent: Double
        let resetsAt: Date?
    }

    struct Provider: Identifiable, Equatable {
        let id: String
        let name: String
        var session: Window?
        var weekly: Window?
        var sessionTokens: Int?
        var weeklyTokens: Int?
        var updatedAt: Date?
    }

    @Published private(set) var providers: [Provider] = []
    @Published private(set) var loading = false

    /// Without `includeTokens` only the limits are read, which is cheap; the token totals from the last refresh are kept.
    func refresh(includeTokens: Bool = true) {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .utility) {
            let found = [Self.claude(includeTokens: includeTokens), Self.codex()].compactMap { $0 }
            await MainActor.run {
                self.providers = includeTokens ? found : found.map { provider in
                    var provider = provider
                    if let old = self.providers.first(where: { $0.id == provider.id }) {
                        provider.sessionTokens = old.sessionTokens
                        provider.weeklyTokens = old.weeklyTokens
                    }
                    return provider
                }
                self.loading = false
            }
        }
    }

    /// A window whose reset time has passed has started over.
    nonisolated private static func window(percent: Double?, resetsAt: Date?) -> Window? {
        guard let percent else { return nil }
        if let resetsAt, resetsAt < .now { return Window(percent: 0, resetsAt: nil) }
        return Window(percent: percent, resetsAt: resetsAt)
    }

    nonisolated private static let home = URL(fileURLWithPath: NSHomeDirectory())

    nonisolated private static func files(under root: URL, modifiedSince date: Date, where match: (URL) -> Bool) -> [(URL, Date)] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: [(URL, Date)] = []
        for case let url as URL in enumerator where match(url) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified >= date { result.append((url, modified)) }
        }
        return result
    }

    // MARK: Claude

    nonisolated private static func claude(includeTokens: Bool) -> Provider? {
        var provider = Provider(id: "claude", name: "Claude Code")
        let cache = home.appendingPathComponent(".claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json")
        if let data = try? Data(contentsOf: cache),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let usage = json["data"] as? [String: Any],
           let stamp = json["lastSuccessAt"] as? Double ?? json["timestamp"] as? Double {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            func date(_ key: String) -> Date? { (usage[key] as? String).flatMap { iso.date(from: $0) } }
            provider.session = window(percent: usage["fiveHourPercent"] as? Double, resetsAt: date("fiveHourResetsAt"))
            provider.weekly = window(percent: usage["weeklyPercent"] as? Double, resetsAt: date("weeklyResetsAt"))
            provider.updatedAt = Date(timeIntervalSince1970: stamp / 1000)
        }
        if includeTokens, let totals = claudeTokens() {
            provider.sessionTokens = totals.session
            provider.weeklyTokens = totals.weekly
        }
        return provider.session == nil && provider.weekly == nil && provider.weeklyTokens == nil ? nil : provider
    }

    /// Tokens Claude Code used in the last five hours and seven days, from its conversation logs.
    nonisolated private static func claudeTokens() -> (session: Int, weekly: Int)? {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let sessionStart = now.addingTimeInterval(-5 * 3_600)
        let logs = files(under: home.appendingPathComponent(".claude/projects"), modifiedSince: weekAgo) { $0.pathExtension == "jsonl" }
        guard !logs.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let marker = Data("\"type\":\"assistant\"".utf8)
        var seen = Set<String>()
        var session = 0, weekly = 0
        for (url, _) in logs {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard line.range(of: marker) != nil,
                      let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let stamp = (json["timestamp"] as? String).flatMap({ iso.date(from: $0) }), stamp >= weekAgo,
                      let message = json["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                if let id = message["id"] as? String, !seen.insert(id).inserted { continue }
                let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens"]
                    .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
                weekly += tokens
                if stamp >= sessionStart { session += tokens }
            }
        }
        return (session, weekly)
    }

    // MARK: Codex

    nonisolated private static func codex() -> Provider? {
        let logs = files(under: home.appendingPathComponent(".codex/sessions"), modifiedSince: .distantPast) {
            $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
        }
        guard let (file, modified) = logs.max(by: { $0.1 < $1.1 }), let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 1_000_000 ? size - 1_000_000 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let limits = (json["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] else { continue }
            func parse(_ key: String) -> Window? {
                guard let entry = limits[key] as? [String: Any] else { return nil }
                let reset = (entry["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                return window(percent: entry["used_percent"] as? Double, resetsAt: reset)
            }
            return Provider(id: "codex", name: "Codex", session: parse("primary"), weekly: parse("secondary"), updatedAt: modified)
        }
        return nil
    }
}

struct AIUsageTab: View {
    @ObservedObject var usage: AIUsageModel

    var body: some View {
        HStack(spacing: 10) {
            if usage.providers.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                    Text(usage.loading ? String(localized: "Loading…") : String(localized: "No AI usage found"))
                        .font(.system(size: 13, weight: .semibold))
                    if !usage.loading {
                        Text("Usage appears here once you have used Claude Code or Codex on this Mac.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(usage.providers) { provider in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(provider.name).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if let updated = provider.updatedAt {
                            Text("Updated \(updated, format: .relative(presentation: .named))")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    if let window = provider.session {
                        UsageBar(title: String(localized: "5-hour"), window: window)
                    }
                    if let window = provider.weekly {
                        UsageBar(title: String(localized: "Weekly"), window: window)
                    }
                    if let session = provider.sessionTokens, let weekly = provider.weeklyTokens {
                        HStack(spacing: 12) {
                            TokenRow(title: String(localized: "Last 5 hours"), tokens: session)
                            TokenRow(title: String(localized: "Last 7 days"), tokens: weekly)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .surface(RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundStyle(.white)
        .task {
            // Limits are cheap to read, so they refresh often; the token totals scan logs and refresh every 2 minutes.
            var tick = 0
            while !Task.isCancelled {
                usage.refresh(includeTokens: tick % 6 == 0)
                tick += 1
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }
}

private struct TokenRow: View {
    let title: String
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            Text("\(tokens.formatted(.number.notation(.compactName))) tokens")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageBar: View {
    let title: String
    let window: AIUsageModel.Window

    private var tint: Color {
        window.percent >= 90 ? .red : window.percent >= 70 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 11, weight: .medium))
                if let reset = window.resetsAt {
                    Text("Resets \(reset, format: .relative(presentation: .named))")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer()
                Text("\(Int(window.percent.rounded()))%").font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, window.percent / 100)))
                }
            }
            .frame(height: 6)
        }
    }
}
