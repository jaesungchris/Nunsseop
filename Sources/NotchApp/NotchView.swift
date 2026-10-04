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
        let topRadius: CGFloat = model.isExpanded ? 14 : 6
        let bottomRadius: CGFloat = model.isExpanded ? 28 : 12
        let notchHeight = model.geometry.collapsedSize.height

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .fill(Color.black)

                if model.isExpanded {
                    ExpandedContent(nowPlaying: nowPlaying, shelf: model.shelf, isDropTargeted: isDropTargeted)
                        .padding(.top, notchHeight + 4)
                        .padding(.horizontal, topRadius + 18)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if model.showsLiveActivity {
                    CollapsedActivity(nowPlaying: nowPlaying, height: notchHeight)
                        .padding(.horizontal, topRadius + 4)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
            .onTapGesture { model.expand() }
            .contextMenu {
                Button("NotchApp 종료") { NSApp.terminate(nil) }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                model.shelf.handleDrop(providers)
            }
            .onChange(of: isDropTargeted) { _, targeted in
                if targeted { model.expand() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.isExpanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.showsLiveActivity)
    }
}

private struct CollapsedActivity: View {
    @ObservedObject var nowPlaying: NowPlayingController
    let height: CGFloat

    var body: some View {
        HStack {
            ArtworkView(image: nowPlaying.artwork, cornerRadius: 4)
                .frame(width: height - 8, height: height - 8)
            Spacer()
            PlaybackBars(isPlaying: nowPlaying.track?.isPlaying == true)
                .frame(width: height - 12, height: height - 14)
        }
        .frame(height: height)
    }
}

private struct ExpandedContent: View {
    @ObservedObject var nowPlaying: NowPlayingController
    let shelf: ShelfStore
    let isDropTargeted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            NowPlayingPanel(nowPlaying: nowPlaying)
                .frame(width: 300, alignment: .leading)
            ShelfView(shelf: shelf, isDropTargeted: isDropTargeted)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NowPlayingPanel: View {
    @ObservedObject var nowPlaying: NowPlayingController

    var body: some View {
        if let track = nowPlaying.track {
            HStack(spacing: 14) {
                ArtworkView(image: nowPlaying.artwork, cornerRadius: 10)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    ProgressRow(track: track).padding(.top, 4)
                    HStack(spacing: 22) {
                        ControlButton(symbol: "backward.fill") { nowPlaying.send(.previous) }
                        ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                            nowPlaying.send(.playPause)
                        }
                        ControlButton(symbol: "forward.fill") { nowPlaying.send(.next) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("재생 중인 음악 없음").font(.system(size: 14, weight: .semibold))
                Text(nowPlaying.needsAutomationPermission
                     ? "시스템 설정 › 개인정보 보호 및 보안 › 자동화에서 NotchApp을 허용하세요"
                     : "Music 또는 Spotify에서 재생하면 여기에 표시됩니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

private struct ProgressRow: View {
    let track: NowPlayingTrack

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = track.position(at: context.date)
            let fraction = track.duration > 0 ? position / track.duration : 0
            HStack(spacing: 6) {
                Text(Self.format(position))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 4)
                Text(Self.format(track.duration))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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

private struct PlaybackBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { i in
                    let phase = sin(t * (5 + Double(i) * 1.7) + Double(i))
                    Capsule()
                        .fill(Color.green)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: isPlaying ? 0.35 + 0.65 * abs(phase) : 0.3)
                }
            }
        }
    }
}
