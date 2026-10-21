import SwiftUI
import LyricsCore

struct LyricsView: View {
    @ObservedObject var player: PlayerModel
    @ObservedObject var app: AppController
    var popover = false
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    @State private var browsing = false
    @State private var followRequest = 0
    @State private var panelSize = CGSize(width: 390, height: 510)
    @State private var timingToastVisible = false
    @State private var timingToastHideTask: Task<Void, Never>?
    @State private var scrollState = LyricScrollState()
    @State private var lyricScrollPosition = ScrollPosition()
    @State private var scrollbarVisible = false
    @State private var scrollbarDragging = false
    @State private var scrollbarHideTask: Task<Void, Never>?
    @State private var showingLyricsSearch = false
    @State private var showingRecordingPicker = false
    @State private var surfaceHovered = false
    @State private var showingAvailabilityInfo = false
    @AppStorage("alwaysShowHeader") private var alwaysShowHeader = true
    @AppStorage("ambienceEnabled") private var ambienceEnabled = true
    @AppStorage("lyricFontSize") private var fontSize = 27.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { player.accent }
    private var layout: LyricLayout { LyricLayout(width: panelSize.width, height: panelSize.height) }
    private var controlsVisible: Bool { app.overlayHovered || scrubbing || popover || player.track == nil }
    private var availabilityActionsVisible: Bool { surfaceHovered || (!popover && app.overlayHovered) || showingAvailabilityInfo }

