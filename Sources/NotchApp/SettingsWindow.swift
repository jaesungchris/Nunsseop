import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
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

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) \(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
