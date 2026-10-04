import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    nonisolated static let expandedWidthRange: ClosedRange<Double> = 520...780
    nonisolated static let expandedHeightRange: ClosedRange<Double> = 170...260
    nonisolated static let pillWidthRange: ClosedRange<Double> = 140...320

    private let defaults = UserDefaults.standard

    @Published var expandedWidth: Double { didSet { defaults.set(expandedWidth, forKey: "expandedWidth") } }
    @Published var expandedHeight: Double { didSet { defaults.set(expandedHeight, forKey: "expandedHeight") } }
    /// Width of the collapsed shape on screens without a camera housing.
    @Published var pillWidth: Double { didSet { defaults.set(pillWidth, forKey: "pillWidth") } }
    /// Smaller artwork/visualizer "ears" beside the collapsed notch while music plays.
    @Published var compactLiveActivity: Bool { didSet { defaults.set(compactLiveActivity, forKey: "compactLiveActivity") } }

    private init() {
        defaults.register(defaults: [
            "expandedWidth": 620.0,
            "expandedHeight": 196.0,
            "pillWidth": 190.0,
            "compactLiveActivity": false,
        ])
        expandedWidth = defaults.double(forKey: "expandedWidth")
        expandedHeight = defaults.double(forKey: "expandedHeight")
        pillWidth = defaults.double(forKey: "pillWidth")
        compactLiveActivity = defaults.bool(forKey: "compactLiveActivity")
    }

    func resetSizes() {
        expandedWidth = 620
        expandedHeight = 196
        pillWidth = 190
        compactLiveActivity = false
    }
}
