import Testing
@testable import Nunsseop

struct TimerParseTests {
    @Test(arguments: [
        ("90", 5400), ("1:30", 90), ("1:00:00", 3600), ("0", 0), (" 25 ", 1500), ("0:59", 59), ("2:05:09", 7509),
    ])
    func parsesLengths(text: String, seconds: Int) {
        #expect(TimerModel.parseLength(text) == seconds)
    }

    @Test(arguments: ["", "-3", "1:75", "1:60:00", "abc", "1:2:3:4", "1:", ":30", "1.5"])
    func rejectsNonLengths(text: String) {
        #expect(TimerModel.parseLength(text) == nil)
    }

    @Test(arguments: ["999999999999999999", "9223372036854775807", "1:999999999999999999",
                      "999999999999999999:00:00", "1234567"])
    func rejectsOversizedComponentsWithoutCrashing(text: String) {
        #expect(TimerModel.parseLength(text) == nil)
    }

    @Test func acceptsLargeButSafeComponents() {
        #expect(TimerModel.parseLength("999999:59:59") == 999_999 * 3600 + 59 * 60 + 59)
    }
}
