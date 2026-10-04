import SwiftUI

/// A single scratch note saved to Application Support.
@MainActor
final class NotesModel: ObservableObject {
    @Published var text: String { didSet { scheduleSave() } }
    private let url: URL
    private var saveWork: DispatchWorkItem?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appendingPathComponent("Nunsseop/notes.txt")
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let text = text, url = url
        let work = DispatchWorkItem {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}

struct NotesTab: View {
    @ObservedObject var notes: NotesModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05))
            if notes.text.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $notes.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 8)
        }
    }
}
