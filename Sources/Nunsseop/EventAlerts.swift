import Foundation

enum MeetingLink {
    /// Hosts of video calls a Join button opens, matched with their subdomains.
    private static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                "webex.com", "facetime.apple.com", "whereby.com", "chime.aws"]
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The first video-call link in the texts (an event's URL, location and notes), in order.
    static func find(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                if let url = match.url, isMeeting(url) { return url }
            }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard url.scheme == "https" || url.scheme == "http", let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

enum EventAlert {
    /// Seconds before the start that an event is announced.
    static let lead: TimeInterval = 5 * 60
    /// An alert that comes due this long after the start (after sleep, say) is still shown; later ones are dropped.
    static let grace: TimeInterval = 60

    /// A key per occurrence, since repeating events share one identifier.
    static func key(_ item: CalendarItem) -> String { "\(item.id)|\(item.start.timeIntervalSinceReferenceDate)" }

    /// Timed events whose alert is due at `now`, soonest first, and when the next one comes due.
    static func due(in items: [CalendarItem], now: Date, announced: Set<String>) -> (due: [CalendarItem], next: Date?) {
        let pending = items.filter { !$0.isAllDay && !announced.contains(key($0)) && $0.start.timeIntervalSince(now) > -grace }
        let due = pending.filter { $0.start.addingTimeInterval(-lead) <= now }.sorted { $0.start < $1.start }
        let next = pending.map { $0.start.addingTimeInterval(-lead) }.filter { $0 > now }.min()
        return (due, next)
    }
}
