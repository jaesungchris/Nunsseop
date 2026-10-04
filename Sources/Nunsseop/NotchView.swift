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
                                    HomeTab(nowPlaying: nowPlaying)
                                    if model.settings.calendarEnabled {
                                        CalendarPanel(calendar: model.calendar)
                                            .frame(width: 168)
                                    }
                                }
                            case .shelf:
                                ShelfView(shelf: model.shelf, isDropTargeted: isDropTargeted && !isAirDropTargeted,
                                          isAirDropTargeted: isAirDropTargeted)
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
                            CollapsedActivity(nowPlaying: nowPlaying, height: notchHeight, earWidth: model.earWidth)
                        } else {
                            Color.clear.frame(height: notchHeight)
                        }
                        if model.showsSneakPeek, let track = nowPlaying.track {
                            SneakPeekLine(track: track)
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
    let height: CGFloat

    init(model: NotchViewModel, height: CGFloat) {
        self.model = model
        self.shelf = model.shelf
        self.height = height
    }

    var body: some View {
        HStack(spacing: 6) {
            TabButton(symbol: "house.fill", selected: model.tab == .home) { model.tab = .home }
            TabButton(symbol: "tray.fill", selected: model.tab == .shelf,
                      badge: shelf.items.count) { model.tab = .shelf }
            Spacer()
            // The middle of the header sits under the camera housing on notched displays.
            if !model.geometry.hasNotch {
                Text(Date.now, format: .dateTime.month().day().weekday(.abbreviated))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            if model.settings.batteryInHeader, let power = model.hud.power {
                BatteryBadge(state: power)
            }
            Button { SettingsWindowController.shared.show() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 26, height: 22)
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
        .frame(height: max(height, 24))
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
        case .power(let state):
            return state.onAC ? "bolt.fill" : BatteryBadge.symbol(for: state.percent)
        case .headphones:
            return "headphones"
        }
    }

    @ViewBuilder private var trailing: some View {
        switch event {
        case .volume(let level, let muted):
            LevelBar(value: muted ? 0 : Double(level))
        case .brightness(let level):
            LevelBar(value: Double(level))
        case .power(let state):
            Text("\(state.percent)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(state.onAC ? .green : .white)
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
    }
}

// MARK: - Collapsed

private struct CollapsedActivity: View {
    @ObservedObject var nowPlaying: NowPlayingController
    let height: CGFloat
    let earWidth: CGFloat

    var body: some View {
        let art = min(height - 10, earWidth - 4)
        HStack {
            ArtworkView(image: nowPlaying.artwork, cornerRadius: art > 16 ? 5 : 3)
                .frame(width: art, height: art)
            Spacer()
            SpectrumBars(isPlaying: nowPlaying.track?.isPlaying == true, tint: nowPlaying.tint)
                .frame(width: art - 2, height: max(8, art - 6))
        }
        .frame(height: height)
    }
}

private struct SneakPeekLine: View {
    let track: NowPlayingTrack

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: track.isPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.6))
            Text(track.title).foregroundStyle(.white)
            if !track.artist.isEmpty {
                Text(track.artist).foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 10)
    }
}

// MARK: - Home

private struct HomeTab: View {
    @ObservedObject var nowPlaying: NowPlayingController

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
                            Text(track.artist.isEmpty ? track.album : track.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
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
