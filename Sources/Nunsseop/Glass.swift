import SwiftUI

private struct LiquidGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether surfaces use Liquid Glass. Only honoured on macOS 26 and later.
    var liquidGlass: Bool {
        get { self[LiquidGlassKey.self] }
        set { self[LiquidGlassKey.self] = newValue }
    }
}

enum LiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

private struct SurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.liquidGlass) private var glass
    let shape: S
    let opacity: Double

    func body(content: Content) -> some View {
        if glass, #available(macOS 26, *) {
            content.glassEffect(.regular.tint(.white.opacity(opacity * 0.5)), in: shape)
        } else {
            content.background(shape.fill(.white.opacity(opacity)))
        }
    }
}

extension View {
    /// A card or field surface: Liquid Glass when it is turned on, otherwise a faint fill.
    func surface<S: Shape>(_ shape: S, opacity: Double = 0.06) -> some View {
        modifier(SurfaceModifier(shape: shape, opacity: opacity))
    }
}

/// The notch body. With Liquid Glass the expanded notch turns into dark glass below the camera,
/// while the band beside the camera stays black so it still merges with the housing.
/// The collapsed eyebrow on a display without a notch is glass too, since it has no housing to merge with.
struct NotchBackground<S: Shape>: View {
    let shape: S
    let glass: Bool
    /// Opacity of the black tint over the glass: higher is darker.
    let tint: Double
    let expanded: Bool
    let notchHeight: CGFloat
    /// The collapsed shape floats on its own, on a display without a notch.
    var floatingPill = false

    /// Glass only while there's something to see through: a full tint is solid black, with no glass edges left.
    /// Compared as the slider shows it (whole percents), so a thumb left at 99.6, which reads "100 %", is solid too.
    static func showsGlass(glass: Bool, tint: Double, expanded: Bool, floatingPill: Bool) -> Bool {
        glass && (tint * 100).rounded() < 100 && (expanded || floatingPill)
    }

    var body: some View {
        if Self.showsGlass(glass: glass, tint: tint, expanded: expanded, floatingPill: floatingPill), #available(macOS 26, *) {
            ZStack(alignment: .top) {
                Color.clear.glassEffect(.regular.tint(.black.opacity(tint)), in: shape)
                if expanded {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .black.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: notchHeight + 28)
                }
            }
        } else {
            shape.fill(Color.black)
        }
    }
}
