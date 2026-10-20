import SwiftUI

struct PlaybackScrubber: View {
    let value: Double
    let duration: Double
    let accent: Color
    let onPreview: (Double?) -> Void
    let onSeek: (Double) -> Void
    @State private var hovering = false
    @State private var dragging: Double?

    private var fraction: Double { min(1, max(0, (dragging ?? value) / max(1, duration))) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.24)).frame(height: 5)
                Capsule().fill(accent).frame(width: width * fraction, height: 5)
                if hovering || dragging != nil {
                    Circle().fill(.white).frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: max(0, min(width - 9, width * fraction - 4.5)))
                        .transition(.opacity)
                }
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { event in
                    let target = min(1, max(0, event.location.x / max(1, width))) * max(0, duration)
                    dragging = target
                    onPreview(target)
                }
                .onEnded { event in
                    let target = min(1, max(0, event.location.x / max(1, width))) * max(0, duration)
                    onSeek(target)
                    dragging = nil
                    onPreview(nil)
                })
        }
        .frame(height: 20)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(value)) seconds of \(Int(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(duration, value + 5))
            case .decrement: onSeek(max(0, value - 5))
            @unknown default: break
            }
        }
    }
}
