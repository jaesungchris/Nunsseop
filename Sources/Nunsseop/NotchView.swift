import SwiftUI

struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingController
    @State private var isDropTargeted = false
    @State private var isAirDropTargeted = false

    init(model: NotchViewModel) {
        self.model = model
        self.nowPlaying = model.nowPlaying
    }

    var body: some View {
        let size = model.currentSize
        let topRadius: CGFloat = model.isExpanded ? 18 : 6
        let bottomRadius: CGFloat = model.isExpanded ? 26 : 14
        let notchHeight = model.geometry.collapsedSize.height
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)

                if model.isExpanded {
                    VStack(spacing: 0) {
                        HeaderBar(model: model, height: notchHeight)
                        Group {
                            switch model.tab {
                            case .home:
                                HStack(spacing: 16) {
                                    HomeTab(nowPlaying: nowPlaying, lyrics: model.settings.lyricsEnabled ? model.lyrics : nil)
                                    if model.settings.calendarEnabled {
                                        CalendarPanel(calendar: model.calendar, showsReminders: model.settings.remindersEnabled)
                                            .frame(width: 168)
                                    }
                                }
                            case .shelf:
                                ShelfView(shelf: model.shelf, isDropTargeted: isDropTargeted && !isAirDropTargeted,
                                          isAirDropTargeted: isAirDropTargeted)
                            case .timer:
                                TimerTab(timer: model.timer)
                            case .clipboard:
                                ClipboardTab(history: model.clipboard)
                            case .notes:
                                NotesTab(notes: model.notes)
                            case .tools:
                                ToolsTab(tools: model.tools, recorder: model.recorder, recordAudio: model.settings.recordAudio)
                            case .system:
                                SystemTab(stats: model.stats, peripherals: model.settings.peripheralBatteries ? model.peripherals : nil)
                            case .apps:
                                AppsTab(launcher: model.launcher)
                            case .search:
                                SearchTab(model: model.search, shortcut: model.settings.searchHotkey ? model.settings.searchHotKey.label : nil)
                            case .emoji:
                                EmojiTab(model: model.emoji)
                            case .ai:
                                AIUsageTab(usage: model.aiUsage)
                            case .mirror:
                                MirrorTab(mirror: model.mirror, deviceID: model.settings.mirrorCameraID)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, topRadius + 14)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                } else if let event = model.hud.event {
                    HUDContent(event: event, height: notchHeight, earWidth: NotchViewModel.hudEarWidth)
                        .padding(.horizontal, topRadius + 6)
                        .transition(.opacity)
                } else if model.showsLiveActivity || model.showsSneakPeek {
                    VStack(spacing: 0) {
                        if model.showsLiveActivity {
                            CollapsedActivity(nowPlaying: nowPlaying, timer: model.timer, recorder: model.recorder,
                                              privacy: model.settings.privacyIndicator ? model.privacy : nil,
                                              height: notchHeight, earWidth: model.earWidth,
                                              showsMusic: model.settings.collapsedMusic, showsTimer: model.settings.collapsedTimer)
                        } else {
                            Color.clear.frame(height: notchHeight)
                        }
                        if model.showsSneakPeek, let track = nowPlaying.track {
                            SneakPeekLine(track: track, lyrics: model.settings.lyricsEnabled ? model.lyrics : nil)
                                .frame(height: NotchViewModel.sneakPeekHeight, alignment: .top)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, topRadius + 3)
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { model.expand() }
            .contextMenu {
                Button("Settings…") { SettingsWindowController.shared.show() }
                Button("Quit Nunsseop") { NSApp.terminate(nil) }
            }
            .onDrop(of: [.fileURL], delegate: NotchDropDelegate(
                model: model,
                isTargeted: $isDropTargeted,
                isAirDropTargeted: $isAirDropTargeted,
                airDropRect: airDropRect(in: size)
            ))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.isExpanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.showsLiveActivity)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.showsSneakPeek)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.hud.event)
        .animation(.easeInOut(duration: 0.18), value: model.tab)
    }
}

extension NotchView {
    /// Where ShelfView's AirDrop tile sits inside the expanded shape.
    func airDropRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = 18 + 14
        let top = max(model.geometry.collapsedSize.height, 24) + 8
        return CGRect(x: size.width - inset - ShelfView.airDropWidth, y: top,
                      width: ShelfView.airDropWidth, height: size.height - top - 16)
    }
}

