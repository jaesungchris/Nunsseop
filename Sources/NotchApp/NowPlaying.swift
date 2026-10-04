import AppKit
import Combine

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var sourceBundleID: String
    var fetchedAt: Date

    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(fetchedAt))
    }

    var identity: String { "\(sourceBundleID)|\(title)|\(artist)|\(album)" }
}

enum NowPlayingCommand {
    case playPause, next, previous
}

/// Reads playback state from apps that expose it over AppleScript. Each source
/// needs the user's Automation consent the first time it is queried.
private struct ScriptSource {
    let bundleID: String
    let durationScale: Double
    let stateScript: String
    let artworkScript: String
    let artworkIsURL: Bool

    func command(_ command: NowPlayingCommand) -> String {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        return "tell application id \"\(bundleID)\" to \(verb)"
    }

    static let music = ScriptSource(
        bundleID: "com.apple.Music",
        durationScale: 1,
        stateScript: """
        tell application id "com.apple.Music"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """,
        artworkScript: """
        tell application id "com.apple.Music" to return data of artwork 1 of current track
        """,
        artworkIsURL: false
    )

    static let spotify = ScriptSource(
        bundleID: "com.spotify.client",
        durationScale: 1.0 / 1000,
        stateScript: """
        tell application id "com.spotify.client"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """,
        artworkScript: """
        tell application id "com.spotify.client" to return artwork url of current track
        """,
        artworkIsURL: true
    )
}

@MainActor
final class NowPlayingController: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var needsAutomationPermission = false

    private let sources: [ScriptSource] = [.music, .spotify]
    private let queue = DispatchQueue(label: "notchapp.nowplaying")
    private var timer: Timer?
    private var artworkIdentity: String?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func send(_ command: NowPlayingCommand) {
        guard let bundleID = track?.sourceBundleID,
              let source = sources.first(where: { $0.bundleID == bundleID }) else { return }
        let script = source.command(command)
        queue.async { [weak self] in
            _ = Self.run(script)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.poll()
            }
        }
    }

    private func poll() {
        let running = sources.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }
        queue.async { [weak self] in
            var candidates: [NowPlayingTrack] = []
            var denied = false
            for source in running {
                switch Self.run(source.stateScript) {
                case .success(let result):
                    if let track = Self.parse(result, source: source) { candidates.append(track) }
                case .failure(let error):
                    if error.code == -1743 { denied = true }
                }
            }
            let best = candidates.first(where: \.isPlaying) ?? candidates.first
            DispatchQueue.main.async {
                self?.apply(best, denied: denied)
            }
        }
    }

    private func apply(_ newTrack: NowPlayingTrack?, denied: Bool) {
        needsAutomationPermission = denied && newTrack == nil
        if track != newTrack { track = newTrack }
        guard let newTrack else {
            artwork = nil
            artworkIdentity = nil
            return
        }
        if newTrack.identity != artworkIdentity {
            artworkIdentity = newTrack.identity
            artwork = nil
            loadArtwork(for: newTrack)
        }
    }

    private func loadArtwork(for track: NowPlayingTrack) {
        guard let source = sources.first(where: { $0.bundleID == track.sourceBundleID }) else { return }
        let identity = track.identity
        queue.async { [weak self] in
            guard case .success(let result) = Self.run(source.artworkScript) else { return }
            if source.artworkIsURL {
                guard let string = result.stringValue, let url = URL(string: string) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self?.setArtwork(image, for: identity) }
                }.resume()
            } else if let image = NSImage(data: result.data) {
                DispatchQueue.main.async { self?.setArtwork(image, for: identity) }
            }
        }
    }

    private func setArtwork(_ image: NSImage, for identity: String) {
        if identity == artworkIdentity { artwork = image }
    }

    private struct ScriptError: Error { let code: Int }

    nonisolated private static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(ScriptError(code: 0)) }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return .failure(ScriptError(code: errorInfo[NSAppleScript.errorNumber] as? Int ?? 0))
        }
        return .success(result)
    }

    nonisolated private static func parse(_ d: NSAppleEventDescriptor, source: ScriptSource) -> NowPlayingTrack? {
        guard d.numberOfItems >= 6, let state = d.atIndex(1)?.stringValue, state != "stopped" else { return nil }
        return NowPlayingTrack(
            title: d.atIndex(2)?.stringValue ?? "",
            artist: d.atIndex(3)?.stringValue ?? "",
            album: d.atIndex(4)?.stringValue ?? "",
            duration: (d.atIndex(5)?.doubleValue ?? 0) * source.durationScale,
            position: d.atIndex(6)?.doubleValue ?? 0,
            isPlaying: state == "playing",
            sourceBundleID: source.bundleID,
            fetchedAt: Date()
        )
    }
}
