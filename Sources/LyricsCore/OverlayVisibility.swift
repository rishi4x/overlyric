public enum DisplayMode: String, CaseIterable, Sendable {
    case menuBar, overlay, spotify

    public var title: String {
        switch self {
        case .menuBar: return "Show in menu bar"
        case .overlay: return "Show as overlay"
        case .spotify: return "Attach to Spotify"
        }
    }

    public static func restored(_ rawValue: String?, legacyShowWithSpotify: Bool) -> DisplayMode {
        let saved = rawValue.flatMap(DisplayMode.init(rawValue:)) ?? .overlay
        return saved == .overlay && legacyShowWithSpotify ? .spotify : saved
    }
}

public enum StatusClickAction: Equatable {
    case showOverlay, hideOverlay, detachSpotify, openPopover, closePopover
}

public enum OverlayVisibility {
    public static func shouldShow(requested: Bool, mode: DisplayMode,
                                  spotifyFocused: Bool, interactingWithOverlay: Bool) -> Bool {
        guard mode != .menuBar, requested else { return false }
        return mode == .overlay || spotifyFocused || interactingWithOverlay
    }

    public static func statusClick(mode: DisplayMode, visible: Bool, keyWindow: Bool, popoverShown: Bool) -> StatusClickAction {
        switch mode {
        case .spotify: return .detachSpotify
        case .menuBar: return popoverShown ? .closePopover : .openPopover
        case .overlay: return visible && keyWindow ? .hideOverlay : .showOverlay
        }
    }
}
