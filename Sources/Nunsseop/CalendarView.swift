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

private struct WeekStrip: View {
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(calendar.week, id: \.self) { day in
                let selected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay)
                Button { calendar.selectedDay = day } label: {
                    VStack(spacing: 1) {
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(selected ? 0.9 : 0.4))
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .frame(width: 22, height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(selected ? 0.18 : 0)))
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
