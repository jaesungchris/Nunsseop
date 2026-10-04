import AppKit
import SwiftUI

/// The apps pinned to the Dock, followed by its recent apps, ready to launch from the notch.
@MainActor
final class AppLauncher: ObservableObject {
    struct App: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let name: String
    }

    @Published private(set) var apps: [App] = []

    func reload() {
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let entries = (dock?.array(forKey: "persistent-apps") ?? []) + (dock?.array(forKey: "recent-apps") ?? [])
        var seen = Set<URL>()
        apps = entries.compactMap { entry -> App? in
            guard let tile = (entry as? [String: Any])?["tile-data"] as? [String: Any],
                  let file = tile["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String else { return nil }
            let url = string.hasPrefix("file://") ? URL(string: string) : URL(fileURLWithPath: string)
            guard let url, url.pathExtension == "app", FileManager.default.fileExists(atPath: url.path),
                  seen.insert(url).inserted else { return nil }
            return App(url: url, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
    }

    func open(_ app: App) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct AppsTab: View {
    @ObservedObject var launcher: AppLauncher

    var body: some View {
        Group {
            if launcher.apps.isEmpty {
                Text("Apps in your Dock show up here")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 8) {
                        ForEach(launcher.apps) { app in
                            AppIcon(app: app) { launcher.open(app) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { launcher.reload() }
    }
}

private struct AppIcon: View {
    let app: AppLauncher.App
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .scaleEffect(hovering ? 1.1 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
                Text(app.name).font(.system(size: 9)).lineLimit(1).foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(app.name)
    }
}
