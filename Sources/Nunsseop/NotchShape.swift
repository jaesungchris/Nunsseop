import SwiftUI

/// Black housing that hangs from the top edge: small outward flares at the top
/// corners, larger rounded corners at the bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Rounds all four corners, the top ones by `topRadius`, for a shape that does not touch the top edge.
    var floating = false

    /// With `floating`, how far the body is pulled in from each side, as the flared top corners do for the camera housing.
    var sideInset: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(topRadius, AnimatablePair(bottomRadius, sideInset)) }
        set { topRadius = newValue.first; bottomRadius = newValue.second.first; sideInset = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        if floating {
            let rect = rect.insetBy(dx: sideInset, dy: 0)
            let limit = min(rect.height / 2, rect.width / 2)
            let top = min(topRadius, limit), bottom = min(bottomRadius, limit)
            return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top), style: .continuous)
        }
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, rect.height / 2, rect.width / 4)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
