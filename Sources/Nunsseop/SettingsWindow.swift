import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "Nunsseop Settings")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Reopens on the pane used last.
    @AppStorage("settingsPane") private var pane = "general"

    var body: some View {
        TabView(selection: $pane) {
            GeneralPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            LayoutPane(settings: settings)
                .tabItem { Label("Notch", systemImage: "rectangle.topthird.inset.filled") }
                .tag("layout")
            AlertsPane(settings: settings)
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
                .tag("alerts")
            ServicesPane(settings: settings)
                .tabItem { Label("Services", systemImage: "puzzlepiece.extension") }
                .tag("services")
        }
        .frame(width: 500, height: 600)
    }
}

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updates = UpdateChecker.shared
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Nunsseop at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.needsApproval {
                    Text("Allow Nunsseop in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !launchAtLogin.isInApplicationsFolder {
                    Text("Move the app to /Applications before turning this on. Current location: \(Bundle.main.bundlePath)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                HStack {
                    if let release = updates.available {
                        Text("Version \(release.version) is available")
                        Spacer()
                        Button("Download") { NSWorkspace.shared.open(release.url) }
                    } else {
                        Text(updates.isChecking ? String(localized: "Checking…")
                             : updates.failed ? String(localized: "Couldn't check for updates")
                             : updates.lastChecked == nil ? String(localized: "Not checked yet")
                             : String(localized: "Nunsseop is up to date"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Now") { updates.check() }.disabled(updates.isChecking)
                    }
                }
                Text("Version \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Display") {
                Picker("Show on", selection: $settings.displayName) {
                    Text("Automatic (built-in display first)").tag("")
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !settings.displayName.isEmpty && !NSScreen.screens.contains(where: { $0.localizedName == settings.displayName }) {
                        Text(settings.displayName).tag(settings.displayName)
                    }
                }
                Toggle("Show the notch when the MacBook lid is closed", isOn: $settings.showInClamshell)
                Text("In clamshell mode the notch appears as a pill on your external display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Size") {
                SliderRow(title: "Expanded width", value: $settings.expandedWidth,
                          range: AppSettings.expandedWidthRange, unit: "pt")
                SliderRow(title: "Expanded height", value: $settings.expandedHeight,
                          range: AppSettings.expandedHeightRange, unit: "pt")
                SliderRow(title: "Collapsed width on screens without a notch", value: $settings.pillWidth,
                          range: AppSettings.pillWidthRange, unit: "pt")
                Toggle("Compact artwork and visualizer while playing", isOn: $settings.compactLiveActivity)
                Button("Reset sizes") { settings.resetSizes() }
            }
            Section("Behavior") {
                SliderRow(title: "Delay before opening on hover", value: $settings.openDelay,
                          range: 0...1, unit: String(localized: "sec"), format: "%.1f")
                Toggle("Swipe down on the notch to open, up to close", isOn: $settings.swipeToOpen)
                Toggle("Swipe left or right on the Home tab to skip tracks", isOn: $settings.swipeForTracks)
            }
        }
        .formStyle(.grouped)
    }
}

/// What the notch shows: which tabs and in what order, the header, and the collapsed notch.
private struct LayoutPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TabRow(tab: .home, settings: settings, canMoveUp: false, canMoveDown: false)
                let tabs = settings.orderedTabs
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    TabRow(tab: tab, settings: settings, canMoveUp: index > 0, canMoveDown: index < tabs.count - 1)
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Turned-off tabs disappear from the notch and stop running in the background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Home tab") {
                Toggle("Calendar", isOn: $settings.calendarEnabled)
                Toggle("Reminders", isOn: $settings.remindersEnabled)
                    .disabled(!settings.calendarEnabled)
            }
            Section("Header") {
                Toggle("Date", isOn: $settings.headerDate)
                Toggle("Weather", isOn: $settings.headerWeather)
                Toggle("Battery", isOn: $settings.batteryInHeader)
            }
            Section("Collapsed notch") {
                Toggle("Artwork and visualizer while music plays", isOn: $settings.collapsedMusic)
                Toggle("Time left while a timer runs", isOn: $settings.collapsedTimer)
                Toggle("Title under the notch when the track changes", isOn: $settings.sneakPeekEnabled)
                Toggle("Always show the title while something is playing", isOn: $settings.sneakPeekAlways)
                    .disabled(!settings.sneakPeekEnabled)
                SliderRow(title: "Duration", value: $settings.sneakPeekDuration,
                          range: 1...10, unit: String(localized: "sec"), format: "%.1f")
                    .disabled(!settings.sneakPeekEnabled || settings.sneakPeekAlways)
                Toggle("Current lyric under the notch while playing", isOn: $settings.lyricsUnderNotch)
                    .disabled(!settings.lyricsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TabRow: View {
    let tab: NotchTab
    @ObservedObject var settings: AppSettings
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.symbol).frame(width: 20).foregroundStyle(.secondary)
            Text(tab.title)
            Spacer()
            if tab != .home {
                Button { settings.moveTab(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(!canMoveUp)
                    .help(Text("Move up"))
                Button { settings.moveTab(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(!canMoveDown)
                    .help(Text("Move down"))
            }
            Toggle("", isOn: Binding(get: { settings.isVisible(tab) }, set: { settings.setVisible(tab, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(tab == .home)
        }
    }
}

/// Pop-ups the notch can show.
private struct AlertsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Volume and brightness") {
                Toggle("Show volume changes in the notch", isOn: $settings.volumeHUDEnabled)
                Toggle("Replace the system volume and brightness HUD", isOn: $settings.replaceSystemHUD)
                if settings.replaceSystemHUD && !MediaKeyInterceptor.isTrusted {
                    Text("Allow Nunsseop in System Settings › Privacy & Security › Accessibility, then relaunch Nunsseop.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Brightness keys adjust the display under the pointer, including external displays that support DDC. Keyboard backlight keys work on keyboards that have them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Power and devices") {
                Toggle("Show when power is connected or disconnected", isOn: $settings.chargingHUDEnabled)
                Toggle("Warn at 20% battery and when fully charged", isOn: $settings.batteryAlerts)
                Toggle("Show headphone battery when they connect", isOn: $settings.headphoneHUDEnabled)
                Toggle("Show Caps Lock changes", isOn: $settings.capsLockHUD)
                Toggle("Show mouse and keyboard batteries and warn when low", isOn: $settings.peripheralBatteries)
            }
            Section("Privacy") {
                Toggle("Show when an app uses the camera or microphone", isOn: $settings.privacyIndicator)
            }
            Section("Files") {
                Toggle("Add new screenshots to the shelf", isOn: $settings.screenshotsToShelf)
                Toggle("Show when downloads start and finish", isOn: $settings.downloadAlerts)
                Toggle("Add finished downloads to the shelf", isOn: $settings.downloadsToShelf)
            }
            Section("Notifications from local tools") {
                Toggle("Let tools on this Mac show notifications in the notch", isOn: $settings.localNotifications)
                Text("Used by Claude Code hooks and scripts. Only requests from this Mac with the secret token are accepted.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copy Claude Code hook command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(NotifyServer.hookCommand, forType: .string)
                }
                .disabled(!settings.localNotifications)
            }
        }
        .formStyle(.grouped)
    }
}

/// Features that use the network, the camera or other apps' data.
private struct ServicesPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Lyrics") {
                Toggle("Show synced lyrics (from LRCLIB)", isOn: $settings.lyricsEnabled)
            }
            Section("Weather") {
                TextField("Weather city (e.g. Seoul)", text: $settings.weatherCity)
                Text("Weather comes from Open-Meteo. Leave the city empty to hide it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Quick search") {
                Toggle("Open Search with ⌃⌥Space from anywhere", isOn: $settings.searchHotkey)
            }
            Section("Screen recording") {
                Toggle("Record microphone audio", isOn: $settings.recordAudio)
                Text("Recordings are saved where screenshots go and added to the shelf. Screen Recording permission is needed the first time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mirror") {
                Picker("Camera", selection: $settings.mirrorCameraID) {
                    Text("System default").tag("")
                    ForEach(MirrorModel.cameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(camera.uniqueID)
                    }
                }
                .disabled(!settings.mirrorEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var format = "%.0f"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value) + " " + unit).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
