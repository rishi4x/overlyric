import SwiftUI
import LyricsCore

@MainActor
final class PlayerModel: ObservableObject {
    @Published var track: Track?
    let clock = PlaybackClock()
    var position: Double {
        get { clock.position }
        set {
            if clock.position != newValue { clock.position = newValue }
            updateActiveIndex()
        }
    }
    @Published var isPlaying = false
    @Published var lines: [LyricLine] = [] { didSet { updateActiveIndex() } }
    @Published private(set) var activeIndex: Int?
    @Published var plainLyrics: String?
    @Published var candidates: [LyricsRecord] = []
    @Published private(set) var showAlternateRecordingNotice = false
    @Published private(set) var selectedRecordingID: Int?
    @Published var message = "Play something on Spotify"
    @Published var detail = "Your words will meet you here."
    @Published var loading = false
    @Published var instrumental = false
    @Published var lyricLoadFailed = false
    @Published var connectionError: String?
    @Published var controlError: String?
    @Published var offset = 0.0 {
        didSet {
            if let track { timing.setOffset(offset, for: track.id) }
            updateActiveIndex()
        }
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
    @Published private(set) var ambienceColors: [Color] = []
    @Published var accent = Color(white: 0.72)
    private let timing = TimingPreferences()
    private let recordings = RecordingPreferences()
    private let artworkLoader = ArtworkLoader()
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?
    private let spotify = SpotifyBridge()
    private let lyrics = LyricsResolver(diskCache: LyricsDiskCache())
    @Published private(set) var lyricsSource = "LRCLIB"
    private var currentLyricsSource: LyricsSource = .lrclib
    private func recordingKey(for trackID: String) -> String {
        currentLyricsSource == .netease ? "netease:\(trackID)" : trackID
    }
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

    private func updateActiveIndex() {
        let index = LRC.activeIndex(in: lines, at: position + offset)
        if activeIndex != index { activeIndex = index }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.connectionError == nil { await self.refresh() }
                try? await Task.sleep(for: .milliseconds(650))
            }
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.position = min(self.track?.duration ?? 0,
                    self.anchorPosition + Date().timeIntervalSince(self.anchorTime))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
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
                showAlternateRecordingNotice = false; selectedRecordingID = nil
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
            if isPlaying != playback.playing { isPlaying = playback.playing }
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
        ambienceColors = []
        accent = Color(white: 0.72)
        guard let url else { return }
        artworkTask = Task {
            do {
                let asset = try await artworkLoader.load(url)
                guard !Task.isCancelled, artworkURL == url else { return }
                artwork = NSImage(data: asset.data)
                ambienceColors = asset.palette.map { rgb in
                    let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
                    return Color(nsColor: NSColor(calibratedHue: color.hueComponent,
                        saturation: min(1, color.saturationComponent * 1.1),
                        brightness: min(0.85, max(0.6, color.brightnessComponent)), alpha: 1))
                }
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
        showAlternateRecordingNotice = false; selectedRecordingID = nil
        instrumental = false; lyricLoadFailed = false
        lyricsSource = "LRCLIB"
        currentLyricsSource = .lrclib
        lyricTask = Task {
            defer { if lyricRequestID == requestID { loading = false } }
            do {
                // Cached lyrics can appear immediately; newer track snapshots cancel this lookup.
                try Task.checkCancellation()
                let resolution = try await lyrics.lookup(track, refresh: refresh)
                guard !Task.isCancelled, lyricRequestID == requestID, self.track == track else { return }
                currentLyricsSource = resolution.source
                lyricsSource = resolution.source.title
                switch resolution.lookup {
                case .record(let record): applyRecording(record)
                case .candidates(let matches):
                    if let record = recordings.preferredRecording(in: matches, for: recordingKey(for: track.id)) {
                        candidates = matches
                        applyRecording(record)
                        recordings.remember(record.id, for: recordingKey(for: track.id))
                        showAlternateRecordingNotice = !recordings.isNoticeDismissed(for: recordingKey(for: track.id))
                    } else {
                        showNoLyrics(instrumental: false)
                    }
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
        guard let track else { return }
        let requestID = lyricRequestID
        loading = true
        lyricTask = Task {
            defer { if lyricRequestID == requestID { loading = false } }
            do {
                let resolved = try await lyrics.fetch(record)
                guard !Task.isCancelled, lyricRequestID == requestID, self.track == track else { return }
                applyRecording(resolved)
                await lyrics.remember(resolved, for: track)
                guard !Task.isCancelled, lyricRequestID == requestID, self.track == track else { return }
                recordings.remember(record.id, for: recordingKey(for: track.id))
                dismissAlternateRecordingNotice()
            } catch {
                guard !Task.isCancelled, lyricRequestID == requestID, self.track == track else { return }
                controlError = "Couldn’t load this recording. Try another version."
            }
        }
    }

    func dismissAlternateRecordingNotice() {
        if let track { recordings.dismissNotice(for: recordingKey(for: track.id)) }
        showAlternateRecordingNotice = false
    }

    private func applyRecording(_ record: LyricsRecord) {
        currentLyricsSource = record.source ?? .lrclib
        lyricsSource = currentLyricsSource.title
        selectedRecordingID = record.id
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
        detail = instrumental ? "\(lyricsSource) marks this recording as instrumental." : "No lyrics are listed for this recording yet."
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
