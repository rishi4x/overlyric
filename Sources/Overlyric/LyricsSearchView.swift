import SwiftUI
import LyricsCore

struct LyricsSearchView: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var results: [LyricsRecord] = []
    @State private var loading = true
    @State private var failed = false
    @State private var revision = 0
    @State private var originalTrackID: String?

    init(player: PlayerModel) {
        self.player = player
        _title = State(initialValue: player.track?.title ?? "")
        _artist = State(initialValue: player.track?.artist ?? "")
        _originalTrackID = State(initialValue: player.track?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Find the words").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Search LRCLIB, then NetEase if needed.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .bottom, spacing: 10) {
                searchField("Song title", placeholder: "Enter a song", text: $title)
                searchField("Artist", placeholder: "Optional", text: $artist)
                Button { revision += 1 } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, height: 22)
                }
                    .buttonStyle(FlatButtonStyle(tint: player.accent))
                    .help("Search lyrics").accessibilityLabel("Search lyrics")
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Choose a recording to use for this song. Other versions may have different timing.")
                .font(.caption).foregroundStyle(.secondary)
            if loading {
                ProgressView("Searching lyrics…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 12) {
                    Text(failed ? "The lyrics library is unavailable right now." : "No matching recordings yet.")
                        .foregroundStyle(.secondary)
                    Text("Try a shorter title, another spelling, or leave the artist blank.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).multilineTextAlignment(.center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { record in
                            Button {
                                guard player.track?.id == originalTrackID else { dismiss(); return }
                                player.chooseRecording(record)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.trackName).font(.system(size: 13, weight: .semibold))
                                        Text("\(record.artistName) · \(record.albumName)")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        Text(record.source == .netease ? "NetEase · Select to load lyrics" : "LRCLIB")
                                            .font(.caption2).foregroundStyle(player.accent)
                                    }
                                    Spacer()
                                    let duration = Int(max(0, record.duration))
                                    Text(String(format: "%d:%02d", duration / 60, duration % 60))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.never)
            }
            Text("LRCLIB · NetEase fallback").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24).frame(width: 480, height: 490)
        .preferredColorScheme(.dark)
        .onSubmit { if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { revision += 1 } }
        .task(id: revision) {
            loading = true; failed = false; results = []
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
            do {
                let records = try await player.searchLyrics(title: title, artist: artist)
                guard !Task.isCancelled else { return }
                results = records
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
            loading = false
        }
        .onChange(of: player.track?.id) { _, _ in dismiss() }
    }

    private func searchField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 12).frame(height: 42)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
                .accessibilityLabel(label)
        }.frame(maxWidth: .infinity)
    }
}
