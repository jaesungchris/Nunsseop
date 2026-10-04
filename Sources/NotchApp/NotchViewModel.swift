import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    @Published private(set) var showsLiveActivity = false

    let nowPlaying = NowPlayingController()
    let shelf = ShelfStore()
    private var cancellables: Set<AnyCancellable> = []

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        nowPlaying.$track
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .sink { [weak self] in self?.showsLiveActivity = $0 }
            .store(in: &cancellables)
    }

    /// While music plays, the collapsed notch grows a square "ear" on each side
    /// for the artwork and a playback indicator.
    var collapsedSize: CGSize {
        let base = geometry.collapsedSize
        guard showsLiveActivity else { return base }
        return CGSize(width: base.width + 2 * (base.height + 6), height: base.height)
    }

    var currentSize: CGSize {
        isExpanded ? NotchGeometry.expandedSize : collapsedSize
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
    }
}
