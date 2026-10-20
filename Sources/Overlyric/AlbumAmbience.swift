import SwiftUI

/// Sparse artwork hues float over the glass; uncolored regions stay transparent.
struct AlbumAmbience: View {
    let colors: [Color]
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let centers = [UnitPoint(x: 1.02, y: 1.03), UnitPoint(x: -0.12, y: -0.1), UnitPoint(x: 1.2, y: 0.22)]
    private let strengths = [0.2, 0.13, 0.085]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.28)
                if enabled && !colors.isEmpty {
                    ForEach(0..<min(3, max(2, colors.count)), id: \.self) { index in
                        let color = colors[index % colors.count]
                        let strength = strengths[index]
                        RadialGradient(stops: [
                            .init(color: color.opacity(strength), location: 0),
                            .init(color: color.opacity(strength * 0.55), location: 0.35),
                            .init(color: color.opacity(strength * 0.12), location: 0.75),
                            .init(color: .clear, location: 1)
                        ], center: centers[index], startRadius: 0,
                            endRadius: max(geometry.size.width, geometry.size.height) * 1.15)
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: colors)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
