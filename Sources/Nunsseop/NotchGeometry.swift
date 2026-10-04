import AppKit

struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var collapsedSize: CGSize
    var hasNotch: Bool

    /// The display named in settings if it is connected; otherwise the built-in display
    /// with a camera housing, then the main screen.
    static func pickScreen(preferredName: String = "") -> NSScreen? {
        if !preferredName.isEmpty, let match = NSScreen.screens.first(where: { $0.localizedName == preferredName }) {
            return match
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Used only when no screen is attached at launch; the next screen change relayouts.
    init(fallbackWidth: CGFloat) {
        screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        collapsedSize = CGSize(width: fallbackWidth, height: 24)
        hasNotch = false
    }

    init(screen: NSScreen, pillWidth: CGFloat) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // The shape's top corners flare outward, so widen it to keep the body as wide as the housing.
            let width = screen.frame.width - left.width - right.width + 12
            collapsedSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            hasNotch = true
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            collapsedSize = CGSize(width: pillWidth, height: max(menuBarHeight, 24))
            hasNotch = false
        }
    }

    /// The panel is sized for the largest allowed shape; only the drawn shape changes.
    var panelFrame: NSRect {
        let size = CGSize(width: AppSettings.expandedWidthRange.upperBound + 40,
                          height: AppSettings.expandedHeightRange.upperBound + 20)
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
