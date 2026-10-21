import AppKit
import SwiftUI
import LyricsCore

final class LyricPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayHostingView: NSHostingView<LyricsView> {
    var hoverChanged: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.hoverChanged?(window.frame.contains(NSEvent.mouseLocation))
        }
    }
    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    @Published var overlayHovered = false
    @Published private(set) var isLiveResizing = false
    @Published var mode = DisplayMode.restored(UserDefaults.standard.string(forKey: "displayMode"),
        legacyShowWithSpotify: UserDefaults.standard.bool(forKey: "showWithSpotify")) {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "displayMode")
            if mode != .menuBar { popover.close(); showOverlay(activate: mode == .overlay) }
            else {
                panel?.orderOut(nil)
                popover.close()
                overlayHovered = false
                showPopover()
            }
        }
    }
    @Published var pinned = UserDefaults.standard.object(forKey: "pinned") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinned"); panel?.level = pinned ? .floating : .normal }
    }
    let player = PlayerModel()
    private var statusItem: NSStatusItem!
    private var panel: LyricPanel?
    private let popover = NSPopover()
    private var overlayRequested = true
    private var foregroundBundleID: String?
    private var timingKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.set(mode.rawValue, forKey: "displayMode")
        UserDefaults.standard.removeObject(forKey: "showWithSpotify")
        foregroundBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(foregroundApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let icon = NSImage(size: NSSize(width: 18, height: 18))
            for suffix in ["", "@2x", "@3x"] {
                guard let url = Bundle.main.url(forResource: "MenuBarIcon\(suffix)", withExtension: "png"),
                      let data = try? Data(contentsOf: url),
                      let representation = NSBitmapImageRep(data: data) else { continue }
                representation.size = icon.size
                icon.addRepresentation(representation)
            }
            if !icon.representations.isEmpty {
                icon.isTemplate = true
                icon.accessibilityDescription = "Overlyric"
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Overlyric")
            }
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Overlyric · click to toggle lyrics · right-click for options"
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.contentViewController = NSHostingController(rootView: LyricsView(player: player, app: self, popover: true))
        timingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window, window.isKeyWindow,
                  window === self.panel || (self.popover.isShown && window === self.popover.contentViewController?.view.window),
                  !(window.firstResponder is NSTextView) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == .command || modifiers == [.command, .shift] {
                switch event.charactersIgnoringModifiers {
                case "+", "=": self.resizeLyrics(by: 2)
                case "-": self.resizeLyrics(by: -2)
                case "0" where modifiers == .command: self.resetLyricSize()
                default: return event
                }
                return nil
            }
            if modifiers.isEmpty {
                guard self.player.track != nil, self.player.connectionError == nil else { return event }
                switch event.keyCode {
                case 49:
                    if !event.isARepeat { self.player.command("playpause") }
                case 123: self.player.seek(self.player.position - 10)
                case 124: self.player.seek(self.player.position + 10)
                default: return event
                }
                return nil
            }
            guard modifiers == .option, !self.player.lines.isEmpty else { return event }
            switch event.keyCode {
            case 123: self.player.adjustTiming(by: 0.5)
            case 124: self.player.adjustTiming(by: -0.5)
            default: return event
            }
            return nil
        }
        player.start()
        if mode != .menuBar { showOverlay() }
    }

    func showOverlay(activate: Bool = false) {
        overlayRequested = true
        updateOverlayVisibility()
        if activate, mode == .overlay {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
        }
    }

    func resizeLyrics(by delta: Double) {
        let size = UserDefaults.standard.object(forKey: "lyricFontSize") as? Double ?? 27
        UserDefaults.standard.set(min(42, max(18, size + delta)), forKey: "lyricFontSize")
    }

    func resetLyricSize() { UserDefaults.standard.removeObject(forKey: "lyricFontSize") }

    private func makeOverlayIfNeeded() {
        if panel == nil {
            let window = LyricPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 510),
                styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Overlyric"
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.preservesContentDuringLiveResize = false
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: LyricLayout.minimumWidth, height: LyricLayout.minimumHeight)
            window.maxSize = NSSize(width: 850, height: 1200)
            window.level = pinned ? .floating : .normal
            window.delegate = self
            let hostingView = OverlayHostingView(rootView: LyricsView(player: player, app: self))
            hostingView.hoverChanged = { [weak self] hovered in
                if self?.overlayHovered != hovered { self?.overlayHovered = hovered }
            }
            window.contentView = hostingView
            if !window.setFrameUsingName("lyricOverlay") { window.center() }
            var restoredFrame = window.frame
            restoredFrame.size.width = min(window.maxSize.width, max(window.minSize.width, restoredFrame.width))
            restoredFrame.size.height = min(window.maxSize.height, max(window.minSize.height, restoredFrame.height))
            window.setFrame(restoredFrame, display: false)
            window.setFrameAutosaveName("lyricOverlay")
            panel = window
        }
    }

    private func updateOverlayVisibility() {
        let allowed = OverlayVisibility.shouldShow(requested: overlayRequested, mode: mode,
            spotifyFocused: foregroundBundleID == "com.spotify.client",
            interactingWithOverlay: foregroundBundleID == Bundle.main.bundleIdentifier && panel?.isVisible == true)
        if allowed {
            makeOverlayIfNeeded()
            if panel?.isVisible != true { panel?.orderFrontRegardless() }
        } else {
            panel?.orderOut(nil)
            overlayHovered = false
        }
    }

    @objc private func foregroundApplicationChanged(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        foregroundBundleID = application.bundleIdentifier
        updateOverlayVisibility()
    }

    func closeSurface() {
        if mode != .menuBar {
            overlayRequested = false
            updateOverlayVisibility()
        } else { popover.close() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        switch OverlayVisibility.statusClick(mode: mode, visible: panel?.isVisible == true,
            keyWindow: panel?.isKeyWindow == true, popoverShown: popover.isShown) {
        case .showOverlay: showOverlay(activate: true)
        case .hideOverlay: closeSurface()
        case .detachSpotify: mode = .overlay
        case .openPopover: showPopover()
        case .closePopover: popover.close()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        for displayMode in DisplayMode.allCases {
            let item = NSMenuItem(title: displayMode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.representedObject = displayMode.rawValue
            item.target = self; item.state = mode == displayMode ? .on : .off; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Overlyric", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let selected = DisplayMode(rawValue: raw) else { return }
        mode = selected
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if mode != .menuBar { showOverlay(activate: mode == .overlay) } else { showPopover() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillStartLiveResize(_ notification: Notification) { isLiveResizing = true }
    func windowDidEndLiveResize(_ notification: Notification) { isLiveResizing = false }
    func applicationWillTerminate(_ notification: Notification) {
        if let timingKeyMonitor { NSEvent.removeMonitor(timingKeyMonitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

@main
enum OverlyricApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        withExtendedLifetime(controller) { application.run() }
    }
}
