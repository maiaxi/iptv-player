import Foundation

struct XtreamError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Client for the Xtream Codes `player_api.php` API.
/// Responses are loosely typed (numbers arrive as strings and vice versa), so they're read leniently.
struct XtreamClient {
    let server: URL
    let username: String
    let password: String
    let sourceID: UUID

    private typealias JSON = [String: Any]

    // MARK: Library

    func loadLibrary() async throws -> LibraryData {
        // Sequential on purpose: many panels answer 503 to concurrent requests from one account.
        let account = try await accountInfo()
        let liveCats = try await categories("get_live_categories", kind: .live)
        let live = try await list("get_live_streams")
        // Movies and series are optional: plenty of accounts are live-only, and one failing
        // shouldn't hide the channels.
        let vodCats = (try? await categories("get_vod_categories", kind: .movie)) ?? []
        let vod = (try? await list("get_vod_streams")) ?? []
        let seriesCats = (try? await categories("get_series_categories", kind: .series)) ?? []
        let series = (try? await list("get_series")) ?? []

        let ext = account.outputFormat
        var items: [MediaItem] = []
        for s in live {
            guard let id = int(s["stream_id"]) else { continue }
            items.append(MediaItem(
                id: "\(sourceID):live:\(id)",
                name: string(s["name"]) ?? String(localized: "Channel \(id)"),
                logo: url(s["stream_icon"]),
                categoryID: "live:\(string(s["category_id"]) ?? "")",
                kind: .live,
                streamURL: streamURL("live", id: id, ext: ext),
                xtreamID: id,
                rating: nil,
                epgID: string(s["epg_channel_id"])
            ))
        }
        for s in vod {
            guard let id = int(s["stream_id"]) else { continue }
            items.append(MediaItem(
                id: "\(sourceID):movie:\(id)",
                name: string(s["name"]) ?? String(localized: "Movie \(id)"),
                logo: url(s["stream_icon"]),
                categoryID: "movie:\(string(s["category_id"]) ?? "")",
                kind: .movie,
                streamURL: streamURL("movie", id: id, ext: string(s["container_extension"]) ?? "mp4"),
                xtreamID: id,
                rating: rating(s["rating"])
            ))
        }
        for s in series {
            guard let id = int(s["series_id"]) else { continue }
            items.append(MediaItem(
                id: "\(sourceID):series:\(id)",
                name: string(s["name"]) ?? String(localized: "Series \(id)"),
                logo: url(s["cover"]),
                categoryID: "series:\(string(s["category_id"]) ?? "")",
                kind: .series,
                streamURL: nil,
                xtreamID: id,
                rating: rating(s["rating"])
            ))
        }

        let cats = liveCats + vodCats + seriesCats
        return LibraryData(items: items, categories: cats, account: account, fetchedAt: Date(), epgURL: xmltvURL)
    }

    var xmltvURL: URL? {
        var comps = URLComponents(string: "\(base)/xmltv.php")
        comps?.queryItems = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
        return comps?.url
    }

    func accountInfo() async throws -> AccountInfo {
        guard let root = try await request(nil) as? JSON, let user = root["user_info"] as? JSON else {
            throw XtreamError(message: String(localized: "Invalid response from the server."))
        }
        if int(user["auth"]) == 0 {
            throw XtreamError(message: String(localized: "Incorrect username or password."))
        }
        let formats = (user["allowed_output_formats"] as? [Any])?.compactMap(string) ?? []
        return AccountInfo(
            expiresAt: int(user["exp_date"]).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            maxConnections: int(user["max_connections"]),
            status: string(user["status"]),
            outputFormat: formats.isEmpty || formats.contains("ts") ? "ts" : formats[0]
        )
    }

    // MARK: Details

