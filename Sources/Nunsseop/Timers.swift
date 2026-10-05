import AppKit
import SwiftUI

/// Countdown, Pomodoro and stopwatch. Only one runs at a time.
@MainActor
final class TimerModel: ObservableObject {
    enum Mode: String, CaseIterable { case countdown, pomodoro, stopwatch }
    enum Phase { case work, rest }

    @Published var mode: Mode = .countdown { didSet { if mode != oldValue { reset() } } }
    @Published var countdownSeconds = TimerModel.stored("countdownSeconds", 5 * 60) {
        didSet { UserDefaults.standard.set(countdownSeconds, forKey: "countdownSeconds") }
    }
    @Published var workMinutes = TimerModel.stored("pomodoroWorkMinutes", 25) {
        didSet { UserDefaults.standard.set(workMinutes, forKey: "pomodoroWorkMinutes") }
    }
    @Published var restMinutes = TimerModel.stored("pomodoroRestMinutes", 5) {
        didSet { UserDefaults.standard.set(restMinutes, forKey: "pomodoroRestMinutes") }
    }
    @Published private(set) var phase: Phase = .work
    @Published private(set) var completedPomodoros = 0
    /// Countdown and Pomodoro: when the current run ends. Stopwatch: when it was (re)started.
    @Published private(set) var anchor: Date?
    /// Time left (countdown) or elapsed (stopwatch) while paused.
    @Published private(set) var pausedValue: TimeInterval?

