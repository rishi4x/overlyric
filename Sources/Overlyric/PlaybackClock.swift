import SwiftUI

/// Frequent progress updates are observed by playback controls, not the entire lyric panel.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var position = 0.0
}
