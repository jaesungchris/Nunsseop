import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Evaluates arithmetic such as `12*(3+4)/2`, `2^10` or `15%`. Returns nil for anything else.
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        let text = input.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
        guard !text.isEmpty, text.contains(where: { "+-*/^%(".contains($0) }) || text.hasSuffix("%"),
              text.allSatisfy({ "0123456789.+-*/^%()".contains($0) }) else { return nil }
        var parser = Parser(chars: Array(text))
        guard let value = parser.expression(), parser.index == parser.chars.count, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        mutating func peek() -> Character? { index < chars.count ? chars[index] : nil }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                index += 1
                guard let rhs = power() else { return nil }
                value = op == "*" ? value * rhs : value / rhs
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if peek() == "^" {
                index += 1
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func unary() -> Double? {
            if peek() == "-" { index += 1; return unary().map { -$0 } }
            if peek() == "+" { index += 1; return unary() }
            guard var value = primary() else { return nil }
            if peek() == "%" { index += 1; value /= 100 }
            return value
        }

        mutating func primary() -> Double? {
            if peek() == "(" {
                index += 1
                let value = expression()
                guard peek() == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while let c = peek(), c.isNumber || c == "." { index += 1 }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}

@MainActor
final class QuickSearchModel: ObservableObject {
    struct AppItem: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let name: String
    }

    @Published var query = ""
    @Published var focusToken = 0
    private(set) var apps: [AppItem] = []

    func loadApps() {
        guard apps.isEmpty else { return }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        var seen = Set<String>()
        apps = folders.flatMap { folder -> [AppItem] in
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "app" }.compactMap { url in
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                return seen.insert(name).inserted ? AppItem(url: url, name: name) : nil
            }
        }
    }

    var calculation: Double? { Calculator.evaluate(query) }

    var matchingApps: [AppItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { ($0.name.lowercased().hasPrefix(q.lowercased()) ? 0 : 1, $0.name) < ($1.name.lowercased().hasPrefix(q.lowercased()) ? 0 : 1, $1.name) }
            .prefix(6))
    }

    func open(_ app: AppItem) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        query = ""
    }

    func searchWeb() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, var components = URLComponents(string: "https://www.google.com/search") else { return }
        components.queryItems = [URLQueryItem(name: "q", value: q)]
        if let url = components.url { NSWorkspace.shared.open(url) }
        query = ""
    }

    func copy(_ value: Double) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Calculator.format(value).replacingOccurrences(of: ",", with: ""), forType: .string)
    }

    /// Return: copy the result, open the first app, or search the web.
    func submit() {
        if let value = calculation { copy(value) } else if let app = matchingApps.first { open(app) } else { searchWeb() }
    }
}

struct SearchTab: View {
    @ObservedObject var model: QuickSearchModel
    let shortcut: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                TextField("Search apps, the web, or calculate", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { model.submit() }
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.1)))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    if let value = model.calculation {
                        ResultRow(symbol: "equal.circle.fill", title: Calculator.format(value),
                                  subtitle: String(localized: "Press Return to copy")) { model.copy(value) }
                    }
                    ForEach(model.matchingApps) { app in
                        ResultRow(icon: NSWorkspace.shared.icon(forFile: app.url.path), title: app.name,
                                  subtitle: String(localized: "Open")) { model.open(app) }
                    }
                    if !model.query.trimmingCharacters(in: .whitespaces).isEmpty && model.calculation == nil {
                        ResultRow(symbol: "globe", title: String(localized: "Search the web for “\(model.query)”"),
                                  subtitle: "Google") { model.searchWeb() }
                    }
                    if model.query.isEmpty {
                        Group {
                            if let shortcut {
                                Text("Type an app name, a sum like 12*(3+4), or anything to search the web. Shortcut: \(shortcut)")
                            } else {
                                Text("Type an app name, a sum like 12*(3+4), or anything to search the web.")
                            }
                        }
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            model.loadApps()
            focused = true
        }
        .onChange(of: model.focusToken) { _, _ in focused = true }
    }
}

private struct ResultRow: View {
    var symbol: String?
    var icon: NSImage?
    let title: String
    let subtitle: String
    let action: () -> Void
    @State private var hovering = false

    init(symbol: String, title: String, subtitle: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.title = title; self.subtitle = subtitle; self.action = action
    }

    init(icon: NSImage, title: String, subtitle: String, action: @escaping () -> Void) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 16)).frame(width: 22)
                }
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.12 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Shortcuts offered for opening Search. ⌃⌥Space is also macOS's default for switching input sources.
enum SearchShortcut: String, CaseIterable, Identifiable {
    case shiftCommandSpace, optionSpace, controlOptionSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shiftCommandSpace: return "⇧⌘Space"
        case .optionSpace: return "⌥Space"
        case .controlOptionSpace: return "⌃⌥Space"
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .shiftCommandSpace: return UInt32(shiftKey | cmdKey)
        case .optionSpace: return UInt32(optionKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        }
    }
}

/// A system-wide hotkey through Carbon, which needs no Accessibility permission.
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, context, &handler)
        let id = EventHotKeyID(signature: OSType(0x4E534550), id: 1)
        isRegistered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }

    convenience init(shortcut: SearchShortcut, action: @escaping () -> Void) {
        self.init(keyCode: UInt32(kVK_Space), modifiers: shortcut.modifiers, action: action)
    }
}
