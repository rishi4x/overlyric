import Foundation

public struct LyricsResolution: Codable, Sendable {
    public let source: LyricsSource
    public let lookup: LyricsLookup
}

public actor LyricsResolver {
    private let lrclib: LyricsClient
    private let netease: NetEaseLyricsClient
    private let primary: @Sendable (Track, Bool) async throws -> LyricsLookup
    private let fallback: @Sendable (Track, Bool) async throws -> LyricsLookup
    private let diskCache: LyricsDiskCache?

    public init(lrclib: LyricsClient = LyricsClient(), netease: NetEaseLyricsClient = NetEaseLyricsClient(),
                primary: (@Sendable (Track, Bool) async throws -> LyricsLookup)? = nil,
                fallback: (@Sendable (Track, Bool) async throws -> LyricsLookup)? = nil,
                diskCache: LyricsDiskCache? = nil) {
        self.lrclib = lrclib; self.netease = netease
        self.primary = primary ?? { try await lrclib.lookup($0, refresh: $1) }
        self.fallback = fallback ?? { try await netease.lookup($0, refresh: $1) }
        self.diskCache = diskCache
    }

    public func lookup(_ track: Track, refresh: Bool = false) async throws -> LyricsResolution {
        try Task.checkCancellation()
        if !refresh, let cached = diskCache?.load(track) { return cached }
        async let primaryResult = Self.attempt(primary, track: track, refresh: refresh)
        async let fallbackResult = Self.attempt(fallback, track: track, refresh: refresh)
        var primaryError: Error?
        do {
            let result = try await primaryResult.get()
            try Task.checkCancellation()
            if result.isUsable {
                let resolution = LyricsResolution(source: .lrclib, lookup: result)
                diskCache?.save(resolution, for: track)
                return resolution
            }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            primaryError = error
        }
        try Task.checkCancellation()
        let result = try await fallbackResult.get()
        try Task.checkCancellation()
        if case .missing = result, let primaryError { throw primaryError }
        let resolution = LyricsResolution(source: .netease, lookup: result)
        diskCache?.save(resolution, for: track)
        return resolution
    }

    private static func attempt(_ operation: @Sendable (Track, Bool) async throws -> LyricsLookup,
                                track: Track, refresh: Bool) async -> Result<LyricsLookup, Error> {
        do { return .success(try await operation(track, refresh)) }
        catch { return .failure(error) }
    }

    public func remember(_ record: LyricsRecord, for track: Track) {
        diskCache?.save(LyricsResolution(source: record.source ?? .lrclib, lookup: .record(record)), for: track)
    }

    public func search(title: String, artist: String) async throws -> [LyricsRecord] {
        do {
            let records = try await lrclib.search(title: title, artist: artist)
            try Task.checkCancellation()
            if !records.isEmpty { return records }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
        }
        return try await netease.search(title: title, artist: artist)
    }

    public func fetch(_ record: LyricsRecord) async throws -> LyricsRecord {
        if record.source == .netease { return try await netease.fetch(record) }
        return record
    }
}
