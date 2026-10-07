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

    /// Each source's agents by their id there (a herdr pane, say). A source replaces its whole list at once.
    private var bySource: [String: [String: State]] = [:]
    @Published private(set) var counts = Counts()

    init() {
        #if DEBUG
        // Debug: --demo-agents shows two working and one waiting, for checking the closed notch.
        if CommandLine.arguments.contains("--demo-agents") {
            replace(source: "demo", with: ["a": .working, "b": .working, "c": .waiting])
        }
        #endif
    }

    /// Everything one source knows now; agents it no longer lists are gone.
    func replace(source: String, with agents: [String: State]) {
        bySource[source] = agents.isEmpty ? nil : agents
        let new = Counts(bySource.values.flatMap(\.values))
        if new != counts { counts = new }
    }

    func clear(source: String) { replace(source: source, with: [:]) }
}

extension Herdr {
    /// herdr's pane states as the board counts them. `done` is finished but not yet seen in herdr, so it waits for
    /// the user like `blocked`; idle and unknown panes aren't agents at work.
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
