import SwiftUI

struct HomeTab: View {
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

    /// Podcasts, videos and long mixes, where skipping and speed matter.
    private func isLong(_ track: NowPlayingTrack) -> Bool { track.duration > 600 }

    static func rateLabel(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    @ViewBuilder
    private func transportButtons(_ track: NowPlayingTrack) -> some View {
        ControlButton(symbol: "backward.fill") { nowPlaying.send(.previous) }
        ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 24) {
            nowPlaying.send(.playPause)
        }
        ControlButton(symbol: "forward.fill") { nowPlaying.send(.next) }
    }

    var body: some View {
        if let track = nowPlaying.track {
            HStack(spacing: 18) {
                // Gives way to the controls when the notch is narrow.
                GlowingArtwork(image: nowPlaying.artwork, tint: nowPlaying.tint, sourceBundleID: track.sourceBundleID)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(minWidth: 80, maxWidth: 104, maxHeight: 104)
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
                        if track.canChangeRate && (isLong(track) || track.rate != 1) {
                            Button { nowPlaying.cycleRate() } label: {
                                Text(Self.rateLabel(track.rate))
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(.white.opacity(track.rate == 1 ? 0.1 : 0.22)))
                            }
                            .buttonStyle(.plain)
                            .help(Text("Playback speed"))
                        }
                        SpectrumBars(isPlaying: track.isPlaying, tint: nowPlaying.tint)
                            .frame(width: 18, height: 14)
                    }
                    Spacer(minLength: 6)
                    ProgressRow(track: track, tint: nowPlaying.tint) { nowPlaying.send(.seek($0)) }
                    Spacer(minLength: 6)
                    // Skip buttons only for long tracks, and only where they fit beside the calendar.
                    ViewThatFits(in: .horizontal) {
                        if track.canSeek && isLong(track) {
                            HStack(spacing: 14) {
                                ControlButton(symbol: "gobackward.15", size: 13) { nowPlaying.skip(by: -15) }
                                    .help(Text("Back 15 seconds"))
                                transportButtons(track)
                                ControlButton(symbol: "goforward.15", size: 13) { nowPlaying.skip(by: 15) }
                                    .help(Text("Forward 15 seconds"))
                            }
                        }
                        HStack(spacing: 30) { transportButtons(track) }
                        HStack(spacing: 12) { transportButtons(track) }
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
            if let icon = InstalledApps.icon(for: sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .offset(x: 6, y: 6)
            }
        }
    }
}

private struct ProgressRow: View {
    let track: NowPlayingTrack
    let tint: Color
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !track.isPlaying)) { context in
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
