import SwiftUI

struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingController
    @State private var isDropTargeted = false

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
                                HomeTab(nowPlaying: nowPlaying)
                            case .shelf:
                                ShelfView(shelf: model.shelf, isDropTargeted: isDropTargeted)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, topRadius + 14)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                } else if model.showsLiveActivity {
                    CollapsedActivity(nowPlaying: nowPlaying, height: notchHeight, earWidth: model.earWidth)
                        .padding(.horizontal, topRadius + 3)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { model.expand() }
            .contextMenu {
                Button("설정…") { SettingsWindowController.shared.show() }
                Button("NotchApp 종료") { NSApp.terminate(nil) }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                model.shelf.handleDrop(providers)
            }
            .onChange(of: isDropTargeted) { _, targeted in
                if targeted {
                    model.tab = .shelf
                    model.expand()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.isExpanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.showsLiveActivity)
        .animation(.easeInOut(duration: 0.18), value: model.tab)
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
            Button { SettingsWindowController.shared.show() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("설정")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("NotchApp 종료")
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

// MARK: - Home

private struct HomeTab: View {
    @ObservedObject var nowPlaying: NowPlayingController

    private var emptyMessage: String {
        if let browser = nowPlaying.browserNeedingJavaScript {
            return "\(browser)의 메뉴 보기(또는 개발자) › 'Apple Events의 JavaScript 허용'을 켜면 브라우저 재생도 표시됩니다"
        }
        if nowPlaying.needsAutomationPermission {
            return "시스템 설정 › 개인정보 보호 및 보안 › 자동화에서 NotchApp을 허용하세요"
        }
        return "Music, Spotify 또는 브라우저에서 재생하면 여기에 표시됩니다"
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
                    ProgressRow(track: track, tint: nowPlaying.tint)
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
                    Text("재생 중인 음악 없음").font(.system(size: 15, weight: .semibold))
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = track.position(at: context.date)
            let fraction = track.duration > 0 ? position / track.duration : 0
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(tint).frame(width: max(5, proxy.size.width * fraction))
                    }
                }
                .frame(height: 5)
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
        let s = Int(seconds.rounded(.down))
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
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(.white.opacity(0.12))
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
