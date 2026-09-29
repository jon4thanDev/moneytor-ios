import SwiftUI

/// The assistant's mark: a glowing multicolor orb. Spins while the assistant is working.
struct AIIcon: View {
    var size: CGFloat = 24
    var isAnimating = false

    private static let colors: [Color] = [.purple, .blue, .cyan, .mint, .yellow, .orange, .pink, .purple]

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let angle = Angle.degrees(isAnimating ? timeline.date.timeIntervalSinceReferenceDate * 240 : 0)
            let gradient = AngularGradient(colors: Self.colors, center: .center, angle: angle)

            ZStack {
                Circle()
                    .fill(gradient)
                    .blur(radius: size * 0.18)
                    .opacity(0.55)
                Circle()
                    .strokeBorder(gradient, lineWidth: size * 0.14)
                Circle()
                    .fill(gradient)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .blur(radius: size * 0.03)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}
