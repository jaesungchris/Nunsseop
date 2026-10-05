import Foundation
import Testing
@testable import Nunsseop

struct TimerLengthLabelTests {
    @Test(arguments: [
        (300, "5 min"), (1500, "25 min"), (5400, "1 hr 30 min"), (90, "1 min 30 sec"), (3600, "1 hr"),
        (3661, "1 hr 1 min 1 sec"), (45, "45 sec"), (0, "0 min"),
    ])
    func english(seconds: Int, label: String) {
        #expect(TimerModel.lengthLabel(seconds, locale: Locale(identifier: "en_US")) == label)
    }

    @Test(arguments: [(1500, "25분"), (5400, "1시간 30분"), (90, "1분 30초"), (86400, "24시간")])
    func korean(seconds: Int, label: String) {
        #expect(TimerModel.lengthLabel(seconds, locale: Locale(identifier: "ko_KR")) == label)
    }

    @Test func noListConnectors() {
        // French puts narrow no-break spaces inside each unit, so compare words rather than the exact string.
        #expect(!TimerModel.lengthLabel(5400, locale: Locale(identifier: "fr_FR")).contains("et"))
        #expect(!TimerModel.lengthLabel(90, locale: Locale(identifier: "es_ES")).contains(" y "))
        #expect(!TimerModel.lengthLabel(5400, locale: Locale(identifier: "de_DE")).contains(","))
    }
}
