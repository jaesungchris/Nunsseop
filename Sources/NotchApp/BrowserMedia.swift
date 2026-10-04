import AppKit

/// Reads media playing in browser tabs through each browser's AppleScript
/// JavaScript bridge. Requires Automation consent and, per browser, the
/// "Allow JavaScript from Apple Events" developer setting.
struct BrowserMedia {
    enum Dialect { case chromium, safari }

    let bundleID: String
    let dialect: Dialect

    static let all: [BrowserMedia] = [
        BrowserMedia(bundleID: "com.apple.Safari", dialect: .safari),
        BrowserMedia(bundleID: "com.google.Chrome", dialect: .chromium),
        BrowserMedia(bundleID: "com.microsoft.edgemac", dialect: .chromium),
        BrowserMedia(bundleID: "com.brave.Browser", dialect: .chromium),
        BrowserMedia(bundleID: "company.thebrowser.Browser", dialect: .chromium),
        BrowserMedia(bundleID: "company.thebrowser.dia", dialect: .chromium),
        BrowserMedia(bundleID: "com.naver.Whale", dialect: .chromium),
        BrowserMedia(bundleID: "com.vivaldi.Vivaldi", dialect: .chromium),
        BrowserMedia(bundleID: "com.operasoftware.Opera", dialect: .chromium),
    ]

    struct Location: Equatable {
        let window: Int
        let tab: Int
    }

    struct Hit {
        let track: NowPlayingTrack
        let artworkURL: URL?
        let location: Location
    }

    enum Failure: Error {
        case notAuthorized
        case javaScriptDisabled
        case other
    }

    /// Tabs on these hosts are probed; probing every tab on each poll would be too slow.
    private static let mediaHosts = [
        "music.youtube.com", "youtube.com", "youtu.be", "open.spotify.com", "soundcloud.com",
        "music.apple.com", "tidal.com", "deezer.com", "bandcamp.com", "twitch.tv", "vimeo.com",
        "netflix.com", "music.amazon.com","pandora.com", "vibe.naver.com", "melon.com",
        "genie.co.kr", "music-flo.com", "music.bugs.co.kr", "chzzk.naver.com", "laftel.net",
    ]

    // JavaScript sources use single quotes only so they can sit inside an AppleScript string.
    private static let stateJS = """
    (() => { const els = [...document.querySelectorAll('video,audio')]; \
    const m = els.find(e => !e.paused) || els.find(e => e.currentTime > 0); \
    const md = navigator.mediaSession && navigator.mediaSession.metadata; \
    if (!m && !md) return ''; \
    const art = md && md.artwork && md.artwork.length ? md.artwork[md.artwork.length - 1].src : ''; \
    return JSON.stringify({ title: md && md.title ? md.title : document.title, \
    artist: md ? md.artist : '', album: md ? md.album : '', art: art, \
    playing: m ? !m.paused : navigator.mediaSession.playbackState === 'playing', \
    pos: m ? m.currentTime : 0, dur: m && isFinite(m.duration) ? m.duration : 0 }); })()
    """

    private static func clickJS(_ selectors: [String], fallback: String) -> String {
        let list = selectors.map { "'\($0)'" }.joined(separator: ",")
        return """
        (() => { for (const q of [\(list)]) { const b = document.querySelector(q); \
        if (b) { b.click(); return; } } \(fallback) })()
        """
    }

    private static func commandJS(_ command: NowPlayingCommand) -> String {
        let media = "const els = [...document.querySelectorAll('video,audio')]; " +
            "const m = els.find(e => !e.paused) || els.find(e => e.currentTime > 0);"
        switch command {
        case .playPause:
            return clickJS(["ytmusic-player-bar #play-pause-button",
                            "[data-testid=control-button-playpause]",
                            ".playControls .playControl"],
                           fallback: "\(media) if (m) { m.paused ? m.play() : m.pause(); }")
        case .next:
            return clickJS(["ytmusic-player-bar .next-button", ".ytp-next-button",
                            "[data-testid=control-button-skip-forward]", ".skipControl__next"],
                           fallback: "\(media) if (m && isFinite(m.duration)) { m.currentTime = Math.min(m.duration, m.currentTime + 10); }")
        case .previous:
            return clickJS(["ytmusic-player-bar .previous-button", ".ytp-prev-button",
                            "[data-testid=control-button-skip-back]", ".skipControl__previous"],
                           fallback: "\(media) if (m) { m.currentTime = Math.max(0, m.currentTime - 10); }")
        }
    }

    private func execute(_ js: String, window: String, tab: String) -> String {
        switch dialect {
        case .chromium:
            return "execute tab \(tab) of window \(window) javascript \"\(js)\""
        case .safari:
            return "do JavaScript \"\(js)\" in tab \(tab) of window \(window)"
        }
    }

    private var tabURLsScript: String {
        """
        tell application id "\(bundleID)"
            set out to {}
            repeat with w from 1 to count of windows
                set end of out to URL of every tab of window w
            end repeat
            return out
        end tell
        """
    }

    static func isMediaSite(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return mediaHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func run(_ source: String) -> Result<NSAppleEventDescriptor, Failure> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.other) }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? ""
            if code == -1743 { return .failure(.notAuthorized) }
            if message.localizedCaseInsensitiveContains("javascript") { return .failure(.javaScriptDisabled) }
            return .failure(.other)
        }
        return .success(result)
    }

    func scan() -> Result<Hit?, Failure> {
        let windows: NSAppleEventDescriptor
        switch Self.run(tabURLsScript) {
        case .success(let d): windows = d
        case .failure(let f): return .failure(f)
        }
        var locations: [Location] = []
        for w in 0..<max(0, windows.numberOfItems) {
            guard let tabs = windows.atIndex(w + 1) else { continue }
            for t in 0..<max(0, tabs.numberOfItems) {
                if let url = tabs.atIndex(t + 1)?.stringValue, Self.isMediaSite(url) {
                    locations.append(Location(window: w + 1, tab: t + 1))
                }
            }
        }
        for location in locations {
            let source = """
            tell application id "\(bundleID)"
                return \(execute(Self.stateJS, window: "\(location.window)", tab: "\(location.tab)"))
            end tell
            """
            switch Self.run(source) {
            case .success(let d):
                if let hit = makeHit(d.stringValue, location: location) { return .success(hit) }
            case .failure(let f):
                return .failure(f)
            }
        }
        return .success(nil)
    }

    private func makeHit(_ jsonString: String?, location: Location) -> Hit? {
        guard let json = jsonString?.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }

        let track = NowPlayingTrack(
            title: info["title"] as? String ?? "",
            artist: info["artist"] as? String ?? "",
            album: info["album"] as? String ?? "",
            duration: info["dur"] as? Double ?? 0,
            position: info["pos"] as? Double ?? 0,
            isPlaying: info["playing"] as? Bool ?? false,
            sourceBundleID: bundleID,
            fetchedAt: Date()
        )
        let artworkURL = (info["art"] as? String).flatMap(URL.init(string:))
        return Hit(track: track, artworkURL: artworkURL, location: location)
    }

    func send(_ command: NowPlayingCommand, at location: Location) {
        let source = """
        tell application id "\(bundleID)"
            \(execute(Self.commandJS(command), window: "\(location.window)", tab: "\(location.tab)"))
        end tell
        """
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
    }
}
