import AppKit
import SwiftUI

struct PlayerView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player

    @State private var controlsVisible = true
    @State private var hoveringControls = false
    @State private var showChannels = false
    @State private var hideTask: Task<Void, Never>?
    @State private var windowState = WindowState()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black

            MPVVideoView(controller: player.mpv)

            statusOverlay

            // Catches clicks/double-clicks over the video.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFullScreen() }
                .onTapGesture { player.togglePause(); poke() }

            if controlsVisible {
                VStack(spacing: 0) {
                    TopBar()
                    Spacer()
                    ControlBar(showChannels: $showChannels, isFullScreen: windowState.isFullScreen,
                               toggleFullScreen: toggleFullScreen)
                        .onHover { hoveringControls = $0; poke() }
                }
                .transition(.opacity)
            }

            HStack(spacing: 0) {
                Spacer()
                if showChannels {
                    ChannelDrawer(close: { showChannels = false })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .onHover { hoveringControls = $0; poke() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .animation(.spring(duration: 0.35), value: showChannels)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .background(WindowReader(state: windowState))
        .navigationTitle(player.current?.name ?? "Player")
        .onContinuousHover { phase in
            if case .active = phase { poke() }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down, action: handleKey)
        .onAppear {
            focused = true
            poke()
        }
        .onDisappear {
            hideTask?.cancel()
            player.stop()
        }
        .onChange(of: player.isPaused) { poke() }
        .task(id: player.current?.id) {
            guard let item = player.current, item.kind == .live else { return }
            while !Task.isCancelled {
                player.epg = await library.epg(for: item)
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let error = player.errorMessage {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)
                Text("No Signal").font(.title2.weight(.semibold))
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                HStack {
                    Button("Try Again") { player.retry() }
                    if player.queue.count > 1 {
                        Button("Next Channel") { player.next() }
                    }
                }
                .controlSize(.large)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .zIndex(2)
        } else if player.isLoading || player.isBuffering {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(.white)
                if player.isBuffering, let pct = player.bufferPercent {
                    Text("Loading \(pct)%").font(.callout).foregroundStyle(.white.opacity(0.8))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func poke() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !hoveringControls, !player.isPaused, !showChannels, player.errorMessage == nil else { return }
            controlsVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func toggleFullScreen() {
        windowState.toggleFullScreen()
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .space: player.togglePause()
        case .leftArrow: player.seek(by: press.modifiers.contains(.shift) ? -60 : -10)
        case .rightArrow: player.seek(by: press.modifiers.contains(.shift) ? 60 : 10)
        case .upArrow: player.previous()
        case .downArrow: player.next()
        case .escape:
            if showChannels { showChannels = false }
            else if windowState.isFullScreen { toggleFullScreen() }
            else { return .ignored }
        default:
            switch press.characters.lowercased() {
            case "f": toggleFullScreen()
            case "m": player.toggleMute()
            case "l", "c": showChannels.toggle()
            case "+", "=": player.setVolume(player.volume + 5)
            case "-": player.setVolume(player.volume - 5)
            default: return .ignored
            }
        }
        poke()
        return .handled
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let item = player.current, item.kind == .live {
                RemoteImage(url: item.logo) { EmptyView() }
                    .frame(width: 56, height: 38)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.name ?? "")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                if let subtitle = player.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer()
            if let size = player.videoSize {
                Text(qualityLabel(size))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.6)))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
        // Leave room for the traffic lights.
        .padding(.leading, 84)
        .padding(.trailing, 24)
        .padding(.top, 14)
        .padding(.bottom, 40)
        .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
    }

    private func qualityLabel(_ size: CGSize) -> String {
        switch size.height {
        case 2000...: "4K"
        case 1000...: "1080p"
        case 700...: "720p"
        default: "SD"
        }
    }
}

// MARK: - Control bar

private struct ControlBar: View {
    @Environment(PlayerModel.self) private var player
    @Binding var showChannels: Bool
    let isFullScreen: Bool
    let toggleFullScreen: () -> Void
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 12) {
            if player.isLive {
                liveInfo
            } else {
                timeline
            }
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Button { player.toggleMute() } label: {
                        Image(systemName: volumeSymbol).frame(width: 22)
                    }
                    Slider(value: Binding(get: { player.isMuted ? 0 : player.volume }, set: { player.setVolume($0) }), in: 0...100)
                        .frame(width: 96)
                        .controlSize(.small)
                }
                Spacer()
                if player.queue.count > 1 {
                    Button { player.previous() } label: { Image(systemName: player.isLive ? "chevron.up" : "backward.end.fill") }
                        .help(player.isLive ? LocalizedStringKey("Previous channel (↑)") : "Previous")
                }
                if !player.isLive {
                    Button { player.seek(by: -10) } label: { Image(systemName: "gobackward.10") }
                }
                Button { player.togglePause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 26))
                        .frame(width: 36)
                }
                if !player.isLive {
                    Button { player.seek(by: 10) } label: { Image(systemName: "goforward.10") }
                }
                if player.queue.count > 1 {
                    Button { player.next() } label: { Image(systemName: player.isLive ? "chevron.down" : "forward.end.fill") }
                        .help(player.isLive ? LocalizedStringKey("Next channel (↓)") : "Next")
                }
                Spacer()
                HStack(spacing: 16) {
                    tracksMenu
                    if player.queue.count > 1 {
                        Button { showChannels.toggle() } label: { Image(systemName: "list.bullet") }
                            .help("List (L)")
                    }
                    Button(action: toggleFullScreen) {
                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .help(isFullScreen ? LocalizedStringKey("Exit full screen (F)") : "Full screen (F)")
                }
                .frame(width: 132, alignment: .trailing)
            }
            .font(.system(size: 17, weight: .semibold))
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .frame(maxWidth: 760)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var volumeSymbol: String {
        if player.isMuted || player.volume == 0 { return "speaker.slash.fill" }
        return player.volume < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private var timeline: some View {
        HStack(spacing: 12) {
            Text(format(scrub ?? player.position)).monospacedDigit()
            Slider(
                value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let scrub {
                        player.seek(to: scrub)
                        self.scrub = nil
                    }
                }
            )
            .controlSize(.small)
            Text("-" + format(max(player.duration - (scrub ?? player.position), 0))).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.8))
    }

    private var liveInfo: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("LIVE").font(.caption.weight(.heavy))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.red.opacity(0.22), in: Capsule())

            if let now = player.epg.first(where: { $0.start <= Date() && $0.end > Date() }) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(now.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    }
                    ProgressView(value: now.progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                    if let next = player.epg.first(where: { $0.start >= now.end }) {
                        Text("Up next: \(next.title)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            } else {
                Spacer()
            }
        }
    }

    private var tracksMenu: some View {
        Menu {
            if !player.audioTracks.isEmpty {
                Picker("Audio", selection: Binding(get: { player.selectedAudio ?? -1 }, set: { player.selectAudio($0) })) {
                    ForEach(player.audioTracks) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.inline)
            }
            Picker("Subtitles", selection: Binding(get: { player.selectedSubtitle ?? -1 }, set: { player.selectSubtitle($0 < 0 ? nil : $0) })) {
                Text("Off").tag(-1)
                ForEach(player.subtitleTracks) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "captions.bubble")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Audio and subtitles")
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Channel drawer

private struct ChannelDrawer: View {
    @Environment(PlayerModel.self) private var player
    @Environment(LibraryStore.self) private var library
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(player.subtitle ?? String(localized: "List")).font(.headline).lineLimit(1)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .padding(.top, 24)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                            row(item, number: index + 1)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                }
                .onAppear { proxy.scrollTo(player.current?.id, anchor: .center) }
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    private func row(_ item: MediaItem, number: Int) -> some View {
        let isCurrent = item.id == player.current?.id
        return Button {
            player.play(item, queue: player.queue, subtitle: player.subtitle)
        } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                if item.kind == .live {
                    RemoteImage(url: item.logo) { Monogram(name: item.name).clipShape(RoundedRectangle(cornerRadius: 4)) }
                        .frame(width: 40, height: 28)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).lineLimit(1)
                    if item.kind == .live, !library.guide.isEmpty {
                        NowPlayingLine(program: library.currentProgram(for: item), clock: library.clock)
                    }
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "waveform").foregroundStyle(Color.accentColor).symbolEffect(.variableColor.iterative)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(isCurrent ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window access

/// Tracks the hosting window and its full-screen state.
@MainActor
@Observable
final class WindowState {
    weak var window: NSWindow?
    private(set) var isFullScreen = false
    private(set) var isTransitioning = false
    private var observers: [NSObjectProtocol] = []

    func attach(_ window: NSWindow?) {
        guard window !== self.window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        self.window = window
        guard let window else { return }
        window.backgroundColor = .black
        isFullScreen = window.styleMask.contains(.fullScreen)

        let center = NotificationCenter.default
        let events: [(Notification.Name, Bool?, Bool)] = [
            (NSWindow.willEnterFullScreenNotification, nil, true),
            (NSWindow.didEnterFullScreenNotification, true, false),
            (NSWindow.willExitFullScreenNotification, nil, true),
            (NSWindow.didExitFullScreenNotification, false, false),
        ]
        for (name, fullScreen, transitioning) in events {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let fullScreen { self.isFullScreen = fullScreen }
                    self.isTransitioning = transitioning
                }
            })
        }
    }

    func toggleFullScreen() {
        // A click during the animation would queue a second toggle and undo the first.
        guard !isTransitioning, let window = window ?? NSApp.keyWindow else { return }
        window.toggleFullScreen(nil)
        // Safety net in case a transition fails and no "did" notification arrives.
        Task { [weak self, weak window] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let window, isTransitioning else { return }
            isTransitioning = false
            isFullScreen = window.styleMask.contains(.fullScreen)
        }
    }
}

private struct WindowReader: NSViewRepresentable {
    let state: WindowState

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindowChange = { [weak state] in state?.attach($0) }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
