import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct AIWindowTests {
    private let later = Date().addingTimeInterval(3600)

    private func claude(session: AIUsageModel.Window?, weekly: AIUsageModel.Window?) -> [AIUsageModel.Provider] {
        [AIUsageModel.Provider(id: "claude", name: "Claude Code", session: session, weekly: weekly)]
    }

    @Test func tighterPicksTheMostUsedWindow() {
        let providers = claude(session: .init(percent: 30, resetsAt: later), weekly: .init(percent: 70, resetsAt: later))
        #expect(NotchViewModel.aiLeft(.claude, in: providers, window: .tighter) == 30)
        #expect(NotchViewModel.aiLeft(.claude, in: providers, window: .session) == 70)
        #expect(NotchViewModel.aiLeft(.claude, in: providers, window: .weekly) == 30)
    }

    @Test func chosenWindowThatResetShowsNothing() {
        // A window whose reset time passed has no known usage, so it isn't shown, and the other one isn't swapped in.
        let providers = claude(session: .init(percent: 0, resetsAt: nil), weekly: .init(percent: 3, resetsAt: later))
        #expect(NotchViewModel.aiLeft(.claude, in: providers, window: .session) == nil)
        #expect(NotchViewModel.aiLeft(.claude, in: providers, window: .weekly) == 97)
        #expect(NotchViewModel.aiLeft(.claude, in: providers, window: .tighter) == 97)
    }

    @Test func missingProviderOrWindowShowsNothing() {
        #expect(NotchViewModel.aiLeft(.codex, in: claude(session: .init(percent: 10, resetsAt: later), weekly: nil)) == nil)
        #expect(NotchViewModel.aiLeft(.claude, in: claude(session: nil, weekly: nil), window: .weekly) == nil)
    }

    @Test func leftNeverGoesNegative() {
        let providers = claude(session: .init(percent: 120, resetsAt: later), weekly: nil)
        #expect(NotchViewModel.aiLeft(.claude, in: providers, window: .session) == 0)
    }
}
