import Testing
@testable import Nunsseop

struct LyricsParseTests {
    @Test func parsesAndSortsTimedLines() {
        let lrc = """
        [ar:Some Artist]
        [00:01.50] Hello
        [00:00.00]Start
        [01:00.00][02:00.00] Chorus
        no timestamp here
        [00:05.00]
        """
        #expect(LyricsModel.parse(lrc) == [
            .init(time: 0, text: "Start"),
            .init(time: 1.5, text: "Hello"),
            .init(time: 5, text: ""),
            .init(time: 60, text: "Chorus"),
            .init(time: 120, text: "Chorus"),
        ])
    }

    @Test func emptyInputHasNoLines() {
        #expect(LyricsModel.parse("").isEmpty)
        #expect(LyricsModel.parse("plain text\nwithout times").isEmpty)
    }
}
