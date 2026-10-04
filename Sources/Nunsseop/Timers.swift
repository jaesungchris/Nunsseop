import AppKit
import SwiftUI

/// Countdown, Pomodoro and stopwatch. Only one runs at a time.
@MainActor
final class TimerModel: ObservableObject {
    enum Mode: String, CaseIterable { case countdown, pomodoro, stopwatch }
    enum Phase { case work, rest }

    @Published var mode: Mode = .countdown { didSet { if mode != oldValue { reset() } } }
    @Published var countdownMinutes = 5
    @Published private(set) var phase: Phase = .work
    @Published private(set) var completedPomodoros = 0
    /// Countdown and Pomodoro: when the current run ends. Stopwatch: when it was (re)started.
    @Published private(set) var anchor: Date?
    /// Time left (countdown) or elapsed (stopwatch) while paused.
    @Published private(set) var pausedValue: TimeInterval?

    static let workMinutes = 25
    static let restMinutes = 5

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
        case .countdown: return TimeInterval(countdownMinutes * 60)
        case .pomodoro: return TimeInterval((phase == .work ? Self.workMinutes : Self.restMinutes) * 60)
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
                                timer.countdownMinutes = minutes
                                timer.reset()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .frame(width: 30, height: 22)
                            .background(Capsule().fill(.white.opacity(timer.countdownMinutes == minutes ? 0.22 : 0.08)))
                        }
                        Text("min").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                    .disabled(timer.isRunning)
                case .pomodoro:
                    Text(timer.phase == .work ? String(localized: "Focus · \(TimerModel.workMinutes) min")
                                              : String(localized: "Break · \(TimerModel.restMinutes) min"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(timer.phase == .work ? .orange : .green)
                    Text("Completed today: \(timer.completedPomodoros)")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                case .stopwatch:
                    Text("Counts up until you stop it")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                Text(TimerModel.format(timer.value(at: context.date)))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
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