/// Drops land on the shelf, or go straight to AirDrop when released over the AirDrop tile.
private struct NotchDropDelegate: DropDelegate {
    let model: NotchViewModel
    @Binding var isTargeted: Bool
    @Binding var isAirDropTargeted: Bool
    let airDropRect: CGRect

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        model.tab = .shelf
        model.expand()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isAirDropTargeted = model.isExpanded && model.tab == .shelf && airDropRect.contains(info.location)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        isAirDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        let toAirDrop = isAirDropTargeted
        isTargeted = false
        isAirDropTargeted = false
        if toAirDrop {
            ShelfSharing.loadURLs(from: providers) { ShelfSharing.airDrop($0) }
            return true
        }
        return model.shelf.handleDrop(providers)
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var weather: WeatherModel
    @ObservedObject private var updates = UpdateChecker.shared
    let height: CGFloat

    init(model: NotchViewModel, height: CGFloat) {
        self.model = model
        self.shelf = model.shelf
        self.weather = model.weather
        self.height = height
    }

    private static let slot: CGFloat = 36

    /// Room for the tab strip: left of the camera on notched displays, otherwise up to the status icons.
    private var layout: (strip: CGFloat, camera: CGFloat, side: CGFloat) {
        let content = model.expandedSize.width - 2 * NotchViewModel.headerInset
        let status = model.headerStatusWidth
        guard model.geometry.hasNotch else { return (content - status - 6, 0, content) }
        let camera = model.geometry.collapsedSize.width + 8
        let side = (content - camera - 12) / 2
        return (side, camera, side)
    }

    var body: some View {
        let layout = layout
        let tabs = model.settings.visibleTabs
        let needed = CGFloat(tabs.count) * Self.slot - 6
        HStack(spacing: 6) {
            if model.geometry.hasNotch {
                tabStrip(tabs, overflowing: needed > layout.strip)
                    .frame(width: layout.strip, alignment: .leading)
                Color.clear.frame(width: layout.camera)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    status
                }
                .frame(width: layout.side)
            } else {
                tabStrip(tabs, overflowing: needed > layout.strip)
                    .frame(width: min(needed, layout.strip), alignment: .leading)
                Spacer()
                if model.settings.headerDate && needed + 110 < layout.strip {
                    Text(Date.now, format: .dateTime.month().day().weekday(.abbreviated))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer()
                status
            }
        }
        .frame(height: max(height, 24))
    }

    private func tabStrip(_ tabs: [NotchTab], overflowing: Bool) -> some View {
        TabStrip(model: model, shelf: shelf, tabs: tabs, overflowing: overflowing,
                 visibleCount: max(1, Int((layout.strip + 6) / Self.slot)))
    }

    @ViewBuilder private var status: some View {
        if model.settings.headerWeather, let weather = model.weather.current {
            HStack(spacing: 4) {
                Image(systemName: WeatherModel.symbol(for: weather.code)).symbolRenderingMode(.multicolor)
                Text("\(Int(weather.temperature.rounded()))°").monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .help("\(weather.place) · \(Int(weather.low.rounded()))° / \(Int(weather.high.rounded()))°")
        }
        if model.settings.batteryInHeader, let power = model.hud.power {
            BatteryBadge(state: power)
        }
        Button { SettingsWindowController.shared.show() } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 26, height: 22)
                .overlay(alignment: .topTrailing) {
                    if updates.available != nil {
                        Circle().fill(Color.blue).frame(width: 6, height: 6).offset(x: -4, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        Button { NSApp.terminate(nil) } label: {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Quit Nunsseop")
    }
}

/// Tabs that don't fit scroll sideways, with arrows at the ends; the selected one is kept in view.
private struct TabStrip: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    let tabs: [NotchTab]
    let overflowing: Bool
    let visibleCount: Int
    @State private var leading: NotchTab?

    private var leadingIndex: Int { leading.flatMap { tabs.firstIndex(of: $0) } ?? 0 }
    private var canGoBack: Bool { overflowing && leadingIndex > 0 }
    private var canGoForward: Bool { overflowing && leadingIndex + visibleCount < tabs.count }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    TabButton(symbol: tab.symbol, selected: model.tab == tab,
                              badge: tab == .shelf ? shelf.items.count : 0) { model.tab = tab }
                        .help(tab.title)
                        .id(tab)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $leading, anchor: .leading)
        .scrollDisabled(!overflowing)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [canGoBack ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: 22)
                Color.black
                LinearGradient(colors: [.black, canGoForward ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: 22)
            }
        }
        .overlay(alignment: .leading) { if canGoBack { arrow("chevron.left", fade: .leading) { page(-1) } } }
        .overlay(alignment: .trailing) { if canGoForward { arrow("chevron.right", fade: .trailing) { page(1) } } }
        .onAppear { reveal(model.tab, animated: false) }
        .onChange(of: model.tab) { _, tab in reveal(tab, animated: true) }
    }