    private static func stored(_ key: String, _ fallback: Int) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : fallback
    }

    var onFinished: ((String) -> Void)?
    private var ticker: Timer?

    var isRunning: Bool { anchor != nil }
    var isActive: Bool { anchor != nil || pausedValue != nil }

    /// Seconds left for countdown modes, seconds elapsed for the stopwatch.
    func value(at date: Date = .now) -> TimeInterval {
        switch mode {
        case .stopwatch:
            if let anchor { return (pausedValue ?? 0) + date.timeIntervalSince(anchor) }
            return pausedValue ?? 0
        case .countdown, .pomodoro:
            if let anchor { return max(0, anchor.timeIntervalSince(date)) }
            return pausedValue ?? fullLength
        }
    }

    var fullLength: TimeInterval {
        switch mode {
        case .countdown: return TimeInterval(countdownSeconds)
        case .pomodoro: return TimeInterval((phase == .work ? workMinutes : restMinutes) * 60)
        case .stopwatch: return 0
        }
    }

    func start() {
        guard anchor == nil else { return }
        switch mode {
        case .stopwatch:
            anchor = .now
        case .countdown, .pomodoro:
            anchor = Date().addingTimeInterval(pausedValue ?? fullLength)
            pausedValue = nil
        }
        startTicking()
    }

    func pause() {
        guard anchor != nil else { return }
        pausedValue = value()
        anchor = nil
        ticker?.invalidate()
    }

    func reset() {
        anchor = nil
        pausedValue = nil
        phase = .work
        ticker?.invalidate()
    }

    /// The length can be changed only while nothing is running or paused.
    var canEditLength: Bool { mode != .stopwatch && !isActive }

    /// Picks which Pomodoro phase to edit and start from.
    func selectPhase(_ phase: Phase) {
        guard mode == .pomodoro, !isActive else { return }
        self.phase = phase
    }

    func adjustLength(byMinutes delta: Int) {
        guard canEditLength else { return }
        switch mode {
        case .countdown:
            // Steps snap to whole minutes, so 1:30 goes to 2:00 or 1:00.
            let minutes = (delta > 0 ? countdownSeconds / 60 : (countdownSeconds + 59) / 60) + delta
            countdownSeconds = min(Self.maxCountdown, max(60, minutes * 60))
        case .pomodoro:
            if phase == .work { workMinutes = min(180, max(1, workMinutes + delta)) }
            else { restMinutes = min(60, max(1, restMinutes + delta)) }
        case .stopwatch:
            break
        }
    }

    /// Sets the length from typed text: "90" is 90 minutes, "1:30" is 1 min 30 s, "1:00:00" is an hour.
    /// Pomodoro lengths are rounded to whole minutes. Returns false if the text isn't a length.
    @discardableResult
    func setLength(from text: String) -> Bool {
        guard canEditLength, let seconds = Self.parseLength(text), seconds > 0 else { return false }
        switch mode {
        case .countdown:
            countdownSeconds = min(Self.maxCountdown, seconds)
        case .pomodoro:
            let minutes = max(1, Int((Double(seconds) / 60).rounded()))
            if phase == .work { workMinutes = min(180, minutes) } else { restMinutes = min(60, minutes) }
        case .stopwatch:
            return false
        }
        return true
    }

    static let maxCountdown = 24 * 3600

    nonisolated static func parseLength(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let n = numbers.map { $0! }
        switch n.count {
        case 1: return n[0] * 60
        case 2: return n[1] < 60 ? n[0] * 60 + n[1] : nil
        default: return n[1] < 60 && n[2] < 60 ? n[0] * 3600 + n[1] * 60 + n[2] : nil
        }
    }

    private func startTicking() {
        ticker?.invalidate()
        guard mode != .stopwatch else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let anchor, anchor <= .now else { return }
        NSSound(named: "Glass")?.play()
        switch mode {
        case .countdown:
            reset()
            onFinished?(String(localized: "Timer finished"))
        case .pomodoro:
            if phase == .work { completedPomodoros += 1 }
            let finishedWork = phase == .work
            phase = finishedWork ? .rest : .work
            self.anchor = Date().addingTimeInterval(fullLength)
            onFinished?(finishedWork ? String(localized: "Time for a break") : String(localized: "Back to work"))
        case .stopwatch:
            break
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct TimerTab: View {
    @ObservedObject var timer: TimerModel

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $timer.mode) {
                    Text("Timer").tag(TimerModel.Mode.countdown)
                    Text("Pomodoro").tag(TimerModel.Mode.pomodoro)
                    Text("Stopwatch").tag(TimerModel.Mode.stopwatch)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)

                switch timer.mode {
                case .countdown:
                    HStack(spacing: 6) {
                        ForEach([1, 3, 5, 10, 15, 25, 45], id: \.self) { minutes in
                            Button("\(minutes)") {
                                timer.reset()
                                timer.countdownSeconds = minutes * 60
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .frame(width: 30, height: 22)
                            .background(Capsule().fill(.white.opacity(timer.countdownSeconds == minutes * 60 ? 0.22 : 0.08)))
                        }
                        Text("min").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize()
                    }
                    .disabled(timer.isRunning)
                    Text("Scroll or click the time to change it")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                case .pomodoro:
                    HStack(spacing: 6) {
                        PhaseChip(title: String(localized: "Focus · \(timer.workMinutes) min"), tint: .orange,
                                  selected: timer.phase == .work) { timer.selectPhase(.work) }
                        PhaseChip(title: String(localized: "Break · \(timer.restMinutes) min"), tint: .green,
                                  selected: timer.phase == .rest) { timer.selectPhase(.rest) }
                    }
                    .disabled(timer.isActive)
                    Text("Completed today: \(timer.completedPomodoros)")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                case .stopwatch:
                    Text("Counts up until you stop it")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            TimeDisplay(timer: timer)
            VStack(spacing: 10) {
                RoundButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", prominent: true) {
                    timer.isRunning ? timer.pause() : timer.start()
                }
                RoundButton(symbol: "arrow.counterclockwise", prominent: false) { timer.reset() }
                    .disabled(!timer.isActive)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RoundButton: View {
    let symbol: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 16 : 13, weight: .semibold))
                .frame(width: prominent ? 44 : 34, height: prominent ? 44 : 34)
                .background(Circle().fill(.white.opacity(prominent ? 0.2 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PhaseChip: View {
    let title: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(selected ? tint : .white.opacity(0.6))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(selected ? tint.opacity(0.18) : .white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

/// The big time. While nothing runs it is also the control: scroll or use the arrows to change it a minute
/// at a time (five with Shift), or click it to type a length.
private struct TimeDisplay: View {
    @ObservedObject var timer: TimerModel
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let editable = timer.canEditLength
        VStack(spacing: 0) {
            arrow("chevron.up", delta: 1).opacity(editable && !editing ? 1 : 0)
            ZStack {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Text(TimerModel.format(timer.value(at: context.date)))
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .opacity(editing ? 0 : 1)
                }
                if editing {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { editing = false }
                        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                }
            }
            .overlay {
                if editable && !editing {
                    ScrollCatcher(onStep: { timer.adjustLength(byMinutes: $0) }, onClick: startEditing)
                }
            }
            .help(editable ? String(localized: "Scroll or click the time to change it") : "")
            arrow("chevron.down", delta: -1).opacity(editable && !editing ? 1 : 0)
        }
        .onChange(of: editable) { _, isEditable in if !isEditable { editing = false } }
    }

    private func startEditing() {
        text = TimerModel.format(timer.value())
        editing = true
        focused = true
    }

    private func arrow(_ symbol: String, delta: Int) -> some View {
        Button {
            timer.adjustLength(byMinutes: NSEvent.modifierFlags.contains(.shift) ? delta * 5 : delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 44, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!timer.canEditLength)
    }

    private func commit() {
        guard editing else { return }
        timer.setLength(from: text)
        editing = false
    }
}

/// Set while the pointer is over the timer's time, so notch swipes leave that scrolling alone.
@MainActor
enum TimeScrollTarget {
    static var isHovered = false
}

/// Turns scroll-wheel and trackpad scrolling over a view into whole steps: up is +1, down is -1, Shift makes it 5.
private struct ScrollCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void
    let onClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onStep = onStep
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onStep = onStep
        view.onClick = onClick
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        TimeScrollTarget.isHovered = false
    }

    final class CatcherView: NSView {
        var onStep: ((Int) -> Void)?
        var onClick: (() -> Void)?
        private var accumulated: CGFloat = 0

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { TimeScrollTarget.isHovered = true }
        override func mouseExited(with event: NSEvent) { TimeScrollTarget.isHovered = false }
        override func mouseDown(with event: NSEvent) { onClick?() }

        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            // Shift turns a mouse wheel into horizontal scrolling, so take whichever axis moved.
            var delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            // Positive means the wheel or fingers moved up, whatever the natural scrolling setting.
            if event.isDirectionInvertedFromDevice { delta = -delta }
            // Trackpads report many small precise deltas; a mouse wheel reports whole lines.
            accumulated += event.hasPreciseScrollingDeltas ? delta / 12 : delta
            let steps = Int(accumulated)
            guard steps != 0 else { return }
            accumulated -= CGFloat(steps)
            onStep?(event.modifierFlags.contains(.shift) ? steps * 5 : steps)
        }
    }
}
