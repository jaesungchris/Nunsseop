import AppKit
import Combine

/// Writes a PNG of the panel after each expand/collapse settles. Enabled with
/// `--snapshot-dir <path>`; used to verify rendering without screen-recording access.
@MainActor
final class DebugSnapshotter {
    private let directory: URL
    private weak var view: NSView?
    private var cancellable: AnyCancellable?
    private var counter = 0

    init(directory: URL, view: NSView, model: NotchViewModel) {
        self.directory = directory
        self.view = view
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cancellable = model.$isExpanded
            .sink { [weak self] expanded in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self?.capture(label: expanded ? "expanded" : "collapsed")
                }
            }
    }

    private func capture(label: String) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        counter += 1
        let url = directory.appendingPathComponent(String(format: "%02d-%@.png", counter, label))
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("snapshot \(url.path)")
    }
}
