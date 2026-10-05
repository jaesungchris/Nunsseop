import AppKit
import Testing
@testable import Nunsseop

struct CallControlsShortcutTests {
    let zoomMute = CallControls.MenuApp.zoom.mic

    @Test func matchesCommandShiftKey() {
        // AXMenuItemCmdModifiers 1 is Shift; Command is implied while bit 3 is clear.
        #expect(zoomMute.matches(key: "A", modifiers: 1))
        #expect(zoomMute.matches(key: "a", modifiers: 1))
    }

    @Test func rejectsOtherKeysAndModifiers() {
        #expect(!zoomMute.matches(key: "A", modifiers: 0))  // ⌘A, Select All
        #expect(!zoomMute.matches(key: "A", modifiers: 3))  // ⌘⇧⌥A
        #expect(!zoomMute.matches(key: "V", modifiers: 1))
        #expect(!zoomMute.matches(key: nil, modifiers: nil))
    }

    @Test func faceTimeMuteIsCommandShiftM() {
        #expect(CallControls.MenuApp.faceTime.mic.matches(key: "M", modifiers: 1))
        #expect(!CallControls.MenuApp.faceTime.mic.matches(key: "M", modifiers: 0))  // ⌘M, Minimize
        #expect(CallControls.MenuApp.faceTime.camera == nil)
    }
}

struct CallControlsStateTests {
    let titles = CallControls.Titles(on: ["mute audio", "오디오 음소거"], off: ["unmute audio", "오디오 음소거 해제"])

    @Test func readsTitleInAnyShippedLanguage() {
        #expect(CallControls.toggle(title: "오디오 음소거", mark: nil, titles: titles, markMeansOff: false) == .on)
        #expect(CallControls.toggle(title: "오디오 음소거 해제", mark: nil, titles: titles, markMeansOff: false) == .off)
        #expect(CallControls.toggle(title: " Mute audio", mark: nil, titles: titles, markMeansOff: false) == .on)
    }

    @Test func unknownTitleOrAmbiguousTitleIsUnknown() {
        #expect(CallControls.toggle(title: "Mikrofon", mark: nil, titles: titles, markMeansOff: false) == .unknown)
        #expect(CallControls.toggle(title: nil, mark: nil, titles: titles, markMeansOff: false) == .unknown)
        let both = CallControls.Titles(on: ["x"], off: ["x"])
        #expect(CallControls.toggle(title: "x", mark: nil, titles: both, markMeansOff: false) == .unknown)
    }

    @Test func checkMarkMeansMutedOnlyWhereTheAppUsesIt() {
        let faceTime = CallControls.Titles(on: ["소리 끔"])
        #expect(CallControls.toggle(title: "소리 끔", mark: "✓", titles: faceTime, markMeansOff: true) == .off)
        #expect(CallControls.toggle(title: "소리 끔", mark: "", titles: faceTime, markMeansOff: true) == .on)
        #expect(CallControls.toggle(title: "오디오 음소거", mark: "✓", titles: titles, markMeansOff: false) == .on)
    }
}

struct MeetStateTests {
    @Test func parsesMicThenCamera() {
        #expect(CallControls.meetState(#"["true","false"]"#) == CallControls.State(mic: .off, camera: .on))
        #expect(CallControls.meetState(#"["false","true"]"#) == CallControls.State(mic: .on, camera: .off))
    }

    @Test func failsClosed() {
        #expect(CallControls.meetState(nil) == nil)
        #expect(CallControls.meetState("") == nil)
        #expect(CallControls.meetState(#"["true"]"#) == nil)
        #expect(CallControls.meetState(#"["true","false","true"]"#) == nil)
        #expect(CallControls.meetState(#"["true",""]"#) == nil)
        #expect(CallControls.meetState("not json") == nil)
    }
}

struct CallControlsTargetTests {
    private func call(_ name: String, _ bundleID: String) -> CallMonitor.Call {
        CallMonitor.Call(appName: name, bundleID: bundleID, icon: NSImage(), startedAt: Date(), title: nil)
    }

    @Test func meetIsControlledOnlyInChromiumBrowsers() {
        #expect(CallControls.Target(call("Google Meet", "com.google.Chrome")) == .meet(browserBundleID: "com.google.Chrome"))
        #expect(CallControls.Target(call("Google Meet", "com.apple.Safari")) == nil)
        #expect(CallControls.Target(call("Google Meet", "org.mozilla.firefox")) == nil)
    }

    @Test func menuAppsAreControlledThroughTheirMenus() {
        #expect(CallControls.Target(call("zoom.us", "us.zoom.xos")) == .menu(.zoom))
        #expect(CallControls.Target(call("FaceTime", "com.apple.FaceTime")) == .menu(.faceTime))
        #expect(CallControls.Target(call("Slack", "com.tinyspeck.slackmacgap")) == nil)
    }
}
