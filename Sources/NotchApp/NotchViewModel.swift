import AppKit
import Combine

enum NotchTab {
    case home, shelf
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    @Published var tab: NotchTab = .home
    @Published private(set) var showsLiveActivity = false

    let settings: AppSettings
    let nowPlaying = NowPlayingController()
    let shelf = ShelfStore()
    private var cancellables: Set<AnyCancellable> = []

    init(geometry: NotchGeometry, settings: AppSettings) {
        self.geometry = geometry
        self.settings = settings
        nowPlaying.$track
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .sink { [weak self] in self?.showsLiveActivity = $0 }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var expandedSize: CGSize {
        CGSize(width: settings.expandedWidth, height: settings.expandedHeight)
    }

    /// While music plays, the collapsed notch grows an "ear" on each side
    /// for the artwork and a playback indicator.
    var collapsedSize: CGSize {
        let base = geometry.collapsedSize
        guard showsLiveActivity else { return base }
        return CGSize(width: base.width + 2 * earWidth, height: base.height)
    }

    var earWidth: CGFloat {
        let height = geometry.collapsedSize.height
        return settings.compactLiveActivity ? height * 0.7 : height + 6
    }

    var currentSize: CGSize {
        isExpanded ? expandedSize : collapsedSize
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
