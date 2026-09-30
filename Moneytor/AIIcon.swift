import SwiftUI

/// The assistant's mark: a rounded diamond in a green-to-purple gradient with a four-point sparkle
/// cut out of it. The gradient turns while the assistant is working.
struct AIIcon: View {
    var size: CGFloat = 24
    var isAnimating = false

    static let colors: [Color] = [
        Color(red: 0.36, green: 0.89, blue: 0.56),
        Color(red: 0.38, green: 0.80, blue: 0.98),
        Color(red: 0.78, green: 0.36, blue: 0.96),
    ]

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            // Starts from the top-left corner, like the resting mark, and turns a full circle every 2 seconds.
            let angle = (isAnimating ? timeline.date.timeIntervalSinceReferenceDate * .pi : 0) + .pi * 1.25
            let start = UnitPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle))
            let end = UnitPoint(x: 1 - start.x, y: 1 - start.y)

            SparkleDiamond()
                .fill(LinearGradient(colors: Self.colors, startPoint: start, endPoint: end), style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// A rounded square turned 45°, with a concave four-point star in the middle.
/// Filled even-odd, the star becomes a see-through cutout.
private struct SparkleDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // A square of 0.74 × side turned 45° spans about 0.92 × side once its corners are rounded.
        let squareSide = side * 0.74
        let square = CGRect(x: center.x - squareSide / 2, y: center.y - squareSide / 2, width: squareSide, height: squareSide)
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: .pi / 4).translatedBy(x: -center.x, y: -center.y)
        var path = Path(roundedRect: square, cornerRadius: squareSide * 0.24, style: .continuous).applying(turn)

        // Each side of the star curves toward the center, which gives the thin sparkle points.
        let reach = side * 0.38
        let pull = reach * 0.14
        let top = CGPoint(x: center.x, y: center.y - reach)
        let right = CGPoint(x: center.x + reach, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + reach)
        let left = CGPoint(x: center.x - reach, y: center.y)
        path.move(to: top)
        path.addQuadCurve(to: right, control: CGPoint(x: center.x + pull, y: center.y - pull))
        path.addQuadCurve(to: bottom, control: CGPoint(x: center.x + pull, y: center.y + pull))
        path.addQuadCurve(to: left, control: CGPoint(x: center.x - pull, y: center.y + pull))
        path.addQuadCurve(to: top, control: CGPoint(x: center.x - pull, y: center.y - pull))
        path.closeSubpath()
        return path
    }
}
