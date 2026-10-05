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
            return App(url: url, name: InstalledApps.name(at: url))
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

/// Name and icon of installed apps. Finding an app by bundle ID and loading its icon is slow enough
/// to matter in a view body, so apps that were found are remembered; missing ones are looked up again.
enum InstalledApps {
    private static let urls = NSCache<NSString, NSURL>()
    private static let icons = NSCache<NSString, NSImage>()

    static func url(for bundleID: String) -> URL? {
        // A cached location is dropped if the app has since moved or been removed.
        if let url = urls.object(forKey: bundleID as NSString) as URL?, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        urls.setObject(url as NSURL, forKey: bundleID as NSString)
        return url
    }

    static func name(at url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(at url: URL) -> NSImage {
        if let icon = icons.object(forKey: url.path as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: url.path as NSString)
        return icon
    }

    static func icon(for bundleID: String) -> NSImage? { url(for: bundleID).map(icon(at:)) }
}
