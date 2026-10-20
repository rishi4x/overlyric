import SwiftUI
import LyricsCore

@MainActor
final class PlayerModel: ObservableObject {
    @Published var track: Track?
    @Published var position = 0.0
    @Published var isPlaying = false
    @Published var lines: [LyricLine] = []
    @Published var plainLyrics: String?
    @Published var candidates: [LyricsRecord] = []
    @Published var message = "Play something on Spotify"
    @Published var detail = "Your words will meet you here."
    @Published var loading = false
    @Published var instrumental = false
    @Published var lyricLoadFailed = false
    @Published var connectionError: String?
    @Published var controlError: String?
    @Published var offset = 0.0 {
        didSet { if let track { timing.setOffset(offset, for: track.id) } }
    }
    @Published private(set) var timingAdjustmentCount = 0

    func adjustTiming(by delta: Double) {
        offset += delta
        timingAdjustmentCount += 1
    }

    func resetTiming() {
        offset = 0
        timingAdjustmentCount += 1
    }
    @Published var artwork: NSImage?
    @Published var accent = Color(red: 0.78, green: 0.75, blue: 1)
    private let timing = TimingPreferences()
    private let artworkLoader = ArtworkLoader()
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?
    private let spotify = SpotifyBridge()
    private let lyrics = LyricsClient()
    private var pollTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var lyricRequestID = UUID()
    private var anchorPosition = 0.0
    private var anchorTime = Date()
    private struct PendingSeek {
        let id: UUID
        let trackID: String
        var deadline: Date?
    }
    private var pendingSeek: PendingSeek?
    private var seekRevision = 0

