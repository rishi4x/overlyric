import Foundation

public struct RecordingPreferences {
    private let defaults: UserDefaults
    private let key = "trackRecordingPreferences"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func entry(for trackID: String) -> [String: Any] {
        defaults.dictionary(forKey: key)?[trackID] as? [String: Any] ?? [:]
    }

    public func preferredRecording(in records: [LyricsRecord], for trackID: String) -> LyricsRecord? {
        let preferredID = entry(for: trackID)["recordingID"] as? Int
        return records.first(where: { $0.id == preferredID }) ?? records.first
    }

    public func isNoticeDismissed(for trackID: String) -> Bool {
        entry(for: trackID)["noticeDismissed"] as? Bool ?? false
    }

    public func remember(_ recordingID: Int, for trackID: String) {
        update(trackID) { $0["recordingID"] = recordingID }
    }

    public func dismissNotice(for trackID: String) {
        update(trackID) { $0["noticeDismissed"] = true }
    }

    private func update(_ trackID: String, change: (inout [String: Any]) -> Void) {
        var entries = defaults.dictionary(forKey: key) ?? [:]
        var entry = entry(for: trackID)
        change(&entry)
        entries[trackID] = entry
        defaults.set(entries, forKey: key)
    }
}
