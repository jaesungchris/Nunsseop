import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct AgentBoardTests {
    @Test func countsAcrossSources() {
        let board = AgentBoard()
        #expect(board.counts.isEmpty)
        board.replace(source: "herdr:a", with: ["p1": .working, "p2": .waiting])
        board.replace(source: "herdr:b", with: ["p1": .working])
        #expect(board.counts == AgentBoard.Counts(working: 2, waiting: 1))
        // A source's new list replaces its old one; others stay.
        board.replace(source: "herdr:a", with: ["p2": .working])
        #expect(board.counts == AgentBoard.Counts(working: 2, waiting: 0))
        board.clear(source: "herdr:b")
        #expect(board.counts == AgentBoard.Counts(working: 1, waiting: 0))
        board.clear(source: "herdr:a")
        #expect(board.counts.isEmpty)
    }

    @Test func herdrStatesAsTheBoardCountsThem() {
        #expect(Herdr.boardState("working") == .working)
        #expect(Herdr.boardState("blocked") == .waiting)
        #expect(Herdr.boardState("done") == .waiting)
        #expect(Herdr.boardState("idle") == nil)
        #expect(Herdr.boardState("unknown") == nil)
        #expect(Herdr.boardStates(["a": "working", "b": "idle", "c": "blocked"]) == ["a": .working, "c": .waiting])
    }

    @Test func closedNotchShowsWaitingFirst() {
        #expect(NotchViewModel.agentsValue(AgentBoard.Counts()) == nil)
        let working = NotchViewModel.agentsValue(AgentBoard.Counts(working: 3))
        #expect(working?.text == "3" && working?.symbol == "bolt.fill")
        let waiting = NotchViewModel.agentsValue(AgentBoard.Counts(working: 3, waiting: 1))
        #expect(waiting?.text == "1" && waiting?.symbol == "hand.raised.fill")
    }
}