    private var headerVisible: Bool { showingRecordingPicker || popover || alwaysShowHeader || app.overlayHovered || scrubbing }
    private var headerActionsVisible: Bool { surfaceHovered || (!popover && app.overlayHovered) || scrubbing }
    private var lineAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1)
    }

    var body: some View {
        Group {
            if popover {
                // The native popover supplies its own continuous surface and corners.
                content
            } else {
                content
                    .background { panelBackground }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.15), lineWidth: 1) }
                    .ignoresSafeArea()
            }
        }
        .foregroundStyle(Color(white: 0.96))
        .preferredColorScheme(.dark)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { panelSize = $0 }
        .onHover { surfaceHovered = $0 }
        .onChange(of: player.loading) { _, loading in if loading { showingRecordingPicker = false } }
        .sheet(isPresented: $showingLyricsSearch) { LyricsSearchView(player: player) }
        .onChange(of: player.timingAdjustmentCount) { _, _ in
            timingToastHideTask?.cancel()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { timingToastVisible = true }
            timingToastHideTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { timingToastVisible = false }
            }
        }
        .onChange(of: player.track?.id) { _, _ in
            showingRecordingPicker = false
            timingToastHideTask?.cancel()
            timingToastVisible = false
            scrollbarHideTask?.cancel()
            scrollbarVisible = false
            scrollbarDragging = false
            browsing = false
        }
        .onDisappear {
            timingToastHideTask?.cancel()
            timingToastVisible = false
            scrollbarHideTask?.cancel()
            scrollbarVisible = false
            scrollbarDragging = false
        }
        .transaction { transaction in
            if app.isLiveResizing {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var content: some View {
        lyricBody
            // Instrumentals center their entire visible group in the panel.
            // Lyrics keep a stable viewport, unaffected by hover controls.
            .padding(.top, showingRecordingPicker ? 112 : (!player.instrumental && (popover || alwaysShowHeader) ? 77 : 0))
            .background { AlbumAmbience(colors: player.ambienceColors, enabled: ambienceEnabled) }
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    header.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
                        .background { if !popover { WindowDragHandle() } }
                    if player.showAlternateRecordingNotice && availabilityActionsVisible && !showingRecordingPicker {
                        alternateRecordingNotice.padding(.horizontal, 22).padding(.bottom, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(stops: [.init(color: .black.opacity(0.92), location: 0),
                        .init(color: .black.opacity(0.8), location: 0.45),
                        .init(color: .black.opacity(0.45), location: 0.72),
                        .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        .contentShape(Rectangle()).onTapGesture { }
                        .accessibilityHidden(true)
                        .padding(.bottom, -55)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { view in
                    view.opacity(headerVisible ? 1 : 0)
                }
                .allowsHitTesting(headerVisible)
                .accessibilityHidden(!headerVisible)
            }
            .overlay(alignment: .bottom) {
                footer.padding(.horizontal, 22).padding(.bottom, 18).padding(.top, 28)
                    .frame(maxWidth: .infinity)
                    .background {
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.65), location: 0.3),
                            .init(color: .black.opacity(0.9), location: 0.6),
                            .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
                            .contentShape(Rectangle()).onTapGesture { }
                            .accessibilityHidden(true)
                            .padding(.top, -35)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { view in
                        view.opacity(controlsVisible ? 1 : 0)
                    }
                    .allowsHitTesting(controlsVisible)
                    .accessibilityHidden(!controlsVisible)
            }
            .overlay(alignment: .trailing) {
                if !player.lines.isEmpty {
                    LyricScrollIndicator(state: scrollState, onScroll: { offset in
                        browsing = true
                        lyricScrollPosition.scrollTo(y: offset)
                    }, onInteraction: { dragging in
                        scrollbarDragging = dragging
                        if dragging { revealScrollbar() } else { hideScrollbarAfterDelay() }
                    })
                    .frame(width: 16)
                    .padding(.top, 84)
                    .padding(.bottom, 100)
                    .padding(.trailing, 7)
                    .opacity(scrollbarVisible ? 1 : 0)
                    .allowsHitTesting(scrollbarVisible)
                    .accessibilityHidden(!scrollbarVisible)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: scrollbarVisible)
                }
            }
            .overlay(alignment: .bottom) {
                if browsing && !timingToastVisible && !player.lines.isEmpty && !showingRecordingPicker && !player.loading && player.connectionError == nil {
                    Button {
                        browsing = false
                        followRequest += 1
                    } label: {
                        Label("Follow lyrics", systemImage: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(FollowLyricsButtonStyle(tint: accent))
                    .padding(.bottom, controlsVisible ? 100 : 12)
                }
            }
            .overlay(alignment: .bottom) {
                timingToast
                    .padding(.bottom, controlsVisible ? 106 : 18)
                    .opacity(timingToastVisible ? 1 : 0)
                    .accessibilityHidden(!timingToastVisible)
            }
    }

    private var timingToast: some View {
        let motionReduced = reduceMotion
        let description = player.offset == 0 ? "Lyrics timing 0.0s" :
            String(format: "Lyrics %@ %.1fs", player.offset > 0 ? "advanced" : "delayed", abs(player.offset))
        return Label(description, systemImage: "clock.arrow.2.circlepath")
            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            .contentTransition(.numericText())
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background {
                Capsule().fill(.thickMaterial)
                    .overlay { Capsule().fill(accent.opacity(0.14)) }
            }
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
            .keyframeAnimator(initialValue: 1.0, trigger: player.timingAdjustmentCount) { content, scale in
                content.scaleEffect(motionReduced ? 1 : scale)
            } keyframes: { _ in
                CubicKeyframe(1.06, duration: 0.08)
                CubicKeyframe(0.98, duration: 0.1)
                CubicKeyframe(1, duration: 0.12)
            }
            .allowsHitTesting(false)
    }

    @ViewBuilder private var panelBackground: some View {
        if #available(macOS 26.0, *) {
            Color.black.opacity(0.35)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.35))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let artwork = player.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Image(systemName: "waveform").font(.system(size: 19, weight: .medium))
                            .foregroundStyle(accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.06))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("Album artwork")
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.track?.title ?? "Overlyric")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(player.track?.artist ?? "A little closer to the music")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
            }
            .overlay { if !popover { WindowDragHandle() } }
            HStack(spacing: 6) {
                if !popover {
                    headerIcon(app.pinned ? "pin.fill" : "pin", label: app.pinned ? "Unpin from top" : "Pin on top") {
                        app.pinned.toggle()
                    }.foregroundStyle(app.pinned ? accent : .white.opacity(0.55))
                }
                headerIcon(popover ? "rectangle.on.rectangle" : "menubar.rectangle", label: popover ? "Switch to overlay" : "Switch to menu bar") {
                    app.mode = popover ? .overlay : .menuBar
                }
                OptionsButton(player: player, app: app, onSearch: { showingLyricsSearch = true }).frame(width: 28, height: 28)
                    .background(.white.opacity(0.12), in: Circle())
                if popover {
                    headerIcon("xmark", label: "Close lyrics") { app.closeSurface() }
                }
            }.font(.system(size: 12, weight: .medium)).padding(.top, 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18)) { view in
                    view.opacity(headerActionsVisible ? 1 : 0)
                }
                .allowsHitTesting(headerActionsVisible)
                .accessibilityHidden(!headerActionsVisible)
        }
    }

    @ViewBuilder private var lyricBody: some View {
        if let error = player.connectionError {
            emptyState(icon: "lock.shield", title: "Connect to Spotify", detail: error) {
                Button("Reconnect") { player.reconnect() }.buttonStyle(FlatButtonStyle())
            }
        } else if player.loading {
            VStack(spacing: 14) {
                ProgressView().controlSize(.small)
                Text("Finding the words…").font(.system(size: 13)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showingRecordingPicker && !player.candidates.isEmpty {
            recordingPicker
        } else if !player.lines.isEmpty {
            syncedLyrics
        } else if let plain = player.plainLyrics {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("UNSYNCED LYRICS").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(accent)
                    Text(plain).font(.system(size: layout.fontSize(base: fontSize - 3), weight: .semibold, design: .default)).lineSpacing(10 * layout.scale)
                        .textSelection(.enabled)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)

            }.scrollIndicators(.never)
        } else if player.instrumental {
            instrumentalState
        } else {
            emptyState(icon: player.track == nil ? "music.note" : "text.quote",
                title: player.message, detail: player.detail) {
                if player.track == nil {
                    Button("Open Spotify") { NSWorkspace.shared.open(URL(string: "spotify:")!) }.buttonStyle(FlatButtonStyle())
                } else {
                    availabilityActions
                    .opacity(availabilityActionsVisible ? 1 : 0)
                    .allowsHitTesting(availabilityActionsVisible)
                    .accessibilityHidden(!availabilityActionsVisible)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: surfaceHovered || app.overlayHovered)
                }
            }
        }
    }

    private var instrumentalState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .light)).foregroundStyle(accent.opacity(0.8))
                .padding(.bottom, 6)
            VStack(spacing: 8) {
                Text(player.message)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .help(player.detail)
                Text("No lyrics on this one.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            if availabilityActionsVisible {
                availabilityActions.padding(.top, 6).transition(.opacity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: availabilityActionsVisible)
    }

    private var availabilityActions: some View {
        HStack(spacing: 7) {
            Button { showingLyricsSearch = true } label: {
                Label("Search manually", systemImage: "magnifyingglass").fixedSize()
            }.buttonStyle(FlatButtonStyle(compact: true))
            Button { player.loadLyrics() } label: {
                Label("Check again", systemImage: "arrow.clockwise").fixedSize()
            }.buttonStyle(FlatButtonStyle(compact: true))
            Button { showingAvailabilityInfo.toggle() } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(FlatButtonStyle(compact: true))
            .help(player.detail).accessibilityLabel("Lyric availability information")
            .popover(isPresented: $showingAvailabilityInfo) {
                Text(player.detail).font(.system(size: 12)).lineSpacing(4).padding(16).frame(width: 260)
            }
        }
    }

    private var alternateRecordingNotice: some View {
        HStack(spacing: 8) {
            Button { showingRecordingPicker = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wrong lyrics?").font(.system(size: 12, weight: .semibold))
                    Text("Click to choose a different one").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.leading, 12)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { player.dismissAlternateRecordingNotice() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).padding(12)
            }.buttonStyle(.plain).help("Dismiss for this song").accessibilityLabel("Dismiss recording suggestion for this song")
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recordingPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Choose a recording").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button { showingRecordingPicker = false } label: {
                        Image(systemName: "xmark").padding(6)
                    }.buttonStyle(.plain).help("Back to lyrics").accessibilityLabel("Back to lyrics")
                }
                Text("Choose the version that fits. Timing can vary between recordings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                ForEach(player.candidates) { record in
                    Button { player.chooseRecording(record); showingRecordingPicker = false } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.albumName.isEmpty ? record.trackName : record.albumName).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                Text(record.instrumental && !record.hasLyrics ? "Instrumental" : record.syncedLyrics?.isEmpty == false ? "Synced lyrics" : "Plain lyrics")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if player.selectedRecordingID == record.id {
                                Image(systemName: "checkmark").foregroundStyle(.white.opacity(0.8))
                            }
                            Text(time(record.duration)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                        }.padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }.padding(24).padding(.bottom, 100)
        }.scrollIndicators(.never)
    }
    private var syncedLyrics: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(player.lines) { line in
                            let active = line.id == player.activeIndex
                            let emphasis = LyricEmphasis.at(line.id, activeIndex: player.activeIndex)
                            Button { player.seek(line.time - player.offset); browsing = false } label: {
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: layout.fontSize(base: fontSize + 3), weight: .semibold, design: .default))
                                    .lineSpacing(4 * layout.scale).multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .foregroundStyle(.white.opacity(emphasis.opacity))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .scaleEffect(active ? 1 : 0.86, anchor: .leading)
                                    .blur(radius: browsing ? 0 : layout.blurRadius(base: emphasis.blur, fontSize: fontSize + 3))
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: browsing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focusable(false).focusEffectDisabled()
                            .help("Play from this line")
                            .accessibilityLabel(line.text.isEmpty ? "Instrumental break" : line.text)
                            .accessibilityAddTraits(active ? .isSelected : [])
                            .padding(.bottom, line.id == player.lines.last?.id ? 0 : layout.rowSpacing(after: line.id, activeIndex: player.activeIndex))
                            .animation(lineAnimation, value: player.activeIndex)
                            .id(line.id)
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, geometry.size.height / 2)
                }
                .scrollIndicators(.never)
                .scrollPosition($lyricScrollPosition)
                .onScrollGeometryChange(for: LyricScrollMetrics.self) { geometry in
                    LyricScrollMetrics(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        contentHeight: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom,
                        viewportHeight: geometry.containerSize.height)
                } action: { _, metrics in scrollState.metrics = metrics }
                .onScrollPhaseChange { _, phase in
                    if phase == .tracking || phase == .interacting || phase == .decelerating {
                        revealScrollbar()
                        if phase == .interacting { browsing = true }
                    } else if phase == .idle {
                        hideScrollbarAfterDelay()
                    }
                }
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.94), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                }
                .onChange(of: player.activeIndex) { _, _ in
                    guard !browsing, let index = player.activeIndex ?? player.lines.first?.id else { return }
                    withAnimation(lineAnimation) { proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.42)) }
                }
                .task(id: geometry.size) {
                    // Let wrapping settle before restoring the active line's anchor.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if !browsing, let index = player.activeIndex ?? player.lines.first?.id {
                        proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.42))
                    }
                }
                .onChange(of: player.track?.id) { _, _ in browsing = false }
                .onChange(of: followRequest) { _, _ in
                    if let index = player.activeIndex ?? player.lines.first?.id {
                        withAnimation(lineAnimation) {
                            proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.42))
                        }
                    }
                }
            }
        }
    }

    private func revealScrollbar() {
        scrollbarHideTask?.cancel()
        scrollbarVisible = true
    }

    private func hideScrollbarAfterDelay() {
        guard !scrollbarDragging else { return }
        scrollbarHideTask?.cancel()
        scrollbarHideTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(900)) }
            catch { return }
            guard !Task.isCancelled, !scrollbarDragging else { return }
            scrollbarVisible = false
        }
    }

    private var footer: some View {
        PlaybackFooter(player: player, clock: player.clock, scrubbing: $scrubbing, scrubPosition: $scrubPosition)
    }

    private func headerIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        icon(symbol, label: label, action: action)
            .frame(width: 28, height: 28)
            .background(.white.opacity(0.12), in: Circle())
    }

    private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(minWidth: 18, minHeight: 22).contentShape(Rectangle()) }
            .buttonStyle(.plain).focusable(false).focusEffectDisabled().help(label).accessibilityLabel(label)
    }

    private func emptyState<Actions: View>(icon: String, title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(accent.opacity(0.8)).padding(.bottom, 8)
            Text(title).font(.system(size: 20, weight: .semibold, design: .rounded))
                .help(detail)
            Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center).lineSpacing(4)
            actions().font(.system(size: 12)).padding(.top, 6)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
