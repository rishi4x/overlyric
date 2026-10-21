import Foundation
import CryptoKit

/// Accessed on the resolver actor, away from the UI thread. Cache failures are optional.
public struct LyricsDiskCache: Sendable {
    private struct Entry: Codable {
        let version: Int
        let track: Track
        let savedAt: Date
        let resolution: LyricsResolution
    }
    public let directory: URL
    private let maxEntries: Int
    private let maxBytes: Int
    private let lifetime: TimeInterval

    public init(directory: URL? = nil, maxEntries: Int = 1000, maxBytes: Int = 20 * 1024 * 1024,
                lifetime: TimeInterval = 30 * 86400) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.rishi.overlyric/Lyrics", isDirectory: true)
        self.maxEntries = maxEntries; self.maxBytes = maxBytes; self.lifetime = lifetime
    }

    private func url(for track: Track) -> URL {
        let key = SHA256.hash(data: Data(track.id.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }

    public func load(_ track: Track, now: Date = Date()) -> LyricsResolution? {
        let file = url(for: track)
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.version == 1,
              entry.track == track, now.timeIntervalSince(entry.savedAt) < lifetime else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        return entry.resolution
    }

    public func save(_ resolution: LyricsResolution, for track: Track, now: Date = Date()) {
        guard resolution.lookup.isUsable else { return }
        let entry = Entry(version: 1, track: track, savedAt: now, resolution: resolution)
        guard let data = try? JSONEncoder().encode(entry), data.count <= maxBytes else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: track), options: .atomic)
            prune()
        } catch { /* Cache writes must not interrupt lyrics. */ }
    }

    private func prune() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var entries: [(url: URL, size: Int, modified: Date)] = []
        for file in files where file.pathExtension == "json" {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            entries.append((file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
        }
        entries.sort { $0.modified < $1.modified }
        var bytes = entries.reduce(0) { $0 + $1.size }
        var count = entries.count
        for entry in entries {
            guard count > maxEntries || bytes > maxBytes else { break }
            if (try? manager.removeItem(at: entry.url)) != nil { count -= 1; bytes -= entry.size }
        }
    }
}

extension LyricsLookup {
    var isUsable: Bool {
        switch self {
        case .record(let record): return record.hasLyrics || record.instrumental
        case .candidates(let records): return records.contains { $0.hasLyrics || $0.instrumental }
        case .instrumental: return true
        case .missing: return false
        }
    }
}
