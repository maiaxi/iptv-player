import Foundation

enum ContentKind: String, Codable, CaseIterable, Hashable {
    case live, movie, series

    var title: String {
        switch self {
        case .live: "TV ao vivo"
        case .movie: "Filmes"
        case .series: "Séries"
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .movie: "film"
        case .series: "tv"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Codable {
    /// Unique across sources: "<sourceID>:<kind>:<nativeID>"
    let id: String
    let name: String
    let logo: URL?
    let categoryID: String
    let kind: ContentKind
    /// nil for Xtream series, which need their episode list loaded first.
    let streamURL: URL?
    let xtreamID: Int?
    let rating: String?
    var userAgent: String? = nil
    var referrer: String? = nil
    /// XMLTV channel id (`tvg-id` / `epg_channel_id`).
    var epgID: String? = nil

    var isPlayable: Bool { streamURL != nil }
}

struct MediaCategory: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let kind: ContentKind
}

struct Episode: Identifiable, Hashable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let plot: String?
    let image: URL?
    let duration: String?
    let streamURL: URL
}

struct SeriesInfo {
    let plot: String?
    let cast: String?
    let genre: String?
    let releaseDate: String?
    let cover: URL?
    let backdrop: URL?
    let episodesBySeason: [Int: [Episode]]
}

struct EPGEntry: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String?
    let start: Date
    let end: Date

    var progress: Double { progress(at: Date()) }

    func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / total, 0), 1)
    }
}

struct AccountInfo: Codable, Hashable {
    var expiresAt: Date?
    var maxConnections: Int?
    var status: String?
    var outputFormat: String
}

// MARK: - Sources

enum SourceKind: Codable, Hashable {
    case m3u(url: URL)
    case xtream(server: URL, username: String, password: String)
}

struct Source: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: SourceKind

    var subtitle: String {
        switch kind {
        case .m3u(let url): url.isFileURL ? url.lastPathComponent : (url.host() ?? url.absoluteString)
        case .xtream(let server, let username, _): "\(username) @ \(server.host() ?? server.absoluteString)"
        }
    }
}

/// Everything loaded from one source, cached on disk between launches.
struct LibraryData: Codable {
    var items: [MediaItem]
    var categories: [MediaCategory]
    var account: AccountInfo?
    var fetchedAt: Date
    /// XMLTV guide for the whole source.
    var epgURL: URL? = nil
}
