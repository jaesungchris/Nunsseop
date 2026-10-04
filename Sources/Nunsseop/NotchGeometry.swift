import AppKit
import IOKit

struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var collapsedSize: CGSize
    var hasNotch: Bool

    /// True while a MacBook's lid is closed (clamshell mode with an external display).
    static var lidIsClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }

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

    /// Debug builds can pretend a display has a notch of this width with `--fake-notch <points>`.
    private static let fakeNotchWidth: CGFloat = {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--fake-notch"), i + 1 < CommandLine.arguments.count,
           let width = Double(CommandLine.arguments[i + 1]) { return width }
        #endif
        return 0
    }()

    init(screen: NSScreen, pillWidth: CGFloat) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // The shape's top corners flare outward, so widen it to keep the body as wide as the housing.
            let width = screen.frame.width - left.width - right.width + 12
            collapsedSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            hasNotch = true
        } else if Self.fakeNotchWidth > 0 {
            collapsedSize = CGSize(width: Self.fakeNotchWidth, height: 32)
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
