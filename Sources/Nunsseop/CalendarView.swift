import SwiftUI

struct CalendarPanel: View {
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WeekStrip(calendar: calendar)
            Group {
                switch calendar.access {
                case .granted:
                    EventList(items: calendar.items)
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

private struct EventList: View {
    let items: [CalendarItem]

    var body: some View {
        if items.isEmpty {
            Text("No events")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
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
}
