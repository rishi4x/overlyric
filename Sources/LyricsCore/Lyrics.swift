import Foundation

public struct LyricLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let time: Double
    public let text: String
}

public enum LRC {
    public static func parse(_ source: String) -> [LyricLine] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d{1,2}(?:\.\d+)?)\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let ns = source as NSString
        let offset = offsetPattern.firstMatch(in: source, range: NSRange(location: 0, length: ns.length))
            .flatMap { Double(ns.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var entries: [(Double, String)] = []
        for raw in source.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let text = line.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(line.substring(with: match.range(at: 1))),
                      let seconds = Double(line.substring(with: match.range(at: 2))), seconds < 60 else { continue }
                entries.append((max(0, minutes * 60 + seconds + offset), text))
            }
        }
        return entries.enumerated().sorted {
            $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0
        }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.element.0, text: $0.element.element.1) }
    }

    public static func activeIndex(in lines: [LyricLine], at position: Double) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }
}

public struct Track: Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double

    public init(id: String, title: String, artist: String, album: String, duration: Double) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
}

public struct LyricsRecord: Decodable, Identifiable, Sendable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let albumName: String
    public let duration: Double
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public var hasLyrics: Bool {
        plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            LRC.parse(syncedLyrics ?? "").contains { !$0.text.isEmpty }
    }
}

public enum LyricsLookup: Sendable {
    case record(LyricsRecord), candidates([LyricsRecord]), instrumental, missing

    public static func resolve(_ matches: [LyricsRecord], for track: Track) -> LyricsLookup {
        let nearbyAlbumMatches = matches.filter {
            LyricsRecord.normalized($0.albumName) == LyricsRecord.normalized(track.album) &&
                abs($0.duration - track.duration) <= 15
        }
        if !nearbyAlbumMatches.isEmpty && nearbyAlbumMatches.allSatisfy({ $0.instrumental && !$0.hasLyrics }) {
            return .instrumental
        }
        return matches.isEmpty ? .missing : .candidates(matches)
    }
}

extension LyricsRecord {
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

public enum LyricsError: LocalizedError {
    case notFound, server(Int)
    public var errorDescription: String? {
        switch self {
        case .notFound: return "No lyrics found for this recording."
        case .server(let code): return "LRCLIB is unavailable (\(code)). Try again shortly."
        }
    }
}

public actor LyricsClient {
    private var cache: [Track: LyricsRecord] = [:]
    private var lookupCache: [Track: LyricsLookup] = [:]
    private let session: URLSession
    private let wait: @Sendable (Double) async throws -> Void

    public init(session: URLSession = .shared,
                wait: @escaping @Sendable (Double) async throws -> Void = { seconds in
                    try await Task.sleep(for: .seconds(seconds))
                }) {
        self.session = session
        self.wait = wait
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Overlyric/1.0 (personal macOS lyrics app)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<4 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw LyricsError.server(0) }
                if http.statusCode == 200 { return data }
                if http.statusCode == 404 { throw LyricsError.notFound }
                let temporary = http.statusCode == 408 || http.statusCode == 429 || (500...599).contains(http.statusCode)
                guard temporary, attempt < 3 else { throw LyricsError.server(http.statusCode) }
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
                try await wait(min(30, max(pow(2, Double(attempt)), retryAfter)))
            } catch let error as URLError {
                let temporary: [URLError.Code] = [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .resourceUnavailable]
                guard temporary.contains(error.code), attempt < 3 else { throw error }
                try await wait(pow(2, Double(attempt)))
            }
        }
        throw LyricsError.server(0)
    }

    public func search(_ track: Track) async throws -> [LyricsRecord] {
        let records = try await search(title: track.title, artist: track.artist)
        return records.filter {
            LyricsRecord.normalized($0.trackName) == LyricsRecord.normalized(track.title) &&
                LyricsRecord.normalized($0.artistName) == LyricsRecord.normalized(track.artist)
        }.sorted { abs($0.duration - track.duration) < abs($1.duration - track.duration) }
    }

    public func search(title: String, artist: String) async throws -> [LyricsRecord] {
        var url = URLComponents(string: "https://lrclib.net/api/search")!
        url.queryItems = [.init(name: "track_name", value: title.trimmingCharacters(in: .whitespacesAndNewlines))]
        if !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url.queryItems?.append(.init(name: "artist_name", value: artist.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let data = try await request(url.url!)
        return try JSONDecoder().decode([LyricsRecord].self, from: data)
            .filter { $0.hasLyrics || $0.instrumental }
    }

    public func lookup(_ track: Track, refresh: Bool = false) async throws -> LyricsLookup {
        if refresh { lookupCache[track] = nil; cache[track] = nil }
        if let cached = lookupCache[track] { return cached }
        let result: LyricsLookup
        do { result = .record(try await fetch(track)) }
        catch {
            let shouldSearch: Bool
            switch error {
            case LyricsError.notFound: shouldSearch = true
            case LyricsError.server(let code): shouldSearch = (500...599).contains(code)
            default: shouldSearch = false
            }
            guard shouldSearch else { throw error }
            try Task.checkCancellation()
            try await wait(0.25)
            result = LyricsLookup.resolve(try await search(track), for: track)
        }
        try Task.checkCancellation()
        if lookupCache.count >= 100 { lookupCache.removeAll() }
        lookupCache[track] = result
        return result
    }

    public func fetch(_ track: Track) async throws -> LyricsRecord {
        if let cached = cache[track] { return cached }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(Int(track.duration.rounded())))
        ]
        let data = try await request(url.url!)
        let record = try JSONDecoder().decode(LyricsRecord.self, from: data)
        if cache.count >= 100 { cache.removeAll() }
        cache[track] = record
        return record
    }
}
