import Testing
@testable import Nunsseop

struct ClaudeCodeHookTests {
    @Test func addsHookToEmptySettings() throws {
        let settings = try ClaudeCodeHook.adding(to: [:])
        #expect(ClaudeCodeHook.isInstalled(in: settings))
        #expect(!ClaudeCodeHook.isInstalled(in: [:]))
    }

    @Test func keepsOtherHooksAndSettings() throws {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "other.sh"]]]
        let settings = try ClaudeCodeHook.adding(to: [
            "model": "opus",
            "hooks": ["Notification": [other], "Stop": [other]],
        ])
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect(settings["model"] as? String == "opus")
        #expect((hooks["Notification"] as? [[String: Any]])?.count == 2)
        #expect((hooks["Stop"] as? [[String: Any]])?.count == 1)
        #expect(ClaudeCodeHook.isInstalled(in: settings))
    }

    @Test func refusesUnexpectedShapes() {
        #expect(throws: ClaudeCodeHook.InstallError.self) { try ClaudeCodeHook.adding(to: ["hooks": "x"]) }
        #expect(throws: ClaudeCodeHook.InstallError.self) {
            try ClaudeCodeHook.adding(to: ["hooks": ["Notification": "x"]])
        }
    }
}