    func seriesInfo(seriesID: Int) async throws -> SeriesInfo {
        guard let root = try await request("get_series_info", ["series_id": "\(seriesID)"]) as? JSON else {
            throw XtreamError(message: String(localized: "Couldn’t load the series."))
        }
        let info = root["info"] as? JSON ?? [:]
        var seasons: [Int: [Episode]] = [:]
        // `episodes` is usually a dict keyed by season number, occasionally an array of arrays.
        var groups: [[JSON]] = []
        if let dict = root["episodes"] as? [String: Any] {
            groups = dict.values.compactMap { $0 as? [JSON] }
        } else if let arr = root["episodes"] as? [Any] {
            groups = arr.compactMap { $0 as? [JSON] }
        }
        for group in groups {
            for e in group {
                guard let id = string(e["id"]) else { continue }
                let season = int(e["season"]) ?? 1
                let epInfo = e["info"] as? JSON ?? [:]
                let ext = string(e["container_extension"]) ?? "mp4"
                guard let stream = URL(string: "\(base)/series/\(enc(username))/\(enc(password))/\(id).\(ext)") else { continue }
                seasons[season, default: []].append(Episode(
                    id: id,
                    season: season,
                    number: int(e["episode_num"]) ?? 0,
                    title: string(e["title"]) ?? String(localized: "Episode"),
                    plot: string(epInfo["plot"]),
                    image: url(epInfo["movie_image"]),
                    duration: string(epInfo["duration"]),
                    streamURL: stream
                ))
            }
        }
        for key in seasons.keys { seasons[key]?.sort { $0.number < $1.number } }
        let backdrop = (info["backdrop_path"] as? [Any])?.first.flatMap(url)
        return SeriesInfo(
            plot: string(info["plot"]),
            cast: string(info["cast"]),
            genre: string(info["genre"]),
            releaseDate: string(info["releaseDate"]) ?? string(info["release_date"]),
            cover: url(info["cover"]),
            backdrop: backdrop,
            episodesBySeason: seasons
        )
    }

    func shortEPG(streamID: Int) async throws -> [EPGEntry] {
        guard let root = try await request("get_short_epg", ["stream_id": "\(streamID)", "limit": "6"]) as? JSON,
              let listings = root["epg_listings"] as? [JSON] else { return [] }
        return listings.compactMap { l in
            guard let start = int(l["start_timestamp"]), let end = int(l["stop_timestamp"]) else { return nil }
            return EPGEntry(
                title: base64(l["title"]) ?? "",
                description: base64(l["description"]),
                start: Date(timeIntervalSince1970: TimeInterval(start)),
                end: Date(timeIntervalSince1970: TimeInterval(end))
            )
        }
        .filter { $0.end > Date() }
    }

    // MARK: Networking

    private var base: String {
        var s = server.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? s
    }

    private func streamURL(_ type: String, id: Int, ext: String) -> URL? {
        URL(string: "\(base)/\(type)/\(enc(username))/\(enc(password))/\(id).\(ext)")
    }

    private func request(_ action: String?, _ params: [String: String] = [:]) async throws -> Any {
        guard var comps = URLComponents(string: "\(base)/player_api.php") else {
            throw XtreamError(message: String(localized: "Invalid server address."))
        }
        var query = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
        if let action { query.append(URLQueryItem(name: "action", value: action)) }
        query += params.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = query
        guard let url = comps.url else { throw XtreamError(message: String(localized: "Invalid server address.")) }

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue(PlayerDefaults.userAgent, forHTTPHeaderField: "User-Agent")

        // Panels rate-limit aggressively (503/429, sometimes an empty 200), so back off and retry.
        let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
        var attempt = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            let transient = [429, 502, 503, 504].contains(status) || (status == 200 && data.isEmpty)
            if transient, attempt < delays.count {
                try await Task.sleep(for: delays[attempt])
                attempt += 1
                continue
            }
            if !(200..<300).contains(status) {
                throw XtreamError(message: status == 503 || status == 429
                    ? String(localized: "The server is busy (error \(status)). Try again in a moment.")
                    : String(localized: "The server responded with error \(status)."))
            }
            do {
                return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                throw XtreamError(message: String(localized: "The server didn’t return valid data. Check the address."))
            }
        }
    }

    private func categories(_ action: String, kind: ContentKind) async throws -> [MediaCategory] {
        guard let arr = try await request(action) as? [JSON] else { return [] }
        return arr.compactMap { c in
            guard let id = string(c["category_id"]) else { return nil }
            return MediaCategory(id: "\(kind.rawValue):\(id)", name: string(c["category_name"]) ?? id, kind: kind)
        }
    }

    private func list(_ action: String) async throws -> [JSON] {
        (try await request(action) as? [JSON]) ?? []
    }

    // MARK: Lenient field readers

    private func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: s.isEmpty ? nil : s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }

    private func int(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber: n.intValue
        case let s as String: Int(s) ?? Double(s).map { Int($0) }
        default: nil
        }
    }

    private func url(_ v: Any?) -> URL? {
        string(v).flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
    }

    private func rating(_ v: Any?) -> String? {
        guard let s = string(v), let d = Double(s), d > 0 else { return nil }
        return String(format: "%.1f", d)
    }

    private func base64(_ v: Any?) -> String? {
        guard let s = string(v) else { return nil }
        if let data = Data(base64Encoded: s), let decoded = String(data: data, encoding: .utf8) { return decoded }
        return s
    }
}
