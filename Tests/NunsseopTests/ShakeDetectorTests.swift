import CoreGraphics
import Foundation
import Testing
@testable import Nunsseop

struct ShakeDetectorTests {
    /// Feeds (x, time) samples and returns the indices where a shake fired.
    private func fire(_ samples: [(CGFloat, TimeInterval)], _ detector: inout ShakeDetector) -> [Int] {
        samples.enumerated().compactMap { index, sample in detector.add(x: sample.0, at: sample.1) ? index : nil }
    }

    private func fire(_ samples: [(CGFloat, TimeInterval)]) -> [Int] {
        var detector = ShakeDetector()
        return fire(samples, &detector)
    }

    @Test func quickShakeFires() {
        // Right, left, right, left in 80 pt strokes, 0.1 s apart: the third reversal fires.
        let samples: [(CGFloat, TimeInterval)] = [(0, 0), (80, 0.1), (0, 0.2), (80, 0.3), (0, 0.4)]
        #expect(fire(samples) == [4])
    }

    @Test func fineGrainedShakeFires() {
        // Many small steps per stroke, as real drag events arrive.
        var samples: [(CGFloat, TimeInterval)] = []
        var time: TimeInterval = 0
        for stroke in 0..<4 {
            for step in 0...8 {
                let x = CGFloat(step) * 10
                samples.append((stroke.isMultiple(of: 2) ? x : 80 - x, time))
                time += 0.015
            }
        }
        #expect(fire(samples).count == 1)
    }

    @Test func steadyDragDoesNotFire() {
        let samples = (0..<100).map { (CGFloat($0) * 10, TimeInterval($0) * 0.01) }
        #expect(fire(samples).isEmpty)
    }

    @Test func smallJitterDoesNotFire() {
        // Back and forth by 30 pt is under the 40 pt stroke.
        let samples = (0..<20).map { (CGFloat($0 % 2) * 30, TimeInterval($0) * 0.05) }
        #expect(fire(samples).isEmpty)
    }

    @Test func slowWaveDoesNotFire() {
        // Same strokes, but 0.4 s apart, so three reversals never fit in 0.6 s.
        let samples: [(CGFloat, TimeInterval)] = [(0, 0), (80, 0.4), (0, 0.8), (80, 1.2), (0, 1.6), (80, 2.0)]
        #expect(fire(samples).isEmpty)
    }

    @Test func twoReversalsDoNotFire() {
        let samples: [(CGFloat, TimeInterval)] = [(0, 0), (80, 0.1), (0, 0.2), (80, 0.3)]
        #expect(fire(samples).isEmpty)
    }

    @Test func firesOnceThenNeedsANewShake() {
        var detector = ShakeDetector()
        let shake: [(CGFloat, TimeInterval)] = [(0, 0), (80, 0.1), (0, 0.2), (80, 0.3), (0, 0.4)]
        #expect(fire(shake, &detector) == [4])
        // One more swing right after is not a second shake.
        #expect(fire([(80, 0.5), (0, 0.6)], &detector).isEmpty)
    }

    @Test func resetForgetsProgress() {
        var detector = ShakeDetector()
        _ = fire([(0, 0), (80, 0.1), (0, 0.2), (80, 0.3)], &detector)
        detector.reset()
        #expect(fire([(0, 0.4)], &detector).isEmpty)
    }
}
