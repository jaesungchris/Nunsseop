import Testing
@testable import Nunsseop

struct LinkCleanerTests {
    @Test func removesTrackingParameters() {
        #expect(LinkCleaner.clean("https://example.com/a?utm_source=x&id=3&fbclid=abc") == "https://example.com/a?id=3")
        #expect(LinkCleaner.clean("https://example.com/a?UTM_Medium=x&gclid=1&q=swift") == "https://example.com/a?q=swift")
    }

    @Test func dropsEmptyQuery() {
        #expect(LinkCleaner.clean("https://example.com/?fbclid=1&utm_campaign=y") == "https://example.com/")
    }

    @Test func stripsShareIDOnlyOnYouTubeAndSpotify() {
        #expect(LinkCleaner.clean("https://www.youtube.com/watch?v=abc&si=xyz") == "https://www.youtube.com/watch?v=abc")
        #expect(LinkCleaner.clean("https://youtu.be/abc?si=xyz") == "https://youtu.be/abc")
        #expect(LinkCleaner.clean("https://open.spotify.com/track/1?si=xyz") == "https://open.spotify.com/track/1")
        #expect(LinkCleaner.clean("https://example.com/page?si=1") == nil)
        #expect(LinkCleaner.clean("https://notyoutube.com/watch?si=1") == nil)
    }

    @Test func keepsFragment() {
        #expect(LinkCleaner.clean("https://example.com/p?utm_medium=a&x=1#section") == "https://example.com/p?x=1#section")
    }

    @Test func leavesOtherTextAlone() {
        #expect(LinkCleaner.clean("hello world") == nil)
        #expect(LinkCleaner.clean("") == nil)
        #expect(LinkCleaner.clean("ftp://example.com/?utm_source=a") == nil)
        #expect(LinkCleaner.clean("https://example.com/?utm_source=a and more") == nil)
        #expect(LinkCleaner.clean("https://example.com/?a=1") == nil)
        #expect(LinkCleaner.clean("https://example.com/") == nil)
    }
}
