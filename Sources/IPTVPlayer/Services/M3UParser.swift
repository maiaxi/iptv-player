import Foundation

enum M3UParser {
    static func parse(_ text: String, sourceID: UUID) -> LibraryData {
        var items: [MediaItem] = []
        var categoryNames: [ContentKind: [String]] = [:]
        var seenCategories = Set<String>()

        var pendingInfo: (name: String, attrs: [String: String])?
        var pendingGroup: String?
        var pendingUA: String?
        var pendingReferrer: String?
        var epgURL: URL?
        var index = 0

        text.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return }

            if line.hasPrefix("#EXTM3U") {
                // `#EXTM3U url-tvg="http://a.xml.gz,http://b.xml"` — use the first guide.
                let attrs = parseExtInf(line).attrs
                epgURL = (attrs["url-tvg"] ?? attrs["x-tvg-url"])?
                    .split(separator: ",").first
                    .flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
            } else if line.hasPrefix("#EXTINF") {
                pendingInfo = parseExtInf(line)
            } else if line.hasPrefix("#EXTGRP:") {
                pendingGroup = String(line.dropFirst("#EXTGRP:".count))
            } else if line.hasPrefix("#EXTVLCOPT:") {
                let opt = line.dropFirst("#EXTVLCOPT:".count)
                if let value = opt.split(separator: "=", maxSplits: 1).last.map(String.init) {
                    if opt.hasPrefix("http-user-agent") { pendingUA = value }
                    if opt.hasPrefix("http-referrer") { pendingReferrer = value }
                }
            } else if !line.hasPrefix("#"), let url = URL(string: line) {
                let info = pendingInfo ?? (name: url.lastPathComponent, attrs: [:])
                let group = info.attrs["group-title"] ?? pendingGroup ?? String(localized: "Uncategorized")
                let kind = kindFor(url: url)
                let categoryID = "\(kind.rawValue):\(group)"
                if seenCategories.insert(categoryID).inserted {
                    categoryNames[kind, default: []].append(group)
                }
                let name = info.name.isEmpty ? (info.attrs["tvg-name"] ?? url.lastPathComponent) : info.name
                items.append(MediaItem(
                    id: "\(sourceID):\(kind.rawValue):\(index)",
                    name: name,
                    logo: info.attrs["tvg-logo"].flatMap { $0.isEmpty ? nil : URL(string: $0) },
                    categoryID: categoryID,
                    kind: kind,
                    streamURL: url,
                    xtreamID: nil,
                    rating: nil,
                    userAgent: pendingUA ?? info.attrs["user-agent"],
                    referrer: pendingReferrer,
                    epgID: info.attrs["tvg-id"].flatMap { $0.isEmpty ? nil : $0 }
                ))
                index += 1
                pendingInfo = nil
                pendingGroup = nil
                pendingUA = nil
                pendingReferrer = nil
            }
        }

        let categories = ContentKind.allCases.flatMap { kind in
            (categoryNames[kind] ?? []).map { MediaCategory(id: "\(kind.rawValue):\($0)", name: $0, kind: kind) }
        }
        return LibraryData(items: items, categories: categories, account: nil, fetchedAt: Date(), epgURL: epgURL)
    }

    /// `#EXTINF:-1 tvg-id="x" tvg-logo="y" group-title="News, World",Channel Name`
    private static func parseExtInf(_ line: String) -> (name: String, attrs: [String: String]) {
        var attrs: [String: String] = [:]
        var inQuotes = false
        var nameStart: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            if c == ",", !inQuotes { nameStart = line.index(after: i); break }
        }
        let header = nameStart.map { line[..<$0] } ?? Substring(line)
        let name = nameStart.map { String(line[$0...]).trimmingCharacters(in: .whitespaces) } ?? ""

        let pattern = #/([A-Za-z0-9\-_]+)="([^"]*)"/#
        for match in header.matches(of: pattern) {
            attrs[String(match.1).lowercased()] = String(match.2)
        }
        return (name, attrs)
    }

    private static func kindFor(url: URL) -> ContentKind {
        let path = url.path().lowercased()
        if path.contains("/movie/") { return .movie }
        if path.contains("/series/") { return .series }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mkv", "avi", "mov", "m4v"].contains(ext) { return .movie }
        return .live
    }
}
