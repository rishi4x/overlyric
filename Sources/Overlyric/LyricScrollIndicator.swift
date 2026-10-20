import SwiftUI
import LyricsCore

/// A floating handle with no track or reserved gutter. Its parent is above lyric masks and chrome.
struct LyricScrollIndicator: View {
    let metrics: LyricScrollMetrics
    let onScroll: (Double) -> Void
    let onInteraction: (Bool) -> Void
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height)
            let thumbHeight = metrics.thumbHeight(in: height)
            let travel = max(0, height - thumbHeight)
            Capsule()
                .fill(.white.opacity(dragStart == nil ? 0.48 : 0.8))
                .frame(width: 4, height: thumbHeight)
                .frame(maxWidth: .infinity)
                .offset(y: travel * metrics.progress)
                .frame(width: geometry.size.width, height: height, alignment: .top)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { event in
                        if dragStart == nil {
                            let thumbTop = travel * metrics.progress
                            let grabbedThumb = event.startLocation.y >= thumbTop && event.startLocation.y <= thumbTop + thumbHeight
                            dragStart = grabbedThumb ? metrics.progress : max(0, min(1, (event.startLocation.y - thumbHeight / 2) / max(1, travel)))
                            onInteraction(true)
                        }
                        let progress = (dragStart ?? metrics.progress) + event.translation.height / max(1, travel)
                        onScroll(metrics.offset(at: progress))
                    }
                    .onEnded { _ in dragStart = nil; onInteraction(false) })
                .accessibilityElement()
                .accessibilityLabel("Scroll lyrics")
                .accessibilityValue("\(Int(metrics.progress * 100)) percent")
                .accessibilityAdjustableAction { direction in
                    onInteraction(true)
                    switch direction {
                    case .increment: onScroll(min(metrics.maximumOffset, metrics.offset + metrics.viewportHeight * 0.6))
                    case .decrement: onScroll(max(0, metrics.offset - metrics.viewportHeight * 0.6))
                    @unknown default: break
                    }
                    onInteraction(false)
                }
        }
    }
}

struct FollowLyricsButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background { background }
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    @ViewBuilder private var background: some View {
        if #available(macOS 26, *) {
            Capsule().fill(.thickMaterial)
                .glassEffect(.regular, in: Capsule())
                .overlay { Capsule().fill(tint.opacity(0.14)) }
        } else {
            Capsule().fill(.thickMaterial)
                .overlay { Capsule().fill(tint.opacity(0.14)) }
        }
    }
}