    var activeIndex: Int? { LRC.activeIndex(in: lines, at: position + offset) }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.connectionError == nil { await self.refresh() }
                try? await Task.sleep(for: .milliseconds(650))
            }
        }
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.position = min(self.track?.duration ?? 0,
                    self.anchorPosition + Date().timeIntervalSince(self.anchorTime))
            }
        }
    }

    func reconnect() { connectionError = nil; controlError = nil; Task { await refresh() } }

    private func refresh() async {
        let revision = seekRevision
        do {
            let snapshot = try await spotify.read()
            // A poll started before a seek must not restore its old playback position.
            guard revision == seekRevision else { return }
            guard let playback = snapshot else {
                pendingSeek = nil
                lyricTask?.cancel()
                updateArtwork(nil)
                lyricRequestID = UUID()
                track = nil; lines = []; plainLyrics = nil; candidates = []; isPlaying = false; loading = false; position = 0
                instrumental = false; lyricLoadFailed = false
                message = "Play something on Spotify"; detail = "Open the Spotify desktop app to get started."
                return
            }
            if playback.track.id != track?.id { pendingSeek = nil }
            let now = Date()
            if let pending = pendingSeek, pending.trackID == playback.track.id, let deadline = pending.deadline {
                let expected = min(playback.track.duration, anchorPosition + (isPlaying ? now.timeIntervalSince(anchorTime) : 0))
                // Spotify can briefly report the old position after accepting a seek.
                if abs(playback.position - expected) < 1.5 || now >= deadline { pendingSeek = nil }
            }
            if pendingSeek == nil {
                anchorPosition = playback.position; anchorTime = now
                position = playback.position
            }
            isPlaying = playback.playing
            if playback.track != track {
                track = playback.track
                offset = timing.offset(for: playback.track.id)
                controlError = nil
                loadLyrics(refresh: false)
            }
            updateArtwork(playback.artworkURL)
        } catch {
            guard revision == seekRevision else { return }
            isPlaying = false
            connectionError = error.localizedDescription
        }
    }

    private func updateArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkTask?.cancel()
        artworkURL = url
        artwork = nil
        accent = Color(red: 0.78, green: 0.75, blue: 1)
        guard let url else { return }
        artworkTask = Task {
            do {
                let asset = try await artworkLoader.load(url)
                guard !Task.isCancelled, artworkURL == url else { return }
                artwork = NSImage(data: asset.data)
                if let rgb = asset.dominant {
                    let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
                    // Lift dark covers enough for the progress fill to stay visible on glass.
                    accent = Color(nsColor: NSColor(calibratedHue: color.hueComponent,
                        saturation: min(1, color.saturationComponent * 1.15),
                        brightness: max(0.65, color.brightnessComponent), alpha: 1))
                }
            } catch { /* Artwork is optional; lyrics and playback remain available. */ }
        }
    }

    func loadLyrics(refresh: Bool = true) {
        lyricTask?.cancel()
        guard let track else { return }
        let requestID = UUID()
        lyricRequestID = requestID
        lines = []; plainLyrics = nil; candidates = []; loading = true
        instrumental = false; lyricLoadFailed = false
        lyricTask = Task {
            defer { if lyricRequestID == requestID { loading = false } }
            do {
                // Allow Spotify's track metadata to settle during a transition. A newer
                // snapshot cancels this task before any lookup for the old snapshot starts.
                try await Task.sleep(for: .milliseconds(750))
                try Task.checkCancellation()
                let result = try await lyrics.lookup(track, refresh: refresh)
                guard !Task.isCancelled, lyricRequestID == requestID, self.track == track else { return }
                switch result {
                case .record(let record): applyRecording(record)
                case .candidates(let matches): candidates = matches
                case .instrumental: showNoLyrics(instrumental: true)
                case .missing: showNoLyrics(instrumental: false)
                }
            } catch {
                guard !Task.isCancelled, lyricRequestID == requestID, self.track == track else { return }
                lyricLoadFailed = true
                message = "Lyrics are unavailable right now"
                detail = "The lyrics library couldn’t be reached. Keep listening, or try again in a moment."
            }
        }
    }

    func chooseRecording(_ record: LyricsRecord) {
        lyricTask?.cancel()
        lyricRequestID = UUID()
        loading = false
        applyRecording(record)
    }

    private func applyRecording(_ record: LyricsRecord) {
        candidates = []
        lines = LRC.parse(record.syncedLyrics ?? "")
        if !lines.contains(where: { !$0.text.isEmpty }) { lines = [] }
        plainLyrics = lines.isEmpty ? record.plainLyrics : nil
        if plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { plainLyrics = nil }
        lyricLoadFailed = false; instrumental = false
        if lines.isEmpty, plainLyrics == nil { showNoLyrics(instrumental: record.instrumental) }
    }

    private func showNoLyrics(instrumental: Bool) {
        self.instrumental = instrumental
        lyricLoadFailed = false
        message = instrumental ? "Feel the music" : "No lyrics available"
        detail = instrumental ? "LRCLIB lists this song as instrumental." : "No lyrics are listed for this recording yet."
    }

    func searchLyrics(title: String, artist: String) async throws -> [LyricsRecord] {
        try await lyrics.search(title: title, artist: artist)
    }

    func command(_ command: String) {
        Task {
            do { try await spotify.command(command); controlError = nil; await refresh() }
            catch { controlError = error.localizedDescription }
        }
    }

    func seek(_ time: Double) {
        guard let track, time.isFinite else { return }
        let target = min(max(0, time), max(0, track.duration - 0.1))
        let requestID = UUID()
        seekRevision += 1
        pendingSeek = PendingSeek(id: requestID, trackID: track.id)
        // Commit the preview before the scrubber releases its drag state.
        anchorPosition = target; anchorTime = Date(); position = target
        Task {
            do {
                try await spotify.command("set player position to \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), target))")
                guard pendingSeek?.id == requestID else { return }
                pendingSeek?.deadline = Date().addingTimeInterval(2)
                controlError = nil
                await refresh()
            } catch {
                guard pendingSeek?.id == requestID else { return }
                pendingSeek = nil
                controlError = error.localizedDescription
                await refresh()
            }
        }
    }
}
