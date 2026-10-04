import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    let isDropTargeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.white.opacity(isDropTargeted ? 0.9 : 0.25))
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isDropTargeted ? 0.12 : 0.04)))

            if shelf.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 18))
                    Text("Drop files here").font(.system(size: 11))
                }
                .foregroundStyle(.white.opacity(0.55))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item) { shelf.remove(item) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .contextMenu {
            if !shelf.items.isEmpty {
                Button("Clear Shelf") { shelf.removeAll() }
            }
            Button("Quit Nunsseop") { NSApp.terminate(nil) }
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(item.url.lastPathComponent)
                .font(.system(size: 9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.12 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Remove from Shelf", action: onRemove)
        }
        .help(item.url.path)
    }
}

extension ShelfStore {
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self.add([url]) }
            }
        }
        return true
    }
}
