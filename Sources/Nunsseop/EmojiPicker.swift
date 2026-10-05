import AppKit
import SwiftUI

/// Every fully-qualified single-scalar emoji, searchable by its Unicode name.
@MainActor
final class EmojiModel: ObservableObject {
    struct Emoji: Identifiable, Hashable {
        var id: String { character }
        let character: String
        let name: String
    }

    @Published private(set) var recents: [String]
    private let defaults = UserDefaults.standard

    static let all: [Emoji] = {
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF,
                                            0x1FA70...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF]
        return ranges.flatMap { $0 }.compactMap { value -> Emoji? in
            guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                  let name = scalar.properties.name else { return nil }
            return Emoji(character: String(Character(scalar)), name: name.lowercased())
        }
    }()

    init() {
        recents = defaults.stringArray(forKey: "emojiRecents") ?? []
    }

    func results(for query: String) -> [Emoji] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            let recent = recents.compactMap { r in Self.all.first { $0.character == r } }
            return recent + Self.all.filter { !recents.contains($0.character) }
        }
        return Self.all.filter { $0.name.contains(q) }
    }

    func copy(_ emoji: Emoji) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(emoji.character, forType: .string)
        recents.removeAll { $0 == emoji.character }
        recents.insert(emoji.character, at: 0)
        if recents.count > 18 { recents.removeLast(recents.count - 18) }
        defaults.set(recents, forKey: "emojiRecents")
    }
}

struct EmojiTab: View {
    @ObservedObject var model: EmojiModel
    @State private var query = ""
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                TextField("Search emoji (English names)", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if let copied {
                    Text("Copied \(copied)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 10).frame(height: 26)
            .surface(Capsule(), opacity: 0.08)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 4)], spacing: 4) {
                    ForEach(model.results(for: query)) { emoji in
                        Button {
                            model.copy(emoji)
                            copied = emoji.character
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == emoji.character { copied = nil } }
                        } label: {
                            Text(emoji.character).font(.system(size: 20)).frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .help(emoji.name)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}
