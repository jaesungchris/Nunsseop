import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
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
            Section("Home") {
                Toggle("Show calendar on the Home tab", isOn: $settings.calendarEnabled)
                Toggle("Show reminders under the calendar", isOn: $settings.remindersEnabled)
                    .disabled(!settings.calendarEnabled)
                Toggle("Show the Timer tab", isOn: $settings.timerTab)
                Toggle("Show the Clipboard tab and keep clipboard history", isOn: $settings.clipboardTab)
                Toggle("Show the Notes tab", isOn: $settings.notesTab)
                Toggle("Show the Tools tab", isOn: $settings.toolsTab)
                Toggle("Show the Mirror tab", isOn: $settings.mirrorEnabled)
                Picker("Camera", selection: $settings.mirrorCameraID) {
                    Text("System default").tag("")
                    ForEach(MirrorModel.cameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(camera.uniqueID)
                    }
                }
                .disabled(!settings.mirrorEnabled)
            }
            Section("System HUD") {
                Toggle("Show volume changes in the notch", isOn: $settings.volumeHUDEnabled)
                Toggle("Replace the system volume and brightness HUD", isOn: $settings.replaceSystemHUD)
                if settings.replaceSystemHUD && !MediaKeyInterceptor.isTrusted {
                    Text("Allow Nunsseop in System Settings › Privacy & Security › Accessibility, then relaunch Nunsseop.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Brightness keys adjust the display under the pointer, including external displays that support DDC. Keyboard backlight keys work on keyboards that have them.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show battery level in the header", isOn: $settings.batteryInHeader)
                Toggle("Show when power is connected or disconnected", isOn: $settings.chargingHUDEnabled)
                Toggle("Show headphone battery when they connect", isOn: $settings.headphoneHUDEnabled)
                Toggle("Warn at 20% battery and when fully charged", isOn: $settings.batteryAlerts)
                Toggle("Show Caps Lock changes", isOn: $settings.capsLockHUD)
                Toggle("Add new screenshots to the shelf", isOn: $settings.screenshotsToShelf)
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
            Section("Sneak Peek") {
                Toggle("Show the title under the notch when the track or play state changes", isOn: $settings.sneakPeekEnabled)
                Toggle("Always show while something is playing", isOn: $settings.sneakPeekAlways)
                    .disabled(!settings.sneakPeekEnabled)
                SliderRow(title: "Duration", value: $settings.sneakPeekDuration,
                          range: 1...10, unit: String(localized: "sec"), format: "%.1f")
                    .disabled(!settings.sneakPeekEnabled || settings.sneakPeekAlways)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
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
