import AppKit
import Combine

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
}

/// Holds references to dropped files (not copies). Stored as bookmarks so items
/// survive being renamed or moved while the app is not running.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let storeURL: URL

    init(storeURL: URL = ShelfStore.defaultStoreURL) {
        self.storeURL = storeURL
        load()
    }

    nonisolated static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchApp/shelf.json")
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.map { $0.url.standardizedFileURL })
        let fresh = urls
            .filter { $0.isFileURL && !existing.contains($0.standardizedFileURL) }
            .map { ShelfItem(id: UUID(), url: $0) }
        guard !fresh.isEmpty else { return }
        items.append(contentsOf: fresh)
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeAll() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let bookmarks = try? JSONDecoder().decode([Data].self, from: data) else { return }
        items = bookmarks.compactMap { bookmark in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(id: UUID(), url: url)
        }
    }

    private func save() {
        let bookmarks = items.compactMap { try? $0.url.bookmarkData() }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(bookmarks).write(to: storeURL, options: .atomic)
        } catch {
            NSLog("NotchApp: failed to save shelf: \(error)")
        }
    }
}
