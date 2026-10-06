import Foundation
import SwiftUI
import Testing
@testable import Nunsseop

struct MeetingLinkTests {
    @Test func findsVideoCallLinks() {
        #expect(MeetingLink.find(in: ["https://us02web.zoom.us/j/123456?pwd=x"])?.host == "us02web.zoom.us")
        #expect(MeetingLink.find(in: [nil, "Room 4", "Join: https://meet.google.com/abc-defg-hij thanks"])?.absoluteString
                == "https://meet.google.com/abc-defg-hij")
        #expect(MeetingLink.find(in: ["<https://teams.microsoft.com/l/meetup-join/19%3a>"])?.host == "teams.microsoft.com")
        #expect(MeetingLink.find(in: ["https://acme.webex.com/meet/kim"]) != nil)
    }

    @Test func takesTheFirstFieldWithALink() {
        let url = MeetingLink.find(in: ["https://zoom.us/j/1", "https://meet.google.com/aaa-bbbb-ccc"])
        #expect(url?.host == "zoom.us")
    }

    @Test func ignoresOtherLinks() {
        #expect(MeetingLink.find(in: ["https://example.com/agenda", "https://notzoom.us/j/1", ""]) == nil)
        #expect(MeetingLink.find(in: []) == nil)
    }
}

struct EventAlertTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func event(_ id: String, in minutes: Double, allDay: Bool = false) -> CalendarItem {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarItem(id: id, title: id, start: start, end: start.addingTimeInterval(1800), isAllDay: allDay, color: .blue)
    }

    @Test func dueFiveMinutesBefore() {
        let items = [event("later", in: 30), event("soon", in: 4), event("sooner", in: 2)]
        let result = EventAlert.due(in: items, now: now, announced: [])
        #expect(result.due.map(\.id) == ["sooner", "soon"])
        #expect(result.next == now.addingTimeInterval(25 * 60))
    }

    @Test func skipsAnnouncedAllDayAndLongStarted() {
        let soon = event("soon", in: 3)
        let items = [soon, event("allDay", in: 1, allDay: true), event("started", in: -2), event("justStarted", in: -0.5)]
        let result = EventAlert.due(in: items, now: now, announced: [EventAlert.key(soon)])
        #expect(result.due.map(\.id) == ["justStarted"])
        #expect(result.next == nil)
    }

    @Test func repeatingOccurrencesHaveTheirOwnKey() {
        let today = event("standup", in: 3)
        let tomorrow = event("standup", in: 3 + 24 * 60)
        #expect(EventAlert.key(today) != EventAlert.key(tomorrow))
        let result = EventAlert.due(in: [today, tomorrow], now: now, announced: [EventAlert.key(today)])
        #expect(result.due.isEmpty)
        #expect(result.next == tomorrow.start.addingTimeInterval(-EventAlert.lead))
    }
}
