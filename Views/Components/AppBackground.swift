import SwiftUI

// MARK: - App Background

/// The themed screen background: dark base with the purple/teal glow. Fills
/// the whole screen, behind the safe areas, on every iPhone size (sizes are
/// relative to the screen, nothing is an image, so nothing stretches or crops).
///
/// The glow drifts very slowly; it stays still when Reduce Motion is on.
struct AppBackground: View {

    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)

            ZStack {
                AppTheme.base

                glow(AppTheme.purple, opacity: 0.28, diameter: size * 0.95)
                    .position(
                        x: geo.size.width * (drift ? 0.32 : 0.18),
                        y: geo.size.height * (drift ? 0.14 : 0.06)
                    )

                glow(AppTheme.teal, opacity: 0.16, diameter: size * 0.8)
                    .position(
                        x: geo.size.width * (drift ? 0.72 : 0.9),
                        y: geo.size.height * (drift ? 0.48 : 0.38)
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: startDrift)
        .onChange(of: reduceMotion) { _, reduce in
            if reduce {
                withAnimation(.easeOut(duration: 0.6)) { drift = false }
            } else {
                startDrift()
            }
        }
    }

    private func glow(_ color: Color, opacity: Double, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
    }

    private func startDrift() {
        guard animated, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
            drift = true
        }
    }
}
