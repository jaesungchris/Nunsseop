import AppKit
import Combine
import SwiftUI

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
    @Published private(set) var artwork: NSImage? {
        didSet { tint = artwork.map(ArtworkTint.color(for:)) ?? .white }
    }
    @Published private(set) var tint: Color = .white
    @Published private(set) var needsAutomationPermission = false
    /// Name of a browser that refused to run JavaScript from Apple Events.
    @Published private(set) var browserNeedingJavaScript: String?

    private let sources: [ScriptSource] = [.music, .spotify]
    private let queue = DispatchQueue(label: "notchapp.nowplaying")
    private var timer: Timer?
    private var artworkIdentity: String?
    private var browserHit: BrowserMedia.Hit?

    private struct PollResult {
        var candidates: [NowPlayingTrack] = []
        var browserHits: [String: BrowserMedia.Hit] = [:]
        var denied = false
        var javaScriptDisabledIn: String?
    }

    func start() {
        if CommandLine.arguments.contains("--demo-track") {
            showDemoTrack()
            return
        }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func send(_ command: NowPlayingCommand) {
        guard let bundleID = track?.sourceBundleID else { return }
        let work: () -> Void
        if let source = sources.first(where: { $0.bundleID == bundleID }) {
            let script = source.command(command)
            work = { _ = Self.run(script) }
        } else if let hit = browserHit, hit.track.sourceBundleID == bundleID,
                  let browser = BrowserMedia.all.first(where: { $0.bundleID == bundleID }) {
            work = { browser.send(command, at: hit.location) }
        } else {
            return
        }
        queue.async { [weak self] in
            work()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.poll()
            }
        }
    }

    private func poll() {
        let isRunning = { (id: String) in !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }
        let apps = sources.filter { isRunning($0.bundleID) }
        let browsers = BrowserMedia.all.filter { isRunning($0.bundleID) }
        queue.async { [weak self] in
            var result = PollResult()
            for source in apps {
                switch Self.run(source.stateScript) {
                case .success(let descriptor):
                    if let track = Self.parse(descriptor, source: source) { result.candidates.append(track) }
                case .failure(let error):
                    if error.code == -1743 { result.denied = true }
                }
            }
            for browser in browsers {
                switch browser.scan() {
                case .success(let hit?):
                    result.candidates.append(hit.track)
                    result.browserHits[browser.bundleID] = hit
                case .success(nil):
                    break
                case .failure(.notAuthorized):
                    result.denied = true
                case .failure(.javaScriptDisabled):
                    result.javaScriptDisabledIn = FileManager.default.displayName(
                        atPath: NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID)?.path ?? browser.bundleID)
                case .failure(.other):
                    break
                }
            }
            DispatchQueue.main.async {
                self?.apply(result)
            }
        }
    }

    private func apply(_ result: PollResult) {
        let newTrack = result.candidates.first(where: \.isPlaying) ?? result.candidates.first
        browserHit = newTrack.flatMap { result.browserHits[$0.sourceBundleID] }
        needsAutomationPermission = result.denied && newTrack == nil
        browserNeedingJavaScript = newTrack == nil ? result.javaScriptDisabledIn : nil
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
        let identity = track.identity
        if let url = browserHit?.artworkURL {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.setArtwork(image, for: identity) }
            }.resume()
            return
        }
        guard let source = sources.first(where: { $0.bundleID == track.sourceBundleID }) else { return }
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

    /// Fixed track with generated artwork, for checking the layout without a player.
    private func showDemoTrack() {
        track = NowPlayingTrack(title: "Midnight Drive", artist: "The Demo Band", album: "Night Roads",
                                duration: 214, position: 71, isPlaying: true,
                                sourceBundleID: "com.apple.Music", fetchedAt: Date())
        artwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemPurple, .systemIndigo])?.draw(in: rect, angle: -45)
            return true
        }
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
