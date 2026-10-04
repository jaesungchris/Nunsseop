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
            window.title = "NotchApp 설정"
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
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section("일반") {
                Toggle("로그인 시 NotchApp 실행", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.needsApproval {
                    Text("시스템 설정 › 일반 › 로그인 항목에서 NotchApp을 허용해야 합니다.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !launchAtLogin.isInApplicationsFolder {
                    Text("앱을 /Applications로 옮긴 뒤 켜는 것을 권장합니다. 지금 위치: \(Bundle.main.bundlePath)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("크기") {
                SliderRow(title: "펼친 너비", value: $settings.expandedWidth,
                          range: AppSettings.expandedWidthRange, unit: "pt")
                SliderRow(title: "펼친 높이", value: $settings.expandedHeight,
                          range: AppSettings.expandedHeightRange, unit: "pt")
                SliderRow(title: "노치 없는 화면의 접힌 너비", value: $settings.pillWidth,
                          range: AppSettings.pillWidthRange, unit: "pt")
                Toggle("재생 중 접힌 노치 양옆을 작게", isOn: $settings.compactLiveActivity)
                Button("크기 기본값으로") { settings.resetSizes() }
            }
            Section("동작") {
                SliderRow(title: "마우스를 올린 뒤 펼치기까지", value: $settings.openDelay,
                          range: 0...1, unit: "초", format: "%.1f")
            }
            Section("미리보기") {
                Toggle("곡이나 재생 상태가 바뀌면 노치 아래에 제목 표시", isOn: $settings.sneakPeekEnabled)
                Toggle("재생 정보가 있으면 항상 표시", isOn: $settings.sneakPeekAlways)
                    .disabled(!settings.sneakPeekEnabled)
                SliderRow(title: "표시 시간", value: $settings.sneakPeekDuration,
                          range: 1...10, unit: "초", format: "%.1f")
                    .disabled(!settings.sneakPeekEnabled || settings.sneakPeekAlways)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
    }
}

private struct SliderRow: View {
    let title: String
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
