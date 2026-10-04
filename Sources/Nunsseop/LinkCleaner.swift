import Foundation

/// Removes well-known tracking parameters from a copied link.
enum LinkCleaner {
    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid",
        "ref_src", "_hsenc", "_hsmi", "yclid", "twclid",
    ]
    /// `si` is only a tracking parameter on these sites; elsewhere it can carry meaning.
    private static let shareIDHosts = ["youtube.com", "youtu.be", "open.spotify.com"]

    /// The cleaned link, or nil when `text` is not a single http(s) URL or has nothing to remove.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty,
              let items = components.percentEncodedQueryItems, !items.isEmpty else { return nil }
        let stripsShareID = shareIDHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !(name.hasPrefix("utm_") || trackingNames.contains(name) || (stripsShareID && name == "si"))
        }
        guard kept.count < items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string
    }
}
