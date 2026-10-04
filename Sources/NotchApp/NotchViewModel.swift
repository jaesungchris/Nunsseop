import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var geometry: NotchGeometry
    @Published private(set) var isExpanded = false

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    var currentSize: CGSize {
        isExpanded ? NotchGeometry.expandedSize : geometry.collapsedSize
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
    }
}
