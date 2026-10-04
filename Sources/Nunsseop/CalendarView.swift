import SwiftUI

struct CalendarPanel: View {
    @ObservedObject var calendar: CalendarModel
    let showsReminders: Bool
    @State private var showingReminders = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WeekStrip(calendar: calendar)
            if showsReminders && calendar.access == .granted {
                HStack(spacing: 4) {
                    PanelSwitch(title: String(localized: "Events"), count: calendar.items.count,
                                selected: !showingReminders) { showingReminders = false }
                    PanelSwitch(title: String(localized: "Reminders"), count: calendar.reminders.count,
                                selected: showingReminders) { showingReminders = true }
                }
            }
            Group {
                switch calendar.access {
                case .granted:
                    ScrollView(.vertical, showsIndicators: false) {
                        if showsReminders && showingReminders {
                            ReminderList(calendar: calendar)
                        } else {
                            EventList(items: calendar.items)
                        }
                    }
                case .unknown, .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(calendar.access == .denied
                             ? String(localized: "Calendar access is off")
                             : String(localized: "Allow calendar access to see your events"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                        Button(calendar.access == .denied ? String(localized: "Open System Settings") : String(localized: "Allow Access")) {
                            calendar.requestAccess()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.15)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
    }
}

/// The month, then today in large accent digits followed by the next few days.
private struct WeekStrip: View {
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(calendar.week.first ?? .now, format: .dateTime.month(.abbreviated))
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 4)
            ForEach(calendar.week.prefix(5), id: \.self) { day in
                let today = Calendar.current.isDateInToday(day)
                let selected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay)
                let weekend = Calendar.current.isDateInWeekend(day)
                Button { calendar.selectedDay = day } label: {
                    VStack(spacing: 0) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(selected ? 0.85 : 0.4))
                        Text(String(format: "%02d", Calendar.current.component(.day, from: day)))
                            .font(.system(size: today ? 19 : 13, weight: today ? .heavy : .semibold).monospacedDigit())
                            .foregroundStyle(today ? Color.blue : (weekend ? Color.red.opacity(0.8) : .white.opacity(selected ? 1 : 0.55)))
                            .fixedSize()
                    }
                    .frame(maxWidth: today ? nil : .infinity)
                    .padding(.horizontal, today ? 2 : 0)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(selected && !today ? 0.15 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PanelSwitch: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(count > 0 ? "\(title) \(count)" : title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 0.95 : 0.45))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ReminderList: View {
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch calendar.reminderAccess {
            case .granted:
                if calendar.reminders.isEmpty {
                    Text("No reminders").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                ForEach(calendar.reminders) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Button { calendar.complete(item) } label: {
                            Image(systemName: "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(item.color)
                        }
                        .buttonStyle(.plain)
                        .help(Text("Mark as completed"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            if let due = item.due {
                                Text(due.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(due < .now ? .red.opacity(0.8) : .white.opacity(0.5))
                            }
                        }
                    }
                }
            case .unknown, .denied:
                Button(calendar.reminderAccess == .denied ? String(localized: "Open System Settings") : String(localized: "Allow Reminders")) {
                    calendar.requestReminderAccess()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.15)))
            }
        }
    }
}

private struct EventList: View {
    let items: [CalendarItem]

    var body: some View {
        if items.isEmpty {
            Text("No events")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Capsule().fill(item.color).frame(width: 3, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(item.isAllDay ? String(localized: "All day") : "\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
        }
    }
}
