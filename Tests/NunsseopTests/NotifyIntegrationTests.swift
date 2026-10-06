import Foundation
import Testing
@testable import Nunsseop

struct JSONHookTests {
    @Test func addsAndRemovesHookInEmptySettings() throws {
        let settings = try JSONHook.adding(NotifyServer.hookCommand, to: [:])
        #expect(JSONHook.isInstalled(in: settings))
        #expect(!JSONHook.isInstalled(in: [:]))
        #expect(JSONHook.removing(from: settings).isEmpty)
    }

    @Test func keepsOtherHooksAndSettings() throws {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "other.sh"]]]
        let settings = try JSONHook.adding(NotifyServer.hookCommand(title: "Gemini CLI"), to: [
            "model": "opus",
            "hooks": ["Notification": [other], "Stop": [other]],
        ])
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect(settings["model"] as? String == "opus")
        #expect((hooks["Notification"] as? [[String: Any]])?.count == 2)
        #expect(JSONHook.isInstalled(in: settings))

        let removed = JSONHook.removing(from: settings)
        let remaining = try #require(removed["hooks"] as? [String: Any])
        #expect((remaining["Notification"] as? [[String: Any]])?.count == 1)
        #expect((remaining["Stop"] as? [[String: Any]])?.count == 1)
        #expect(!JSONHook.isInstalled(in: removed))
    }

    @Test func refusesUnexpectedShapes() {
        #expect(throws: NotifyIntegration.IntegrationError.self) { try JSONHook.adding("x", to: ["hooks": "x"]) }
        #expect(throws: NotifyIntegration.IntegrationError.self) {
            try JSONHook.adding("x", to: ["hooks": ["Notification": "x"]])
        }
    }
}

struct CodexNotifyTests {
    let script = CodexNotify.scriptURL.path

    @Test func parsesStringArrays() {
        #expect(CodexNotify.parseStringArray(#"["a", 'b c', "d\"e"]"#) == ["a", "b c", "d\"e"])
        #expect(CodexNotify.parseStringArray(#"["a",] # note"#) == ["a"])
        #expect(CodexNotify.parseStringArray("[]") == [])
        #expect(CodexNotify.parseStringArray(#"["a""#) == nil)
        #expect(CodexNotify.parseStringArray(#"["a"] x"#) == nil)
    }

    @Test func wrapsExistingCommandAndRestoresIt() throws {
        let text = "model = \"o3\"\nnotify = [\"/usr/bin/foo\", \"--bar\"]\n\n[tui]\nnotify = true\n"
        let added = try CodexNotify.adding(to: text)
        #expect(added.contains("notify = [\"/bin/sh\", \"\(script)\", \"/usr/bin/foo\", \"--bar\"]"))
        #expect(added.contains("[tui]\nnotify = true"))
        #expect(CodexNotify.isInstalled(in: added))
        #expect(!CodexNotify.isInstalled(in: text))
        #expect(try CodexNotify.removing(from: added) == text)
    }

    @Test func addsLineWhenThereIsNoneAndRemovesIt() throws {
        let text = "model = \"o3\"\n[tui]\nnotify = true\n"
        let added = try CodexNotify.adding(to: text)
        #expect(added.hasPrefix("notify = [\"/bin/sh\", \"\(script)\"]\n"))
        #expect(try CodexNotify.removing(from: added) == text)
    }

    @Test func refusesMultilineArray() {
        #expect(throws: NotifyIntegration.IntegrationError.self) {
            try CodexNotify.adding(to: "notify = [\n  \"foo\",\n]\n")
        }
    }
}
