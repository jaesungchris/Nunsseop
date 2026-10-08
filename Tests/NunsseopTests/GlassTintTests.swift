import SwiftUI
import Testing
@testable import Nunsseop

@Suite struct GlassTintTests {
    @Test func tintGoesUpToFullyOpaque() {
        #expect(AppSettings.glassTintRange.upperBound == 100)
    }

    @Test func fullTintIsSolidBlack() {
        typealias Background = NotchBackground<Rectangle>
        #expect(Background.showsGlass(glass: true, tint: 0.99, expanded: true, floatingPill: false))
        // What the slider shows as "100 %" is solid, even a hair short of the end.
        #expect(!Background.showsGlass(glass: true, tint: 0.996, expanded: true, floatingPill: false))
        #expect(Background.showsGlass(glass: true, tint: 0.994, expanded: true, floatingPill: false))
        #expect(!Background.showsGlass(glass: true, tint: 1, expanded: true, floatingPill: false))
        #expect(!Background.showsGlass(glass: true, tint: 1, expanded: false, floatingPill: true))
        #expect(Background.showsGlass(glass: true, tint: 0.55, expanded: false, floatingPill: true))
        #expect(!Background.showsGlass(glass: false, tint: 0.55, expanded: true, floatingPill: false))
        #expect(!Background.showsGlass(glass: true, tint: 0.55, expanded: false, floatingPill: false))
    }
}
