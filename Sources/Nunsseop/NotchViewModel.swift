import AppKit
import Combine

enum NotchTab {
    case home, shelf, mirror
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    @Published var tab: NotchTab = .home
    @Published private(set) var showsLiveActivity = false
    @Published private(set) var sneakPeekPending = false

    let settings: AppSettings
    let nowPlaying = NowPlayingController()
    let shelf = ShelfStore()
    let hud: HUDCenter
    let calendar = CalendarModel()
    let mirror = MirrorModel()
    private var cancellables: Set<AnyCancellable> = []
    private var sneakPeekWork: DispatchWorkItem?

    static let sneakPeekHeight: CGFloat = 24

    init(geometry: NotchGeometry, settings: AppSettings) {
        self.geometry = geometry
        self.settings = settings
        self.hud = HUDCenter(settings: settings)
        nowPlaying.$track
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .sink { [weak self] in self?.showsLiveActivity = $0 }
            .store(in: &cancellables)
        nowPlaying.$track
            .compactMap { $0.map { "\($0.identity)|\($0.isPlaying)" } }
            .removeDuplicates()
            .sink { [weak self] _ in self?.triggerSneakPeek() }
            .store(in: &cancellables)
        hud.$event
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.$mirrorEnabled
            .filter { !$0 }
            .sink { [weak self] _ in if self?.tab == .mirror { self?.tab = .home } }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var expandedSize: CGSize {
        CGSize(width: settings.expandedWidth, height: settings.expandedHeight)
    }

    var showsSneakPeek: Bool {
        settings.sneakPeekEnabled && nowPlaying.track != nil && (settings.sneakPeekAlways || sneakPeekPending)
    }

    /// While music plays, the collapsed notch grows an "ear" on each side
    /// for the artwork and a playback indicator, plus a text line underneath
    /// while the sneak peek shows.
    static let hudEarWidth: CGFloat = 96

    var showsHUD: Bool { hud.event != nil }

    var collapsedSize: CGSize {
        var size = geometry.collapsedSize
        if let event = hud.event {
            size.width += 2 * Self.hudEarWidth
            if case .headphones = event { size.height += Self.sneakPeekHeight }
            return size
        }
        if showsLiveActivity { size.width += 2 * earWidth }
        if showsSneakPeek {
            size.width = max(size.width, 300)
            size.height += Self.sneakPeekHeight
        }
        return size
    }

    private func triggerSneakPeek() {
        sneakPeekWork?.cancel()
        sneakPeekPending = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.sneakPeekPending = false }
        }
        sneakPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.sneakPeekDuration, execute: work)
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
        // The camera must only start from an explicit click on the Mirror tab.
        if tab == .mirror { tab = .home }
    }
}
