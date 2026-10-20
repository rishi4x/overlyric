import AppKit
import SwiftUI
import LyricsCore

/// Explicitly hands header drags to AppKit, including for nonactivating pinned panels.
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

/// Native menu stays intact while playback publishes position updates.
struct OptionsButton: NSViewRepresentable {
    let player: PlayerModel
    let app: AppController
    let onSearch: () -> Void

    final class Button: NSButton {
        override var acceptsFirstResponder: Bool { false }
    }

    @MainActor final class Coordinator: NSObject {
        let player: PlayerModel
        let app: AppController
        var onSearch: () -> Void
        init(player: PlayerModel, app: AppController, onSearch: @escaping () -> Void) {
            self.player = player; self.app = app; self.onSearch = onSearch
        }

        @objc func show(_ sender: NSButton) {
            let menu = NSMenu()
            func add(_ title: String, enabled: Bool = true, action: @escaping @MainActor () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action
                item.isEnabled = enabled
                menu.addItem(item)
            }
            menu.autoenablesItems = false
            for mode in DisplayMode.allCases {
                add(mode.title) { self.app.mode = mode }
                menu.items.last?.state = app.mode == mode ? .on : .off
            }
            menu.addItem(.separator())
            func resize(_ delta: Double) {
                let size = UserDefaults.standard.object(forKey: "lyricFontSize") as? Double ?? 27
                UserDefaults.standard.set(min(42, max(18, size + delta)), forKey: "lyricFontSize")
            }
            add("Larger lyrics") { resize(2) }
            add("Smaller lyrics") { resize(-2) }
            let alwaysShowHeader = UserDefaults.standard.object(forKey: "alwaysShowHeader") as? Bool ?? true
            add("Always show header") {
                UserDefaults.standard.set(!alwaysShowHeader, forKey: "alwaysShowHeader")
            }
            menu.items.last?.state = alwaysShowHeader ? .on : .off
            menu.addItem(.separator())
            add(String(format: "Lyric timing: %+.1fs", player.offset), enabled: false) {}
            add("Advance lyrics 0.5s") { self.player.adjustTiming(by: 0.5) }
            menu.items.last?.keyEquivalent = "\u{F702}"
            menu.items.last?.keyEquivalentModifierMask = .option
            add("Delay lyrics 0.5s") { self.player.adjustTiming(by: -0.5) }
            menu.items.last?.keyEquivalent = "\u{F703}"
            menu.items.last?.keyEquivalentModifierMask = .option
            add("Reset timing") { self.player.resetTiming() }
            menu.addItem(.separator())
            add("Search lyrics…", enabled: player.track != nil) { self.onSearch() }
            add("Reload lyrics", enabled: player.track != nil) { self.player.loadLyrics() }
            add("Reconnect Spotify") { self.player.reconnect() }
            add("Lyrics from LRCLIB") { NSWorkspace.shared.open(URL(string: "https://lrclib.net")!) }
            menu.addItem(.separator())
            add("Quit Overlyric") { NSApp.terminate(nil) }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 5), in: sender)
        }

        @objc private func invoke(_ sender: NSMenuItem) {
            (sender.representedObject as? @MainActor () -> Void)?()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(player: player, app: app, onSearch: onSearch) }
    func makeNSView(context: Context) -> NSButton {
        let button = Button()
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Options")
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.focusRingType = .none
        button.toolTip = "Options"
        button.setAccessibilityLabel("Options")
        button.target = context.coordinator
        button.action = #selector(Coordinator.show(_:))
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) { context.coordinator.onSearch = onSearch }
}