    /// Scrolls just enough to bring the tab into view.
    private func reveal(_ tab: NotchTab, animated: Bool) {
        guard overflowing, let index = tabs.firstIndex(of: tab) else { return }
        var target = leadingIndex
        if index < target { target = index }
        if index >= target + visibleCount { target = index - visibleCount + 1 }
        target = min(max(0, target), max(0, tabs.count - visibleCount))
        guard target != leadingIndex || leading == nil else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { leading = tabs[target] }
        } else {
            leading = tabs[target]
        }
    }

    private func page(_ direction: Int) {
        let step = max(1, visibleCount - 1)
        let target = min(max(0, leadingIndex + direction * step), max(0, tabs.count - visibleCount))
        withAnimation(.easeOut(duration: 0.25)) { leading = tabs[target] }
    }

    private func arrow(_ symbol: String, fade: Edge, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(colors: [.black.opacity(0), .black],
                                   startPoint: fade == .trailing ? .leading : .trailing,
                                   endPoint: fade == .trailing ? .trailing : .leading)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TabButton: View {
    let symbol: String
    let selected: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.45))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0)))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(.white))
                            .offset(x: 2, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HUD

private struct HUDContent: View {
    let event: HUDEvent
    let height: CGFloat
    let earWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: earWidth - 16, alignment: .leading)
                Spacer()
                trailing
                    .frame(width: earWidth - 16, alignment: .trailing)
            }
            .frame(height: height)
            if case .notice(_, let title, let detail) = event {
                Text(([title] + (detail.map { [$0] } ?? [])).joined(separator: "  ·  "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(height: NotchViewModel.sneakPeekHeight, alignment: .top)
            }
            if case .headphones(let battery) = event {
                Text(([battery.name] + battery.levels.map { "\($0.label) \($0.percent)%" }).joined(separator: "  ·  "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .frame(height: NotchViewModel.sneakPeekHeight, alignment: .top)
            }
        }
    }

    private var symbol: String {
        switch event {
        case .volume(let level, let muted):
            if muted || level == 0 { return "speaker.slash.fill" }
            return level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness(let level):
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard(let level):
            return level == 0 ? "light.min" : "light.max"
        case .power(let state):
            return state.onAC ? "bolt.fill" : BatteryBadge.symbol(for: state.percent)
        case .headphones:
            return "headphones"
        case .notice(let symbol, _, _):
            return symbol
        }
    }

    @ViewBuilder private var trailing: some View {
        switch event {
        case .volume(let level, let muted):
            LevelBar(value: muted ? 0 : Double(level))
        case .brightness(let level), .keyboard(let level):
            LevelBar(value: Double(level))
        case .power(let state):
            Text("\(state.percent)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(state.onAC ? .green : .white)
        case .notice:
            EmptyView()
        case .headphones(let battery):
            Text("\(battery.levels.map(\.percent).min() ?? 0)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

private struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

private struct BatteryBadge: View {
    let state: PowerState

    static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(state.percent)%").font(.system(size: 10, weight: .medium).monospacedDigit())
            Image(systemName: state.isCharging ? "battery.100percent.bolt" : Self.symbol(for: state.percent))
                .font(.system(size: 13))
                .foregroundStyle(state.percent <= 20 && !state.onAC ? .red : (state.onAC ? .green : .white))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.trailing, 4)
        .fixedSize()
    }
}

// MARK: - Collapsed

private struct CollapsedActivity: View {
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject var timer: TimerModel
    @ObservedObject var recorder: ScreenRecorder
    let privacy: PrivacyMonitor?
    let height: CGFloat
    let earWidth: CGFloat
    let showsMusic: Bool
    let showsTimer: Bool

    var body: some View {
        let art = min(height - 10, 32)
        let playing = showsMusic && nowPlaying.track?.isPlaying == true
        HStack {
            if playing {
                ArtworkView(image: nowPlaying.artwork, cornerRadius: art > 16 ? 5 : 3)
                    .frame(width: art, height: art)
            } else if recorder.isRecording {
                Circle().fill(.red).frame(width: 8, height: 8)
            } else if let privacy, privacy.cameraInUse || privacy.micInUse {
                HStack(spacing: 3) {
                    if privacy.cameraInUse { Image(systemName: "video.fill").foregroundStyle(.green) }
                    if privacy.micInUse { Image(systemName: "mic.fill").foregroundStyle(.orange) }
                }
                .font(.system(size: 10, weight: .semibold))
            } else {
                Image(systemName: timer.mode == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(timer.mode == .pomodoro && timer.phase == .rest ? .green : .orange)
            }
            Spacer()
            if let started = recorder.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerModel.format(context.date.timeIntervalSince(started)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.red)
                }
            } else if let privacy, (privacy.cameraInUse || privacy.micInUse), !(showsTimer && timer.isRunning), playing {
                HStack(spacing: 3) {
                    if privacy.cameraInUse { Circle().fill(.green).frame(width: 6, height: 6) }
                    if privacy.micInUse { Circle().fill(.orange).frame(width: 6, height: 6) }
                }
            } else if showsTimer && timer.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerModel.format(timer.value(at: context.date)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            } else {
                SpectrumBars(isPlaying: playing, tint: nowPlaying.tint)
                    .frame(width: art - 2, height: max(8, art - 6))
            }
        }
        .frame(height: height)
    }
}

private struct SneakPeekLine: View {
    let track: NowPlayingTrack
    let lyrics: LyricsModel?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(spacing: 6) {
                Image(systemName: track.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.6))
                if track.isPlaying, let line = lyrics?.line(at: track.position(at: context.date)) {
                    Text(line).foregroundStyle(.white)
                        .id(line)
                        .transition(.opacity)
                } else {
                    Text(track.title).foregroundStyle(.white)
                    if !track.artist.isEmpty {
                        Text(track.artist).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: lyrics?.line(at: track.position(at: context.date)))
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 10)
    }
}

// MARK: - Home

private struct HomeTab: View {
    @ObservedObject var nowPlaying: NowPlayingController
    let lyrics: LyricsModel?

    private var emptyMessage: String {
        if let browser = nowPlaying.browserNeedingJavaScript {
            return BrowserMedia.enableHint(for: browser)
        }
        if nowPlaying.needsAutomationPermission {
            return String(localized: "Allow Nunsseop in System Settings › Privacy & Security › Automation")
        }
        return String(localized: "Play something in any app or browser and it shows up here")
    }

    var body: some View {
        if let track = nowPlaying.track {
            HStack(spacing: 18) {
                GlowingArtwork(image: nowPlaying.artwork, tint: nowPlaying.tint, sourceBundleID: track.sourceBundleID)
                    .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            if track.isPlaying, let lyrics, !lyrics.lines.isEmpty {
                                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                                    Text(lyrics.line(at: track.position(at: context.date)) ?? (track.artist.isEmpty ? track.album : track.artist))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(nowPlaying.tint)
                                        .lineLimit(1)
                                }
                            } else {
                                Text(track.artist.isEmpty ? track.album : track.artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        SpectrumBars(isPlaying: track.isPlaying, tint: nowPlaying.tint)
                            .frame(width: 18, height: 14)
                    }
                    Spacer(minLength: 6)
                    ProgressRow(track: track, tint: nowPlaying.tint) { nowPlaying.send(.seek($0)) }
                    Spacer(minLength: 6)
                    HStack(spacing: 30) {
                        ControlButton(symbol: "backward.fill") { nowPlaying.send(.previous) }
                        ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 24) {
                            nowPlaying.send(.playPause)
                        }
                        ControlButton(symbol: "forward.fill") { nowPlaying.send(.next) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 104)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08))
                    Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.white.opacity(0.35))
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing").font(.system(size: 15, weight: .semibold))
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    if nowPlaying.browserNeedingJavaScript == BrowserMedia.diaBundleID {
                        Button("Relaunch Dia with JavaScript allowed") { BrowserMedia.relaunchDiaWithJavaScript() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.15)))
                            .padding(.top, 2)
                            .help("Quits Dia and opens it again with \(BrowserMedia.diaJavaScriptFlag). Dia restores its tabs.")
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct GlowingArtwork: View {
    let image: NSImage?
    let tint: Color
    let sourceBundleID: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkView(image: image, cornerRadius: 16)
                .shadow(color: image == nil ? .clear : tint.opacity(0.55), radius: 16)
            if let icon = Self.appIcon(for: sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .offset(x: 6, y: 6)
            }
        }
    }

    static func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct ProgressRow: View {
    let track: NowPlayingTrack
    let tint: Color
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = track.duration > 0 ? track.position(at: context.date) / track.duration : 0
            let fraction = min(1, max(0, dragFraction ?? live))
            let position = fraction * track.duration
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(tint).frame(width: max(5, proxy.size.width * fraction))
                    }
                    .frame(height: dragFraction == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard track.duration > 0 else { return }
                                dragFraction = min(1, max(0, value.location.x / proxy.size.width))
                            }
                            .onEnded { _ in
                                if let dragFraction, track.duration > 0 { onSeek(dragFraction * track.duration) }
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 12)
                .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(0, track.duration - position)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 16
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: size + 18, height: size + 14)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared pieces

private struct ArtworkView: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.white.opacity(0.12))
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct SpectrumBars: View {
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { i in
                    let phase = sin(t * (4.3 + Double(i) * 1.9) + Double(i) * 1.3)
                    Capsule()
                        .fill(tint)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: isPlaying ? 0.3 + 0.7 * abs(phase) : 0.25)
                }
            }
        }
    }
}
