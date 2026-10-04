import AppKit

struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var collapsedSize: CGSize
    var hasNotch: Bool

    static let expandedSize = CGSize(width: 640, height: 190)

    /// Prefers the built-in display with a camera housing; otherwise the main screen.
    static func pickScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            collapsedSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            hasNotch = true
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            collapsedSize = CGSize(width: 190, height: max(menuBarHeight, 24))
            hasNotch = false
        }
    }

    /// The panel stays at the expanded size; only the drawn shape changes.
    var panelFrame: NSRect {
        let size = CGSize(width: Self.expandedSize.width + 40, height: Self.expandedSize.height + 20)
        return NSRect(x: screenFrame.midX - size.width / 2,
                      y: screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    func shapeRect(size: CGSize) -> NSRect {
        NSRect(x: screenFrame.midX - size.width / 2,
                      y: screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }
}
