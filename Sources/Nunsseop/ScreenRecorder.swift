import AppKit
import CoreGraphics

/// Records the main display with the system `screencapture` tool and shows a live
/// indicator in the notch while recording. Needs Screen Recording permission.
@MainActor
final class ScreenRecorder: ObservableObject {
    @Published private(set) var startedAt: Date?
    var onFinished: ((URL?) -> Void)?

    private var process: Process?
    private var output: URL?

    var isRecording: Bool { startedAt != nil }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func toggle(withAudio: Bool) {
        isRecording ? stop() : start(withAudio: withAudio)
    }

    func start(withAudio: Bool) {
        guard process == nil else { return }
        guard Self.hasPermission else {
            CGRequestScreenCaptureAccess()
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let directory = ScreenshotWatcher.directory
        let url = directory.appendingPathComponent("Nunsseop Recording \(formatter.string(from: .now)).mov")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-v", "-C", "-k"] + (withAudio ? ["-g"] : []) + [url.path]
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.finished() }
        }
        do {
            try process.run()
        } catch {
            return
        }
        self.process = process
        output = url
        startedAt = .now
    }

    func stop() {
        // screencapture finishes the file cleanly on interrupt.
        process?.interrupt()
    }

    private func finished() {
        let url = output
        process = nil
        output = nil
        startedAt = nil
        let saved = url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        onFinished?(saved)
    }
}
