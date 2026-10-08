import SwiftUI

/// What coding agents are doing right now, gathered from every source that can tell (herdr first; Muxy, cmux and
/// hooks to follow), so the closed notch can say how many are working and how many wait for you. A live count is
/// something only the notch can show at a glance; Notification Center keeps what happened, not what's happening.
@MainActor
final class AgentBoard: ObservableObject {
    enum State: Equatable {
        /// Running a turn.
        case working
        /// Asking for input, or finished and not yet looked at.
        case waiting
    }

    struct Counts: Equatable {
        var working = 0
        var waiting = 0
        var isEmpty: Bool { working == 0 && waiting == 0 }

        init(working: Int = 0, waiting: Int = 0) {
            self.working = working
            self.waiting = waiting
        }

        init<S: Sequence>(_ states: S) where S.Element == State {
            for state in states {
                switch state {
                case .working: working += 1
                case .waiting: waiting += 1
                }
            }
        }
    }

    /// An agent's state, and when it stops counting (a finished one that nobody looked at, say).
    struct Agent: Equatable {
        var state: State
        var expiresAt: Date? = nil
    }

    /// Each source's agents by their id there (a herdr pane, say). A source replaces its whole list at once.
    private var bySource: [String: [String: Agent]] = [:]
    @Published private(set) var counts = Counts()
    private var expiry: Timer?

    init() {
        #if DEBUG
        // Debug: --demo-agents shows two working and one waiting, for checking the closed notch.
        if CommandLine.arguments.contains("--demo-agents") {
            replace(source: "demo", with: ["a": .working, "b": .working, "c": .waiting])
        }
        #endif
    }

    /// Everything one source knows now; agents it no longer lists are gone.
    func replace(source: String, with agents: [String: Agent], now: Date = .now) {
        bySource[source] = agents.isEmpty ? nil : agents
        recount(now: now)
    }

    func replace(source: String, with states: [String: State]) {
        replace(source: source, with: states.mapValues { Agent(state: $0) })
    }

    func clear(source: String) { replace(source: source, with: [String: Agent]()) }

    /// Counts the agents that haven't expired, and wakes up when the next one does.
    func recount(now: Date = .now) {
        let live = bySource.values.flatMap(\.values).filter { $0.expiresAt.map { $0 > now } ?? true }
        let new = Counts(live.map(\.state))
        if new != counts { counts = new }
        expiry?.invalidate()
        expiry = nil
        guard let next = live.compactMap(\.expiresAt).min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.recount() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }
}

extension Herdr {
    /// How long a finished pane nobody looked at in herdr keeps counting as waiting; past it the hand goes away even
    /// for someone who never opens herdr.
    static let doneWindow: TimeInterval = 10 * 60

    /// A pane's state and since when it has been in it.
    struct PaneState: Equatable {
        let status: String
        let since: Date
    }

    /// The board's agents for a session's panes; `done` ones expire `doneWindow` after they finished.
    static func boardAgents(_ panes: [String: PaneState]) -> [String: AgentBoard.Agent] {
        panes.compactMapValues { pane in
            boardState(pane.status).map { state in
                AgentBoard.Agent(state: state, expiresAt: pane.status == "done" ? pane.since.addingTimeInterval(doneWindow) : nil)
            }
        }
    }

    /// herdr's pane states as the board counts them. `done` is finished but not yet seen in herdr, so it waits for
    /// the user like `blocked` (for a while: see `doneWindow`); idle and unknown panes aren't agents at work.
    static func boardState(_ status: String) -> AgentBoard.State? {
        switch status {
        case "working": .working
        case "blocked", "done": .waiting
        default: nil
        }
    }

    static func boardStates(_ panes: [String: String]) -> [String: AgentBoard.State] {
        panes.compactMapValues(boardState)
    }
}
