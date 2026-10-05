import Foundation
import Testing
@testable import Nunsseop

struct AIUsageParseTests {
    private func data(_ lines: String...) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    @Test func familyFollowsTheModelOrProvider() {
        #expect(AIUsageModel.family(provider: "anthropic", model: "claude-sonnet-5") == .claude)
        #expect(AIUsageModel.family(provider: "openrouter", model: "anthropic/claude-opus") == .claude)
        #expect(AIUsageModel.family(provider: "openai-codex", model: "gpt-5.5") == .codex)
        #expect(AIUsageModel.family(provider: "openai", model: nil) == .codex)
        #expect(AIUsageModel.family(provider: "google", model: "gemini-3-pro") == nil)
    }

    @Test func claudeCodeCountsInputOutputAndCacheWrites() {
        let records = AIUsageModel.claudeCodeRecords(data(
            #"{"type":"user","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"user"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:05.000Z","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":300,"cache_read_input_tokens":5000}}}"#,
            #"{"type":"assistant","timestamp":"not a date","message":{"id":"msg_2","usage":{"input_tokens":1}}}"#
        ))
        #expect(records.count == 1)
        #expect(records.first?.id == "msg_1")
        #expect(records.first?.tokens == 330)
        #expect(records.first?.family == .claude)
    }

    @Test func piLogsMapProvidersAndUseResponseIds() {
        let records = AIUsageModel.piRecords(data(
            #"{"type":"message","id":"a1","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-5","usage":{"input":2,"output":100,"cacheRead":900,"cacheWrite":50},"timestamp":1790848800000,"responseId":"msg_x"}}"#,
            #"{"type":"message","id":"b2","timestamp":"2026-10-01T10:01:00.000Z","message":{"role":"assistant","provider":"openai-codex","model":"gpt-5.5","usage":{"input":7,"output":3,"cacheRead":0,"cacheWrite":0}}}"#,
            #"{"type":"message","id":"c3","timestamp":"2026-10-01T10:02:00.000Z","message":{"role":"assistant","provider":"google","model":"gemini-3-pro","usage":{"input":1,"output":1}}}"#
        ), file: "/s.jsonl")
        #expect(records.map(\.family) == [.claude, .codex])
        #expect(records.map(\.tokens) == [152, 10])
        #expect(records.map(\.id) == ["msg_x", "/s.jsonl#b2"])
        #expect(records.first?.date == Date(timeIntervalSince1970: 1_790_848_800))
    }

    @Test func codexLeavesOutCachedInputAndRepeatedCounts() {
        let line = #"{"timestamp":"2026-10-01T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000},"last_token_usage":{"input_tokens":900,"cached_input_tokens":600,"output_tokens":100}}}}"#
        let records = AIUsageModel.codexRecords(data(
            line, line,
            #"{"timestamp":"2026-10-01T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#
        ), file: "/r.jsonl")
        #expect(records.map(\.tokens) == [400, 400])
        let totals = AIUsageModel.totals([("Codex", records)], now: Date(timeIntervalSince1970: 1_790_850_000))
        #expect(totals[.codex]?.weekly == 400)
    }

    @Test func openCodeRowsCountReasoningAndCacheWrites() {
        let row = Data(#"{"role":"assistant","providerID":"openai","modelID":"gpt-5.5","tokens":{"input":500,"output":160,"reasoning":40,"cache":{"read":80000,"write":10}},"time":{"created":1790848800000}}"#.utf8)
        let record = AIUsageModel.openCodeRecord(id: "msg_oc", data: row)
        #expect(record == .init(id: "msg_oc", family: .codex, date: Date(timeIntervalSince1970: 1_790_848_800), tokens: 710))
        #expect(AIUsageModel.openCodeRecord(id: "u", data: Data(#"{"role":"user","time":{"created":1}}"#.utf8)) == nil)
    }

    @Test func totalsDeduplicateAcrossToolsAndSplitWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func record(_ id: String?, hoursAgo: Double, _ tokens: Int, _ family: AIUsageModel.Family = .claude) -> AIUsageModel.TokenRecord {
            .init(id: id, family: family, date: now.addingTimeInterval(-hoursAgo * 3600), tokens: tokens)
        }
        let totals = AIUsageModel.totals([
            ("Claude Code", [record("m1", hoursAgo: 1, 100), record("m2", hoursAgo: 30, 50), record("old", hoursAgo: 200, 999)]),
            ("gjc", [record("m1", hoursAgo: 1, 100), record("m3", hoursAgo: 2, 7), record(nil, hoursAgo: 3, 0)]),
            ("omo", [record(nil, hoursAgo: 4, 0)]),
            ("OpenCode", [record("o1", hoursAgo: 6, 20, .codex)]),
        ], now: now)
        #expect(totals[.claude] == .init(session: 107, weekly: 157, tools: ["Claude Code", "gjc"]))
        #expect(totals[.codex] == .init(session: 0, weekly: 20, tools: ["OpenCode"]))
    }

    @Test func gjcReportGivesBothWindows() throws {
        let later = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        let json = """
        {"value":{"provider":"anthropic","fetchedAt":1790889000000,"limits":[
          {"scope":{"windowId":"5h"},"window":{"id":"5h","resetsAt":\(later)},"amount":{"used":4,"usedFraction":0.04,"unit":"percent"}},
          {"scope":{"windowId":"7d"},"window":{"id":"7d","resetsAt":\(later)},"amount":{"used":20,"unit":"percent"}}]}}
        """
        let (family, limits) = try #require(AIUsageModel.gjcLimits(Data(json.utf8)))
        #expect(family == .claude)
        #expect(limits.source == "gjc")
        #expect(limits.updatedAt == Date(timeIntervalSince1970: 1_790_889_000))
        #expect(limits.session?.percent == 4)
        #expect(limits.weekly?.percent == 20)
        #expect(AIUsageModel.gjcLimits(Data(#"{"value":{"provider":"google","fetchedAt":1,"limits":[]}}"#.utf8)) == nil)
    }

    @Test func omcAndCodexLimitsCarryTheirTimes() throws {
        let omc = try #require(AIUsageModel.omcLimits(Data(#"{"lastSuccessAt":1790000000000,"data":{"fiveHourPercent":13,"weeklyPercent":3,"weeklyResetsAt":"2020-01-01T00:00:00.000Z"}}"#.utf8)))
        #expect(omc.updatedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(omc.session?.percent == 13)
        #expect(omc.weekly == .init(percent: 0, resetsAt: nil))
        #expect(omc.source == nil)

        let text = #"{"timestamp":"2026-10-01T10:00:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":10.0},"secondary":{"used_percent":15.0}}}}"#
        let codex = try #require(AIUsageModel.codexLimits(text, modified: .distantPast))
        #expect(codex.session?.percent == 10)
        #expect(codex.weekly?.percent == 15)
        #expect(codex.updatedAt == ISO8601DateFormatter().date(from: "2026-10-01T10:00:00Z"))
    }
}
