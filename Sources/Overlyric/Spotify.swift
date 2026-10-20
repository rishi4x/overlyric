import AppKit
import LyricsCore

struct Playback: Sendable {
    let track: Track
    let position: Double
    let playing: Bool
    let artworkURL: URL?
}

enum SpotifyError: LocalizedError {
    case scripting(Int, String)
    var errorDescription: String? {
        switch self {
        case .scripting(-1743, _):
            return "Allow Overlyric to control Spotify in System Settings → Privacy & Security → Automation, then reconnect."
        case .scripting(_, let message): return "Couldn’t connect to Spotify. \(message)"
        }
    }
}

actor SpotifyBridge {
    private func run(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SpotifyError.scripting(0, "Unable to prepare playback command.")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            throw SpotifyError.scripting(error[NSAppleScript.errorNumber] as? Int ?? 0,
                error[NSAppleScript.errorMessage] as? String ?? "Please try again.")
        }
        return result
    }

    func read() throws -> Playback? {
        let data = try run("""
        if application id "com.spotify.client" is not running then return {}
        tell application id "com.spotify.client"
            if player state is stopped then return {}
            set t to current track
            return {id of t, name of t, artist of t, album of t, duration of t, player position, (player state is playing), artwork url of t}
        end tell
        """)
        guard data.numberOfItems == 8 else { return nil }
        func string(_ index: Int) -> String { data.atIndex(index)?.stringValue ?? "" }
        let duration = Double(string(5)) ?? 0
        return Playback(track: Track(id: string(1), title: string(2), artist: string(3),
            album: string(4), duration: duration / 1000),
            position: Double(string(6)) ?? 0, playing: data.atIndex(7)?.booleanValue ?? false,
            artworkURL: URL(string: string(8)))
    }

    func command(_ command: String) throws {
        _ = try run("""
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client" to \(command)
        end if
        """)
    }
}
