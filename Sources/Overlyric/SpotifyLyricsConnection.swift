import AppKit
import SwiftUI
import WebKit
import Security
import LyricsCore

@MainActor
final class SpotifyLyricsConnection: ObservableObject {
    let client = SpotifyLyricsClient()
    @Published private(set) var cookie: String?
    @Published var status = "Sign in to Spotify, then click Connect lyrics."
    @Published var busy = false
    private var window: NSWindow?
    private var browser: WKWebView?
    private var onChange: (() -> Void)?
    private let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.overlyric.spotify-lyrics", kSecAttrAccount as String: "sp_dc"]

    init() {
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            cookie = String(data: data, encoding: .utf8)
        }
    }

    func show(onChange: @escaping () -> Void) {
        self.onChange = onChange
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        self.browser = browser
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Spotify lyrics"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 520)
        window.contentViewController = NSHostingController(rootView: SpotifyLyricsLogin(connection: self, browser: browser))
        self.window = window
        browser.load(URLRequest(url: URL(string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!))
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func connect() {
        guard !busy, let browser else { return }
        busy = true
        Task {
            let cookies = await browser.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard let session = cookies.first(where: {
                $0.name == "sp_dc" && ($0.domain == "spotify.com" || $0.domain == ".spotify.com" || $0.domain == "open.spotify.com") &&
                    ($0.expiresDate.map { $0 > Date() } ?? true)
            }) else {
                status = "Finish signing in to Spotify, then try Connect lyrics again."
                busy = false
                return
            }
            status = "Checking Spotify lyrics access…"
            do {
                try await client.validateSession(cookie: session.value)
            } catch {
                status = "Spotify couldn’t verify this session. Try signing in again; LRCLIB is still available."
                busy = false
                return
            }
            var attributes: [String: Any] = [kSecValueData as String: Data(session.value.utf8)]
            let update = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
            let saved: OSStatus
            if update == errSecItemNotFound {
                attributes.merge(key) { value, _ in value }
                attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                saved = SecItemAdd(attributes as CFDictionary, nil)
            } else { saved = update }
            guard saved == errSecSuccess else {
                status = "Couldn’t save the Spotify session in Keychain (\(saved))."
                busy = false
                return
            }
            cookie = session.value
            status = "Connected. Spotify lyrics will be tried before LRCLIB."
            busy = false
            onChange?()
            window?.close()
            // Discard the temporary sign-in browser; only the session cookie remains in Keychain.
            window = nil; self.browser = nil
        }
    }

    func disconnect() {
        let result = SecItemDelete(key as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            status = "Couldn’t remove the Spotify session from Keychain (\(result))."
            return
        }
        cookie = nil
        status = "Sign in to Spotify, then click Connect lyrics."
        window?.close(); window = nil; browser = nil
    }
}

private struct SpotifySignInBrowser: NSViewRepresentable {
    let browser: WKWebView
    func makeNSView(context: Context) -> WKWebView { browser }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

private struct SpotifyLyricsLogin: View {
    @ObservedObject var connection: SpotifyLyricsConnection
    let browser: WKWebView
    var body: some View {
        VStack(spacing: 0) {
            SpotifySignInBrowser(browser: browser)
            VStack(alignment: .leading, spacing: 10) {
                Text("Use Spotify’s lyrics").font(.headline)
                Text(connection.status).font(.callout).foregroundStyle(.secondary)
                Text("Your Spotify session saves in macOS Keychain. LRCLIB remains the fallback.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Connect lyrics") { connection.connect() }
                        .buttonStyle(.borderedProminent).disabled(connection.busy)
                }
            }.padding(18)
        }
    }
}
