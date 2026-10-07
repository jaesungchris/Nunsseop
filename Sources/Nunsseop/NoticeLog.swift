import SwiftUI

/// The notices agents, terminals, tools and the calendar sent, so one that was missed (it shows for a few seconds)
/// can still be read and followed. Kept in memory only: agents' messages can hold anything.
@MainActor
final class NoticeLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let symbol: String
        let title: String
        let detail: String?
        /// Going back to where it came from (a terminal tab, a meeting), when it said.
        let action: (() -> Void)?
    }

    static let limit = 30

    @Published private(set) var entries: [Entry] = []
    /// Notices since the tab was last looked at.
    @Published private(set) var unseen = 0
    /// While the tab is on screen, new notices are seen as they arrive.
    var isShowing = false {
        didSet { if isShowing { markSeen() } }
    }

    init() {
        #if DEBUG
        // Debug: --demo-notices fills the tab for checking its layout.
        if CommandLine.arguments.contains("--demo-notices") {
            add(symbol: "calendar", title: "Lunch", detail: "in 5 minutes", at: .now.addingTimeInterval(-3600))
            add(symbol: "terminal", title: "Pi · work", detail: "Finished · refactor the parser", action: {}, at: .now.addingTimeInterval(-900))
            add(symbol: "sparkles", title: "Claude Code", detail: "Claude is waiting for your input", action: {}, at: .now.addingTimeInterval(-60))
        }
        #endif
    }

    func add(symbol: String, title: String, detail: String?, action: (() -> Void)? = nil, at date: Date = .now) {
        entries.insert(Entry(date: date, symbol: symbol, title: title, detail: detail, action: action), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        if !isShowing { unseen = min(unseen + 1, Self.limit) }
    }

    func markSeen() { unseen = 0 }

    func remove(_ entry: Entry) { entries.removeAll { $0.id == entry.id } }

    func clear() {
        entries = []
        unseen = 0
    }
}

struct NoticesTab: View {
    @ObservedObject var log: NoticeLog

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recent notifications").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear") { log.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(log.entries.isEmpty ? 0.3 : 0.7))
                    .disabled(log.entries.isEmpty)
            }
            if log.entries.isEmpty {
                Text("Notifications from agents, terminals and your calendar show up here")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(log.entries) { entry in
                            NoticeRow(entry: entry) { log.remove(entry) }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { log.isShowing = true }
        .onDisappear { log.isShowing = false }
    }
}

private struct NoticeRow: View {
    let entry: NoticeLog.Entry
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)
                .foregroundStyle(.white.opacity(0.75))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.date, format: .dateTime.hour().minute())
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
            }
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(Text("Remove"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .surface(RoundedRectangle(cornerRadius: 10), opacity: hovering && entry.action != nil ? 0.14 : 0.08)
        .contentShape(Rectangle())
        // A notice that leads somewhere goes there again; the others just stay readable.
        .onTapGesture { entry.action?() }
        .onHover { hovering = $0 }
        .help(entry.action == nil ? Text(verbatim: "") : Text("Go to where it came from"))
    }
}
