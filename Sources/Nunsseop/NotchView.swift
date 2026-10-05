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
        // With the left ear hidden, the collapsed shape grows right only and its top row starts past the camera.
        let shift = model.isExpanded ? 0 : model.collapsedShift
        let earLead = shift > 0 ? model.geometry.collapsedSize.width - 6 : 0

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchBackground(shape: shape, glass: model.settings.liquidGlass, tint: model.settings.glassTint / 100, expanded: model.isExpanded, notchHeight: notchHeight)

                if model.isExpanded {
                    VStack(spacing: 0) {
                        HeaderBar(model: model, height: notchHeight)
                        Group {
                            switch model.tab {
                            case .home:
                                HStack(spacing: 16) {
                                    HomeTab(nowPlaying: nowPlaying, lyrics: model.settings.lyricsEnabled ? model.lyrics : nil)
                                    if model.settings.calendarEnabled {
                                        // A wide notch gives the calendar room for the whole week in large digits.
                                        let wide = model.expandedSize.width >= 700
                                        CalendarPanel(calendar: model.calendar, showsReminders: model.settings.remindersEnabled, wide: wide)
                                            .frame(width: wide ? 220 : 168)
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
                    // No scale here: scaling the scrolling tab row while it appears leaves it a few points off.
                    .transition(.opacity)
                } else if let event = model.hud.event {
                    HUDContent(event: event, height: notchHeight, earWidth: NotchViewModel.hudEarWidth, leadingInset: earLead)
                        .padding(.horizontal, topRadius + 6)
                        .transition(.opacity)
                } else if model.showsLiveActivity || model.showsSneakPeek || model.showsIdleEars {
                    VStack(spacing: 0) {
                        if model.showsLiveActivity {
                            CollapsedActivity(nowPlaying: nowPlaying, timer: model.timer, recorder: model.recorder,
                                              privacy: model.settings.privacyIndicator ? model.privacy : nil, call: model.calls.call,
                                              height: notchHeight, earWidth: model.earWidth,
                                              showsMusic: model.settings.collapsedMusic, showsTimer: model.settings.collapsedTimer)
                            .padding(.leading, earLead)
                        } else if model.showsIdleEars {
                            IdleEars(model: model, height: notchHeight)
                                .padding(.leading, earLead)
                        } else {
                            Color.clear.frame(height: notchHeight)
                        }
                        if model.showsSneakPeek, let title = model.sneakPeekCallTitle {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill").font(.system(size: 8)).foregroundStyle(.green)
                                Text(title).foregroundStyle(.white)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: NotchViewModel.sneakPeekHeight, alignment: .top)
                            .transition(.opacity)
                        } else if model.showsSneakPeek, let track = nowPlaying.track {
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
            .offset(x: shift)
            // Ears appearing is when the app's menus matter, so they are read again then.
            .onChange(of: model.collapsedSize.width) { old, new in
                if new > old { model.appMenus.refresh() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.liquidGlass, model.settings.liquidGlass)
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
