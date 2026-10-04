import AppKit
import EventKit
import SwiftUI

struct CalendarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    let color: Color
}

@MainActor
final class CalendarModel: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access
    @Published var selectedDay = Calendar.current.startOfDay(for: .now) {
        didSet { reload() }
    }
    @Published private(set) var items: [CalendarItem] = []
    @Published private(set) var reminderAccess: Access
    @Published private(set) var reminders: [ReminderItem] = []

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    #if DEBUG
    private let isDemo = CommandLine.arguments.contains("--demo-track")
    #else
    private let isDemo = false
    #endif

    init() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .denied, .restricted, .writeOnly: access = .denied
        default: access = .unknown
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: reminderAccess = .granted
        case .denied, .restricted, .writeOnly: reminderAccess = .denied
        default: reminderAccess = .unknown
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    func requestAccess() {
        if access == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            return
        }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    func requestReminderAccess() {
        if reminderAccess == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
            return
        }
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.reminderAccess = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    func complete(_ item: ReminderItem) {
        reminders.removeAll { $0.id == item.id }
        guard !isDemo, let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    /// Incomplete reminders due by the end of the selected day, including undated ones.
    private func reloadReminders() {
        guard reminderAccess == .granted,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) else {
            reminders = []
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] found in
            let items = (found ?? [])
                .compactMap { reminder -> ReminderItem? in
                    let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    if let due, due >= end { return nil }
                    return ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                                        due: due, color: Color(nsColor: reminder.calendar?.color ?? .systemOrange))
                }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            DispatchQueue.main.async { self?.reminders = items }
        }
    }

    /// Fixed events for checking the layout without calendar access.
    private func showDemoItems() {
        access = .granted
        let day = selectedDay
        func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        items = [
            CalendarItem(id: "a", title: "Team standup", start: at(10, 0), end: at(10, 15), isAllDay: false, color: .blue),
            CalendarItem(id: "b", title: "Lunch", start: at(12, 30), end: at(13, 30), isAllDay: false, color: .orange),
            CalendarItem(id: "c", title: "5 km run", start: at(19, 0), end: at(19, 40), isAllDay: false, color: .green),
        ]
        reminderAccess = .granted
        reminders = [
            ReminderItem(id: "r1", title: "Pay the electricity bill", due: at(18, 0), color: .orange),
            ReminderItem(id: "r2", title: "Buy coffee beans", due: nil, color: .orange),
        ]
    }

    /// The selected day and the six days after it.
    var week: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) }
    }

    func reload() {
        if isDemo { showDemoItems(); return }
        reloadReminders()
        guard access == .granted else { items = []; return }
        let start = selectedDay
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        items = store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                CalendarItem(id: event.eventIdentifier ?? UUID().uuidString,
                             title: event.title ?? "",
                             start: event.startDate, end: event.endDate,
                             isAllDay: event.isAllDay,
                             color: Color(nsColor: event.calendar.color ?? .systemBlue))
            }
    }
}
