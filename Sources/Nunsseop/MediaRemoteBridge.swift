import AppKit

struct MediaRemoteUpdate {
    var track: NowPlayingTrack?
    var artwork: Data?
}

/// Runs the MediaRemote helper (Resources/nowplaying.pl + libNowPlayingHelper.dylib)
/// inside /usr/bin/perl and turns its JSON lines into updates.
@MainActor
final class MediaRemoteBridge {
    var onUpdate: ((MediaRemoteUpdate) -> Void)?
    /// Called when the helper cannot start or keeps exiting; callers fall back to other sources.
    var onUnavailable: (() -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var restarts = 0

    func start() {
        guard let script = Bundle.main.url(forResource: "nowplaying", withExtension: "pl"),
              let library = Bundle.main.url(forResource: "libNowPlayingHelper", withExtension: "dylib") else {
            onUnavailable?()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, library.path]
        process.environment = ["PATH": "/usr/bin:/bin"]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.helperExited() }
        }
        do {
            try process.run()
        } catch {
            onUnavailable?()
            return
        }
        self.process = process
        self.input = input.fileHandleForWriting
        self.output = output.fileHandleForReading
    }

    func send(_ command: NowPlayingCommand) {
        let word: String
        switch command {
        case .playPause: word = "toggle"
        case .next: word = "next"
        case .previous: word = "previous"
        case .seek(let seconds): word = "seek \(max(0, seconds))"
        case .rate(let rate): word = "rate \(rate)"
        }
        try? input?.write(contentsOf: Data((word + "\n").utf8))
    }

    private func helperExited() {
        output?.readabilityHandler = nil
        process = nil
        input = nil
        output = nil
        buffer.removeAll()
        onUnavailable?()
        restarts += 1
        guard restarts <= 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.start() }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard let info = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if info["error"] != nil {
            process?.terminate()
            return
        }
        restarts = 0
        guard info["active"] as? Bool == true, let title = info["title"] as? String, !title.isEmpty else {
            onUpdate?(MediaRemoteUpdate(track: nil, artwork: nil))
            return
        }
        let rate = info["rate"] as? Double ?? 0
        var position = info["elapsed"] as? Double ?? 0
        if let timestamp = info["timestamp"] as? Double, rate > 0 {
            position += (Date().timeIntervalSince1970 - timestamp) * rate
        }
        // MRMediaRemoteCommand codes: 19 changes the playback rate, 24 seeks. Nil when the helper could not read them.
        let commands = info["commands"] as? [Int]
        let track = NowPlayingTrack(
            title: title,
            artist: info["artist"] as? String ?? "",
            album: info["album"] as? String ?? "",
            duration: info["duration"] as? Double ?? 0,
            position: position,
            isPlaying: rate > 0,
            sourceBundleID: info["bundleID"] as? String ?? "",
            fetchedAt: Date(),
            rate: rate > 0 ? rate : 1,
            canSeek: commands?.contains(24) ?? true,
            canChangeRate: commands?.contains(19) ?? false
        )
        let artwork = (info["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
        onUpdate?(MediaRemoteUpdate(track: track, artwork: artwork))
    }
}
