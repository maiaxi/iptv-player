import Foundation
import Observation

enum CategoryFilter {
    static let all = "all"
}

enum SidebarItem: Hashable {
    case kind(ContentKind)
    case favorites
    case recents
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var sources: [Source] = Storage.loadSources()
    private(set) var selectedSourceID: UUID?
    private(set) var library: LibraryData?
    private(set) var isLoading = false
    var loadError: String?
    var isAddingSource = false

    private(set) var favorites: Set<String>
    private(set) var recents: [String]

    /// Programme guide keyed by lowercased XMLTV channel id.
    private(set) var guide: [String: [EPGEntry]] = [:]
    /// Ticks every 30 s so "now playing" and progress bars stay current.
    private(set) var clock = Date()
    private var guideTask: Task<Void, Never>?
    private var guideKey: String?
    private var guideLoadedAt = Date.distantPast

    private var itemsByKind: [ContentKind: [MediaItem]] = [:]
    private var itemsByCategory: [String: [MediaItem]] = [:]
    private var itemsByID: [String: MediaItem] = [:]
    private var loadTask: Task<Void, Never>?

    private static let cacheMaxAge: TimeInterval = 12 * 3600

    init() {
        let defaults = UserDefaults.standard
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        recents = defaults.stringArray(forKey: "recents") ?? []
        let saved = defaults.string(forKey: "selectedSource").flatMap(UUID.init)
        if let id = saved ?? sources.first?.id { select(sourceID: id) }

        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                clock = Date()
                if clock.timeIntervalSince(guideLoadedAt) > 3 * 3600 { loadGuide(force: true) }
            }
        }
    }

    var selectedSource: Source? { sources.first { $0.id == selectedSourceID } }

    // MARK: Sources

    func select(sourceID: UUID) {
        guard sources.contains(where: { $0.id == sourceID }) else { return }
        selectedSourceID = sourceID
        UserDefaults.standard.set(sourceID.uuidString, forKey: "selectedSource")
        apply(nil)
        load(force: false)
    }

    func add(_ source: Source) {
        sources.append(source)
        Storage.saveSources(sources)
        select(sourceID: source.id)
    }

    func update(_ source: Source) {
        guard let i = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[i] = source
        Storage.saveSources(sources)
        Storage.removeLibrary(for: source.id)
        if source.id == selectedSourceID { load(force: true) }
    }

    func remove(_ source: Source) {
        sources.removeAll { $0.id == source.id }
        Storage.saveSources(sources)
        Storage.removeLibrary(for: source.id)
        if selectedSourceID == source.id {
            selectedSourceID = nil
            apply(nil)
            if let first = sources.first { select(sourceID: first.id) }
        }
    }

    func refresh() {
        guideKey = nil
        load(force: true)
    }

    private func load(force: Bool) {
        guard let source = selectedSource else { return }
        loadTask?.cancel()
        loadError = nil
        isLoading = true
        loadTask = Task {
            if !force, let cached = await Task.detached(operation: { Storage.loadLibrary(for: source.id) }).value {
                guard !Task.isCancelled else { return }
                apply(cached)
                if Date().timeIntervalSince(cached.fetchedAt) < Self.cacheMaxAge {
                    isLoading = false
                    return
                }
            }
            do {
                let data = try await Self.fetch(source)
                guard !Task.isCancelled else { return }
                apply(data)
                Task.detached(priority: .background) { Storage.saveLibrary(data, for: source.id) }
            } catch {
                guard !Task.isCancelled else { return }
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }

    private nonisolated static func fetch(_ source: Source) async throws -> LibraryData {
        switch source.kind {
        case .xtream(let server, let username, let password):
            return try await XtreamClient(server: server, username: username, password: password, sourceID: source.id).loadLibrary()
        case .m3u(let url):
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                var req = URLRequest(url: url, timeoutInterval: 90)
                req.setValue(PlayerDefaults.userAgent, forHTTPHeaderField: "User-Agent")
                let (body, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw XtreamError(message: String(localized: "Couldn’t download the playlist (error \(http.statusCode))."))
                }
                data = body
            }
            let text = String(decoding: data, as: UTF8.self)
            guard text.contains("#EXTINF") || text.contains("://") else {
                throw XtreamError(message: String(localized: "This file doesn’t look like an M3U playlist."))
            }
            return M3UParser.parse(text, sourceID: source.id)
        }
    }

    private func apply(_ data: LibraryData?) {
        library = data
        let items = data?.items ?? []
        itemsByKind = Dictionary(grouping: items, by: \.kind)
        itemsByCategory = Dictionary(grouping: items, by: \.categoryID)
        itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        loadGuide(force: false)
    }

    // MARK: Programme guide

    private func loadGuide(force: Bool) {
        guard let source = selectedSource, let data = library, let url = data.epgURL else {
            guideTask?.cancel()
            guide = [:]
            guideKey = nil
            return
        }
        let key = "\(source.id)|\(url.absoluteString)"
        guard force || key != guideKey else { return }
        if key != guideKey { guide = [:] }
        guideKey = key
        guideLoadedAt = Date()
        let channels = Set(data.items.compactMap(\.epgID))
        guard !channels.isEmpty else { return }

        guideTask?.cancel()
        guideTask = Task {
            let parsed = await Task.detached(priority: .utility) {
                await Self.fetchGuide(url: url, sourceID: source.id, channels: channels, useCache: !force)
            }.value
            guard !Task.isCancelled, let parsed else { return }
            guide = parsed
        }
    }

    private nonisolated static func fetchGuide(url: URL, sourceID: UUID, channels: Set<String>, useCache: Bool) async -> [String: [EPGEntry]]? {
        let cacheFile = Storage.cacheDir.appending(path: "\(sourceID)-epg.xml")
        var raw: Data?
        if useCache,
           let modified = (try? FileManager.default.attributesOfItem(atPath: cacheFile.path()))?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 6 * 3600 {
            raw = try? Data(contentsOf: cacheFile)
        }
        if raw == nil {
            if url.isFileURL {
                raw = try? Data(contentsOf: url)
            } else {
                var req = URLRequest(url: url, timeoutInterval: 120)
                req.setValue(PlayerDefaults.userAgent, forHTTPHeaderField: "User-Agent")
                if let (body, response) = try? await URLSession.shared.data(for: req),
                   (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                   !body.isEmpty {
                    raw = body
                    try? body.write(to: cacheFile, options: .atomic)
                }
            }
        }
        guard let raw else { return nil }
        let now = Date()
        return XMLTVParser.parse(raw, channels: channels, from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(24 * 3600))
    }

    func schedule(for item: MediaItem) -> [EPGEntry] {
        item.epgID.flatMap { guide[$0.lowercased()] } ?? []
    }

    func currentProgram(for item: MediaItem) -> EPGEntry? {
        guard item.kind == .live else { return nil }
        return schedule(for: item).first { $0.start <= clock && $0.end > clock }
    }

    // MARK: Queries

    func count(for kind: ContentKind) -> Int { itemsByKind[kind]?.count ?? 0 }

    func categories(for kind: ContentKind) -> [MediaCategory] {
        (library?.categories ?? []).filter { $0.kind == kind && itemsByCategory[$0.id] != nil }
    }

    func count(in category: MediaCategory) -> Int { itemsByCategory[category.id]?.count ?? 0 }

    /// `filter` is `CategoryFilter.all`, a category id (for a kind) or a kind's raw value (for favorites/recents).
    func items(for sidebar: SidebarItem, filter: String, search: String) -> [MediaItem] {
        var base: [MediaItem]
        switch sidebar {
        case .kind(let kind):
            base = filter == CategoryFilter.all ? itemsByKind[kind] ?? [] : itemsByCategory[filter] ?? []
        case .favorites:
            base = ContentKind.allCases.flatMap { (itemsByKind[$0] ?? []).filter { favorites.contains($0.id) } }
        case .recents:
            base = recents.compactMap { itemsByID[$0] }
        }
        if sidebar == .favorites || sidebar == .recents, let kind = ContentKind(rawValue: filter) {
            base = base.filter { $0.kind == kind }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func categoryName(for item: MediaItem) -> String? {
        library?.categories.first { $0.id == item.categoryID }?.name
    }

    // MARK: Favorites & recents

    func isFavorite(_ item: MediaItem) -> Bool { favorites.contains(item.id) }

    func toggleFavorite(_ item: MediaItem) {
        if favorites.remove(item.id) == nil { favorites.insert(item.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    func markRecent(_ item: MediaItem) {
        recents.removeAll { $0 == item.id }
        recents.insert(item.id, at: 0)
        if recents.count > 50 { recents.removeLast(recents.count - 50) }
        UserDefaults.standard.set(recents, forKey: "recents")
    }

    // MARK: Xtream extras

    private var xtreamClient: XtreamClient? {
        guard let source = selectedSource, case .xtream(let server, let username, let password) = source.kind else { return nil }
        return XtreamClient(server: server, username: username, password: password, sourceID: source.id)
    }

    func seriesInfo(for item: MediaItem) async throws -> SeriesInfo? {
        guard let client = xtreamClient, let id = item.xtreamID else { return nil }
        return try await client.seriesInfo(seriesID: id)
    }

    func epg(for item: MediaItem) async -> [EPGEntry] {
        let fromGuide = schedule(for: item).filter { $0.end > Date() }
        if !fromGuide.isEmpty { return fromGuide }
        guard item.kind == .live, let client = xtreamClient, let id = item.xtreamID else { return [] }
        return (try? await client.shortEPG(streamID: id)) ?? []
    }
}
