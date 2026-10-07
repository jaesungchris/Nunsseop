import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct NoticeLogTests {
    @Test func newestFirstAndCapped() {
        let log = NoticeLog()
        for index in 0..<(NoticeLog.limit + 5) { log.add(symbol: "terminal", title: "n\(index)", detail: nil) }
        #expect(log.entries.count == NoticeLog.limit)
        #expect(log.entries.first?.title == "n\(NoticeLog.limit + 4)")
        #expect(log.entries.last?.title == "n5")
    }

    @Test func unseenCountsUntilLookedAt() {
        let log = NoticeLog()
        log.add(symbol: "terminal", title: "a", detail: nil)
        log.add(symbol: "calendar", title: "b", detail: "in 5 minutes")
        #expect(log.unseen == 2)
        log.markSeen()
        #expect(log.unseen == 0)
        log.add(symbol: "terminal", title: "c", detail: nil)
        #expect(log.unseen == 1)
        log.clear()
        #expect(log.entries.isEmpty && log.unseen == 0)
    }

    @Test func entriesKeepWhereTheyCameFrom() {
        let log = NoticeLog()
        var went = 0
        log.add(symbol: "terminal", title: "Pi", detail: "done", action: { went += 1 })
        log.add(symbol: "sparkles", title: "Script", detail: nil)
        let pi = log.entries[1]
        pi.action?()
        #expect(went == 1)
        #expect(log.entries[0].action == nil)
        log.remove(pi)
        #expect(log.entries.map(\.title) == ["Script"])
    }

    @Test func noBadgeForNoticesArrivingWhileTheTabIsOpenEvenWhenFull() {
        let log = NoticeLog()
        for index in 0..<NoticeLog.limit { log.add(symbol: "terminal", title: "n\(index)", detail: nil) }
        log.isShowing = true
        #expect(log.unseen == 0)
        // Full: the count stays at 30, which a count-based check would miss.
        log.add(symbol: "terminal", title: "new", detail: nil)
        #expect(log.entries.count == NoticeLog.limit)
        #expect(log.entries.first?.title == "new")
        #expect(log.unseen == 0)
        log.isShowing = false
        log.add(symbol: "terminal", title: "later", detail: nil)
        #expect(log.unseen == 1)
    }
}

@MainActor
struct LastingNoticeShownTests {
    @Test func tellsWhetherItShowed() {
        let hud = HUDCenter(settings: AppSettings.shared)
        // Declined from the start (alerts off, event cancelled or well under way): not shown, so not recorded.
        #expect(!hud.showLasting(duration: 8) { nil })
        #expect(hud.event == nil)
        #expect(hud.showLasting(duration: 8) { .notice(symbol: "calendar", title: "Lunch", detail: nil) })
        #expect(hud.event != nil)
    }
}
