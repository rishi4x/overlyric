import Foundation

public enum NetEaseError: LocalizedError {
    case unavailable(Int)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let code): return "NetEase is unavailable (\(code)). Try again shortly."
        }
    }
}

public actor NetEaseLyricsClient {
    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            struct Song: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable { let name: String }
                let id: Int
                let name: String
                let artists: [Artist]
                let album: Album
                let duration: Double
            }
            let songs: [Song]?
        }
        let code: Int
        let result: Result?
    }
    private struct LyricResponse: Decodable {
        struct Body: Decodable { let lyric: String? }
        let code: Int
        let lrc: Body?
        let nolyric: Bool?
    }
    private let session: URLSession
    private let wait: @Sendable (Double) async throws -> Void
    private var cache: [Int: LyricsRecord] = [:]

    public init(session: URLSession? = nil,
                wait: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12
        self.session = session ?? URLSession(configuration: config)
        self.wait = wait
    }

    private func request(_ path: String, query: [URLQueryItem]) async throws -> Data {
        var url = URLComponents(string: "https://music.163.com\(path)")!
        url.queryItems = query
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return data }
                guard attempt < 2, status == 429 || (500...599).contains(status) else {
                    throw NetEaseError.unavailable(status)
                }
                try await wait(pow(2, Double(attempt)))
            } catch let error as URLError {
                guard attempt < 2, [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) else { throw error }
                try await wait(pow(2, Double(attempt)))
            }
        }
        throw NetEaseError.unavailable(0)
    }

    public func search(title: String, artist: String) async throws -> [LyricsRecord] {
        let term = [title, artist].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !term.isEmpty else { return [] }
        let data = try await request("/api/search/get", query: [
            .init(name: "s", value: term), .init(name: "type", value: "1"),
            .init(name: "limit", value: "10"), .init(name: "offset", value: "0")])
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard response.code == 200 else { throw NetEaseError.unavailable(response.code) }
        return (response.result?.songs ?? []).map { song in
            LyricsRecord(id: song.id, trackName: song.name, artistName: song.artists.map(\.name).joined(separator: ", "),
                albumName: song.album.name, duration: song.duration / 1000, instrumental: false,
                plainLyrics: nil, syncedLyrics: nil, source: .netease)
        }
    }

    public func fetch(_ record: LyricsRecord, refresh: Bool = false) async throws -> LyricsRecord {
        if !refresh, let cached = cache[record.id] { return cached }
        let data = try await request("/api/song/lyric", query: [
            .init(name: "id", value: String(record.id)), .init(name: "lv", value: "1"),
            .init(name: "kv", value: "1"), .init(name: "tv", value: "-1")])
        let response = try JSONDecoder().decode(LyricResponse.self, from: data)
        guard response.code == 200 else { throw NetEaseError.unavailable(response.code) }
        let text = Self.removingCredits(response.lrc?.lyric ?? "")
        let timed = LRC.parse(text)
        let usable = timed.contains { !$0.text.isEmpty }
        let result = LyricsRecord(id: record.id, trackName: record.trackName, artistName: record.artistName,
            albumName: record.albumName, duration: record.duration, instrumental: response.nolyric == true,
            plainLyrics: timed.isEmpty && !text.isEmpty ? text : nil,
            syncedLyrics: usable ? text : nil, source: .netease)
        try Task.checkCancellation()
        if cache.count >= 100 { cache.removeAll() }
        cache[record.id] = result
        return result
    }

    static func removingCredits(_ text: String) -> String {
        // Match explicit role labels only, after any timestamps. Never remove early
        // cues merely because of their position, or phrases containing these words.
        let pattern = #"^\s*(?:\[[^\]]+\]\s*)*(?:作词|作詞|作曲|编曲|編曲|制作人|製作人|制作|製作|词曲|詞曲|混音|母带|母帶|录音|錄音|监制|監製|词|詞|曲|lyricist|composer|lyrics\s+by|written\s+by|composed\s+by|produced\s+by|producer|arranged\s+by|arranger|mixed\s+by|mastered\s+by|recorded\s+by)\s*[:：]"#
        let expression = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return text.components(separatedBy: .newlines).filter { line in
            expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func lookup(_ track: Track, refresh: Bool = false) async throws -> LyricsLookup {
        let matches = try await search(title: track.title, artist: track.artist).filter {
            LyricsRecord.normalized($0.trackName) == LyricsRecord.normalized(track.title) &&
            LyricsRecord.normalized($0.artistName) == LyricsRecord.normalized(track.artist) &&
            abs($0.duration - track.duration) <= 15
        }.sorted {
            let leftAlbum = LyricsRecord.normalized($0.albumName) == LyricsRecord.normalized(track.album)
            let rightAlbum = LyricsRecord.normalized($1.albumName) == LyricsRecord.normalized(track.album)
            if leftAlbum != rightAlbum { return leftAlbum }
            return abs($0.duration - track.duration) < abs($1.duration - track.duration)
        }
        var available: [LyricsRecord] = []
        for match in matches.prefix(3) {
            let record = try await fetch(match, refresh: refresh)
            if record.hasLyrics || record.instrumental { available.append(record) }
        }
        guard let first = available.first else { return .missing }
        if LyricsRecord.normalized(first.albumName) == LyricsRecord.normalized(track.album), abs(first.duration - track.duration) <= 3 {
            return .record(first)
        }
        return .candidates(available)
    }
}
