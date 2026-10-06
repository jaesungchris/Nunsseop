import Foundation

enum MeetingLink {
    /// Hosts of video calls a Join button opens, matched with their subdomains, and the paths their meetings use.
    private static let meetings: [(host: String, path: String)] = [
        ("zoom.us", "^/(j|my|w|s)/"),
        ("meet.google.com", "^/[a-z]{3}-[a-z]{4}-[a-z]{3}"),
        ("teams.microsoft.com", "^/(l/meetup-join|meet)/"),
        ("teams.live.com", "^/meet/"),
        ("webex.com", "^/(meet|join|wbxmjs)/|^/[^/]+/j\\.php"),
        ("facetime.apple.com", "^/join"),
        ("whereby.com", "^/[^/]+"),
        ("chime.aws", "^/[0-9]+"),
    ]
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The video-call link in the texts (an event's URL, location and notes). A link to an actual meeting wins
    /// over other links on a call service's site (`zoom.us/download`, say), and otherwise the first one counts.
    static func find(in texts: [String?]) -> URL? {
        var links: [(url: URL, isMeeting: Bool)] = []
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                // Only web links: a Join button must not open file:// or another app's scheme on a matching host,
                // including one hidden inside a Safe Links wrapper.
                guard let url = match.url.map(unwrapped),
                      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                      let host = url.host?.lowercased(),
                      let service = meetings.first(where: { host == $0.host || host.hasSuffix("." + $0.host) })
                else { continue }
                links.append((secure(url), url.path.range(of: service.path, options: .regularExpression) != nil))
            }
        }
        return (links.first(where: \.isMeeting) ?? links.first)?.url
    }

    /// The link inside an Outlook Safe Links wrapper, which Outlook puts around every link in an invitation.
    private static func unwrapped(_ url: URL) -> URL {
        guard url.host?.lowercased().hasSuffix("safelinks.protection.outlook.com") == true,
              let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: inner) else { return url }
        return target
    }

    /// Call services all answer on https, so a plain http link isn't opened as is.
    private static func secure(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = "https"
        return parts.url ?? url
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

extension EventAlert {
    /// Whether a notice for `item` may still show: alerts are on, the event hasn't been under way for long,
    /// and the occurrence is still among the alertable events (not cancelled, deleted, declined or hidden since).
    static func isStillDue(_ item: CalendarItem, enabled: Bool, among items: [CalendarItem], now: Date) -> Bool {
        enabled && item.start.timeIntervalSince(now) > -grace && items.contains { key($0) == key(item) }
    }
}

/// Decides which event to announce, one at a time: each notice gets `spacing` seconds before the next,
/// however often the events are checked in between.
struct EventAlertQueue {
    let spacing: TimeInterval
    private(set) var announced: Set<String> = []
    /// Nothing is announced before this.
    private(set) var quietUntil = Date.distantPast

    init(spacing: TimeInterval) { self.spacing = spacing }

    /// The event to announce now, if any, and when to check again.
    mutating func step(items: [CalendarItem], now: Date) -> (announce: CalendarItem?, next: Date?) {
        announced.formIntersection(items.map(EventAlert.key))
        let (due, next) = EventAlert.due(in: items, now: now, announced: announced)
        guard let first = due.first else { return (nil, next) }
        if now < quietUntil { return (nil, quietUntil) }
        announced.insert(EventAlert.key(first))
        quietUntil = now.addingTimeInterval(spacing)
        return (first, due.count > 1 ? quietUntil : next)
    }
}

/// Notices that must be seen once: one another HUD covers before its time is up comes back after it,
/// for the time it had left. It comes back once at most, so covered notices don't keep reshuffling.
struct LastingNotices<Notice> {
    /// Less than this left isn't worth bringing a notice back for.
    static var minimumReplay: TimeInterval { 1 }

    private struct Shown { let notice: Notice; let ends: Date; let isReplay: Bool }
    private var current: Shown?
    private(set) var interrupted: [(notice: Notice, remaining: TimeInterval)] = []

    /// Something else takes the HUD at `now` (a lasting notice, or nil for any other HUD).
    /// A first showing still on screen waits its turn; a notice already brought back once is dropped.
    mutating func replace(with notice: Notice?, duration: TimeInterval, now: Date) {
        if let current, !current.isReplay {
            let remaining = current.ends.timeIntervalSince(now)
            if remaining >= Self.minimumReplay { interrupted.append((current.notice, remaining)) }
        }
        current = notice.map { Shown(notice: $0, ends: now.addingTimeInterval(duration), isReplay: false) }
    }

    /// The HUD went away on its own at `now`. Returns the notice to bring back, if any, with how long to show it.
    mutating func finish(now: Date) -> (notice: Notice, remaining: TimeInterval)? {
        current = nil
        guard !interrupted.isEmpty else { return nil }
        let next = interrupted.removeFirst()
        current = Shown(notice: next.notice, ends: now.addingTimeInterval(next.remaining), isReplay: true)
        return next
    }
}
