import Foundation
import Observation

struct Track: Identifiable, Hashable {
    let id: Int
    let title: String
}

@MainActor
@Observable
final class PlayerModel {
    static let shared = PlayerModel()

    let mpv = MPVController()

    private(set) var current: MediaItem?
    private(set) var subtitle: String?
    private(set) var queue: [MediaItem] = []

    private(set) var isPaused = false
    private(set) var isLoading = false
    private(set) var isBuffering = false
    private(set) var bufferPercent: Int?
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var volume: Double
    private(set) var isMuted = false
    private(set) var videoSize: CGSize?
    private(set) var errorMessage: String?

    private(set) var audioTracks: [Track] = []
    private(set) var subtitleTracks: [Track] = []
    private(set) var selectedAudio: Int?
    private(set) var selectedSubtitle: Int?

    var epg: [EPGEntry] = []

    private var retries = 0
    private var retryTask: Task<Void, Never>?

    var isLive: Bool { current?.kind == .live || duration <= 0 }
    var currentIndex: Int? { current.flatMap { c in queue.firstIndex { $0.id == c.id } } }

    private init() {
        volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 100
        mpv.setDouble("volume", volume)
        mpv.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: Playback

    func play(_ item: MediaItem, queue: [MediaItem], subtitle: String? = nil) {
        guard let url = item.streamURL else { return }
        current = item
        self.subtitle = subtitle
        self.queue = queue.filter(\.isPlayable)
        errorMessage = nil
        retries = 0
        retryTask?.cancel()
        position = 0
        duration = 0
        epg = []
        videoSize = nil
        isLoading = true
        mpv.setFlag("pause", false)
        mpv.load(url, userAgent: item.userAgent, referrer: item.referrer)
    }

    func stop() {
        retryTask?.cancel()
        mpv.stop()
        current = nil
        isLoading = false
        errorMessage = nil
    }

    func retry() {
        guard let current else { return }
        play(current, queue: queue, subtitle: subtitle)
    }

    func togglePause() { mpv.setFlag("pause", !isPaused) }

    func seek(to seconds: Double) {
        guard !isLive else { return }
        position = seconds
        mpv.command(["seek", String(seconds), "absolute+keyframes"])
    }

    func seek(by seconds: Double) {
        guard !isLive else { return }
        mpv.command(["seek", String(seconds), "relative"])
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 150)
        mpv.setDouble("volume", volume)
        if isMuted, value > 0 { mpv.setFlag("mute", false) }
        UserDefaults.standard.set(volume, forKey: "volume")
    }

    func toggleMute() { mpv.setFlag("mute", !isMuted) }

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ delta: Int) {
        guard let index = currentIndex, !queue.isEmpty else { return }
        let target = (index + delta + queue.count) % queue.count
        play(queue[target], queue: queue, subtitle: subtitle)
    }

    func selectAudio(_ id: Int) { mpv.setString("aid", String(id)) }
    func selectSubtitle(_ id: Int?) { mpv.setString("sid", id.map(String.init) ?? "no") }

    func shutdown() { mpv.shutdown() }

    // MARK: Events

    private func handle(_ event: MPVEvent) {
        switch event {
        case .startFile:
            isLoading = true
        case .fileLoaded:
            isLoading = false
            errorMessage = nil
            reloadTracks()
        case .endFile(let error, let endOfFile):
            guard current != nil else { return }
            if current?.kind == .live, retries < 3 {
                // Live streams drop all the time; reconnect quietly a few times before giving up.
                retries += 1
                isLoading = true
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled, let self, let item = current, let url = item.streamURL else { return }
                    mpv.load(url, userAgent: item.userAgent, referrer: item.referrer)
                }
            } else if let error {
                isLoading = false
                errorMessage = "Não foi possível reproduzir este conteúdo (\(error))."
            } else if endOfFile, current?.kind == .series, let index = currentIndex, index + 1 < queue.count {
                next()
            } else {
                isLoading = false
            }
        case .property(let name, let value):
            switch name {
            case "pause": isPaused = value as? Bool ?? false
            case "paused-for-cache": isBuffering = value as? Bool ?? false
            case "cache-buffering-state": bufferPercent = (value as? Int64).map(Int.init)
            case "time-pos": position = value as? Double ?? 0
            case "duration": duration = value as? Double ?? 0
            case "volume": if let v = value as? Double { volume = v }
            case "mute": isMuted = value as? Bool ?? false
            case "track-list/count": reloadTracks()
            case "aid": selectedAudio = (value as? String).flatMap { Int($0) }
            case "sid": selectedSubtitle = (value as? String).flatMap { Int($0) }
            case "video-params/w", "video-params/h":
                if let w = mpv.getString("video-params/w").flatMap(Double.init),
                   let h = mpv.getString("video-params/h").flatMap(Double.init) {
                    videoSize = CGSize(width: w, height: h)
                    retries = 0
                }
            default: break
            }
        }
    }

    private func reloadTracks() {
        let count = Int(mpv.getString("track-list/count") ?? "") ?? 0
        var audio: [Track] = []
        var subs: [Track] = []
        for i in 0..<count {
            guard let type = mpv.getString("track-list/\(i)/type"),
                  let id = mpv.getString("track-list/\(i)/id").flatMap(Int.init) else { continue }
            let lang = mpv.getString("track-list/\(i)/lang")
            let title = mpv.getString("track-list/\(i)/title")
            let label = [title, lang.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }]
                .compactMap { $0 }
                .joined(separator: " · ")
            let track = Track(id: id, title: label.isEmpty ? "Faixa \(id)" : label)
            if type == "audio" { audio.append(track) }
            if type == "sub" { subs.append(track) }
        }
        audioTracks = audio
        subtitleTracks = subs
    }
}
