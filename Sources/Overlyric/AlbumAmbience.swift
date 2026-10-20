import SwiftUI

/// Broad, low-contrast color fields fade across the edges of the panel.
struct AlbumAmbience: View {
    let artwork: NSImage?
    let accent: Color
    let playing: Bool
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.28)
                if enabled && artwork != nil {
                    if playing && !reduceMotion {
                        glow(size: geometry.size)
                            .phaseAnimator([false, true]) { content, phase in
                                content
                                    .scaleEffect(phase ? 1.04 : 1, anchor: .bottomTrailing)
                                    .rotationEffect(.degrees(phase ? 3 : -3), anchor: .bottomTrailing)
                                    .offset(x: phase ? 6 : -6, y: phase ? -8 : 4)
                            } animation: { _ in .easeInOut(duration: 26) }
                    } else {
                        glow(size: geometry.size)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: accent)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(size: CGSize) -> some View {
        let spread = max(size.width, size.height)
        return ZStack {
            RadialGradient(stops: [
                .init(color: accent.opacity(0.18), location: 0),
                .init(color: accent.opacity(0.09), location: 0.35),
                .init(color: accent.opacity(0.025), location: 0.72),
                .init(color: .clear, location: 1)
            ], center: UnitPoint(x: 1.02, y: 1.03), startRadius: 0, endRadius: spread * 1.05)
            RadialGradient(stops: [
                .init(color: accent.opacity(0.085), location: 0),
                .init(color: accent.opacity(0.035), location: 0.45),
                .init(color: .clear, location: 1)
            ], center: UnitPoint(x: 0.18, y: -0.12), startRadius: 0, endRadius: spread * 0.85)
        }
        .frame(width: size.width, height: size.height)
        .blur(radius: 40)
    }
}
