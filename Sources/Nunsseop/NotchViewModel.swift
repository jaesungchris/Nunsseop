import AppKit
import Combine

/// What each side of the collapsed notch shows while nothing is playing or running.
enum IdleItem: String, CaseIterable, Identifiable {
    case none, claude, codex, battery, weather, date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "Nothing")
        case .claude: return String(localized: "Claude Code left")
        case .codex: return String(localized: "Codex left")
        case .battery: return String(localized: "Battery")
        case .weather: return String(localized: "Weather")
        case .date: return String(localized: "Date")
        }
    }

    var usesAIUsage: Bool { self == .claude || self == .codex }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, timer, clipboard, notes, tools, system, apps, search, emoji, ai, mirror

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .tools: return "switch.2"
        case .system: return "cpu"
        case .apps: return "square.grid.3x3.fill"
        case .search: return "magnifyingglass"
        case .emoji: return "face.smiling"
        case .ai: return "sparkles"
        case .mirror: return "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .shelf: return String(localized: "Shelf")
        case .timer: return String(localized: "Timer")
        case .clipboard: return String(localized: "Clipboard")
        case .notes: return String(localized: "Notes")
        case .tools: return String(localized: "Tools")
        case .system: return String(localized: "System")
        case .apps: return String(localized: "Apps")
        case .search: return String(localized: "Search")
        case .emoji: return String(localized: "Emoji")
        case .ai: return String(localized: "AI usage")
        case .mirror: return String(localized: "Mirror")
        }
    }
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
    let timer = TimerModel()
    let clipboard = ClipboardHistory()
    let notes = NotesModel()
    let tools = ToolsModel()
    let screenshots = ScreenshotWatcher()
    let capsLock = CapsLockWatcher()
    let notifyServer = NotifyServer()
    let stats = SystemStats()
    let launcher = AppLauncher()
    let lyrics = LyricsModel()
    let weather = WeatherModel()
    let downloads = DownloadWatcher()
    let peripherals = PeripheralMonitor()
    let privacy = PrivacyMonitor()
    let emoji = EmojiModel()
    let aiUsage = AIUsageModel()
    lazy var search = QuickSearchModel(clipboard: clipboard, emoji: emoji, tools: tools)
    let recorder = ScreenRecorder()
    /// Set when opened by the hotkey; the notch then stays open until the pointer visits it or Escape is pressed.
    @Published var pinned = false
    private var cancellables: Set<AnyCancellable> = []
    private var sneakPeekWork: DispatchWorkItem?

    static let sneakPeekHeight: CGFloat = 24

    init(geometry: NotchGeometry, settings: AppSettings) {
        self.geometry = geometry
        self.settings = settings
        self.hud = HUDCenter(settings: settings)
        Publishers.CombineLatest4(nowPlaying.$track.map { $0?.isPlaying == true }, timer.$anchor.map { $0 != nil },
                                  settings.$collapsedMusic, settings.$collapsedTimer)
            .map { music, timer, showMusic, showTimer in (music && showMusic) || (timer && showTimer) }
            .combineLatest(recorder.$startedAt.map { $0 != nil },
                           privacy.$cameraInUse.combineLatest(privacy.$micInUse, settings.$privacyIndicator).map { ($0 || $1) && $2 })
            .map { $0 || $1 || $2 }
            .removeDuplicates()
            .sink { [weak self] in self?.showsLiveActivity = $0 }
            .store(in: &cancellables)
        nowPlaying.$track
            .sink { [weak self] in self?.lyrics.update(for: $0) }
            .store(in: &cancellables)
        lyrics.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recorder.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        privacy.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        timer.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        nowPlaying.$track
            .compactMap { $0.map { "\($0.identity)|\($0.isPlaying)" } }
            .removeDuplicates()
            .sink { [weak self] _ in self?.triggerSneakPeek() }
            .store(in: &cancellables)
        hud.$event
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // The idle ears show these.
        hud.$power.map { _ in () }
            .merge(with: weather.$current.map { _ in () }, aiUsage.$providers.map { _ in () })
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.leaveHiddenTab() }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var expandedSize: CGSize {
        var width = settings.expandedWidth
        if settings.widenForTabs { width = max(width, min(widthFittingTabs, geometry.maxExpandedWidth)) }
        return CGSize(width: width, height: settings.expandedHeight)
    }

    static let tabSlot: CGFloat = 36
    /// Horizontal inset of the expanded content from the shape's edge.
    static let headerInset: CGFloat = 18 + 14

    /// Battery, weather, Settings and Quit at the right end of the header.
    var headerStatusWidth: CGFloat {
        var width: CGFloat = 2 * (26 + 6)
        if settings.batteryInHeader && hud.power != nil { width += 58 }
        if settings.headerWeather && weather.current != nil { width += 50 }
        return width
    }

    /// The width that shows every tab in one row, left of the camera on notched displays.
    private var widthFittingTabs: CGFloat {
        let tabs = CGFloat(settings.visibleTabs.count) * Self.tabSlot - 6
        let content: CGFloat
        if geometry.hasNotch {
            let side = max(tabs + 2, headerStatusWidth)
            content = 2 * side + geometry.collapsedSize.width + 8 + 12
        } else {
            content = tabs + 6 + headerStatusWidth
        }
        return content + 2 * Self.headerInset
    }

    var showsSneakPeek: Bool {
        guard settings.sneakPeekEnabled, let track = nowPlaying.track else { return false }
        let lyricsLive = settings.lyricsEnabled && settings.lyricsUnderNotch && track.isPlaying && !lyrics.lines.isEmpty
        return settings.sneakPeekAlways || sneakPeekPending || lyricsLive
    }

    /// While music plays, the collapsed notch grows an "ear" on each side
    /// for the artwork and a playback indicator, plus a text line underneath
    /// while the sneak peek shows.
    static let hudEarWidth: CGFloat = 96
    /// Room for a short value such as "73%" or "16°" on each side while idle.
    static let idleEarWidth: CGFloat = 64

    var showsHUD: Bool { hud.event != nil }

    var collapsedSize: CGSize {
        var size = geometry.collapsedSize
        if let event = hud.event {
            size.width += 2 * Self.hudEarWidth
            switch event {
            case .headphones, .notice: size.height += Self.sneakPeekHeight
            default: break
            }
            return size
        }
        if showsLiveActivity {
            size.width += 2 * earWidth
        } else if showsIdleEars {
            size.width += 2 * Self.idleEarWidth
        }
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
        let base = settings.compactLiveActivity ? height * 0.7 : height + 6
        // Room for "12:34" when a timer is running.
        let needsText = (timer.isRunning && settings.collapsedTimer) || recorder.isRecording
        return needsText ? max(base, 50) : base
    }

    var currentSize: CGSize {
        isExpanded ? expandedSize : collapsedSize
    }

    private func leaveHiddenTab() {
        if !settings.isVisible(tab) { tab = .home }
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        pinned = false
        // The camera must only start from an explicit click on the Mirror tab.
        if tab == .mirror { tab = .home }
        // Search opened by its shortcut may be a tab the header doesn't show.
        leaveHiddenTab()
    }
}
