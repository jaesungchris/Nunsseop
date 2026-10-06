import Foundation
import Testing
@testable import Nunsseop

struct MuxyNotificationTests {
    func feed(_ entries: [(id: String, read: Bool, provider: String?)]) -> Data {
        let list: [[String: Any]] = entries.map { entry in
            let source: [String: Any] = entry.provider.map { ["aiProvider": ["_0": $0]] } ?? ["osc": [String: Any]()]
            return ["id": entry.id, "title": "Pi", "body": "Session completed", "isRead": entry.read,
                    "source": source, "timestamp": 812978474.8, "paneID": "P"]
        }
        return try! JSONSerialization.data(withJSONObject: list)
    }

    @Test func parsesMuxyEntries() {
        let notices = MuxyNotice.parse(feed([("a", false, "pi"), ("b", true, nil)]))
        #expect(notices == [MuxyNotice(id: "a", title: "Pi", body: "Session completed", isRead: false, provider: "pi"),
                            MuxyNotice(id: "b", title: "Pi", body: "Session completed", isRead: true, provider: nil)])
    }

    @Test func halfWrittenFileIsNotAnEmptyList() {
        #expect(MuxyNotice.parse(Data("[{\"id\":".utf8)) == nil)
        #expect(MuxyNotice.parse(Data("{}".utf8)) == nil)
        #expect(MuxyNotice.parse(Data("[]".utf8)) == [])
    }

    @Test func historyIsNotReplayed() {
        var seen = MuxySeen()
        #expect(seen.fresh(in: MuxyNotice.parse(feed([("old", false, "claude")]))!).isEmpty)
        let next = MuxyNotice.parse(feed([("new", false, "pi"), ("read", true, "pi"), ("old", false, "claude")]))!
        #expect(seen.fresh(in: next).map(\.id) == ["new"])
        #expect(seen.fresh(in: next).isEmpty)
    }

    @Test func connectedToolsAreRecognised() {
        func provider(_ name: String?) -> NotifyIntegration? {
            MuxyNotice(id: "x", title: "", body: "", isRead: false, provider: name).integration
        }
        #expect(provider("claude") == .claudeCode)
        #expect(provider("codex") == .codex)
        #expect(provider("pi") == nil)
        #expect(provider(nil) == nil)
    }
}
