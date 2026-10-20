import SwiftUI

struct PlaybackFooter: View {
    @ObservedObject var player: PlayerModel
    @ObservedObject var clock: PlaybackClock
    @Binding var scrubbing: Bool
    @Binding var scrubPosition: Double

    var body: some View {
        VStack(spacing: 10) {
            if let error = player.controlError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
            }
            HStack(spacing: 8) {
                Text(time(scrubbing ? scrubPosition : clock.position))
                PlaybackScrubber(value: clock.position, duration: player.track?.duration ?? 0, accent: player.accent,
                    onPreview: { preview in
                        scrubbing = preview != nil
                        if let preview { scrubPosition = preview }
                    }, onSeek: player.seek)
                Text(time(player.track?.duration ?? 0))
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 22) {
                icon("backward.end.fill", label: "Previous track") { player.command("previous track") }
                icon("gobackward.10", label: "Rewind 10 seconds") { player.seek(clock.position - 10) }
                    .font(.system(size: 18))
                icon(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play") {
                    player.command("playpause")
                }.font(.system(size: 20))
                icon("goforward.10", label: "Forward 10 seconds") { player.seek(clock.position + 10) }
                    .font(.system(size: 18))
                icon("forward.end.fill", label: "Next track") { player.command("next track") }
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
        }.disabled(player.track == nil || player.connectionError != nil)
    }

    private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(minWidth: 18, minHeight: 22).contentShape(Rectangle()) }
            .buttonStyle(.plain).focusable(false).focusEffectDisabled().help(label).accessibilityLabel(label)
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
