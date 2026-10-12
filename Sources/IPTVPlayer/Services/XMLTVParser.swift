import Foundation

/// Streaming XMLTV parser. Guides are often 10–100 MB, so only programmes for the wanted channels
/// inside a time window are kept. Channel ids are matched case-insensitively.
final class XMLTVParser: NSObject, XMLParserDelegate {
    private let wanted: Set<String>
    private let window: ClosedRange<Date>
    private(set) var guide: [String: [EPGEntry]] = [:]

    private var channel: String?
    private var start: Date?
    private var end: Date?
    private var title = ""
    private var desc = ""
    private var text = ""

    private static let formatters: [DateFormatter] = ["yyyyMMddHHmmss Z", "yyyyMMddHHmmssZ", "yyyyMMddHHmmss"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = $0
        return f
    }

    static func parse(_ data: Data, channels: Set<String>, from: Date, to: Date) -> [String: [EPGEntry]] {
        let delegate = XMLTVParser(wanted: Set(channels.map { $0.lowercased() }), window: from...to)
        let parser = XMLParser(data: Gzip.isCompressed(data) ? (Gzip.decompress(data) ?? data) : data)
        parser.delegate = delegate
        parser.parse()
        for key in delegate.guide.keys {
            delegate.guide[key]?.sort { $0.start < $1.start }
        }
        return delegate.guide
    }

    private init(wanted: Set<String>, window: ClosedRange<Date>) {
        self.wanted = wanted
        self.window = window
    }

    private static func date(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces) else { return nil }
        for f in formatters { if let d = f.date(from: s) { return d } }
        return nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "programme":
            channel = nil
            guard let id = attributes["channel"]?.lowercased(), wanted.contains(id),
                  let s = Self.date(attributes["start"]), let e = Self.date(attributes["stop"]),
                  e > window.lowerBound, s < window.upperBound else { return }
            channel = id
            start = s
            end = e
            title = ""
            desc = ""
        case "title", "desc":
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if channel != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let channel else { return }
        switch name {
        case "title" where title.isEmpty: title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "desc" where desc.isEmpty: desc = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "programme":
            if let start, let end, !title.isEmpty {
                // Some feeds list the same slot twice with slightly different times; keep the first.
                let existing = guide[channel] ?? []
                if !existing.contains(where: { $0.start < end && $0.end > start && $0.title == title }) {
                    guide[channel, default: []].append(EPGEntry(title: title, description: desc.isEmpty ? nil : desc, start: start, end: end))
                }
            }
            self.channel = nil
        default:
            break
        }
    }
}

enum Gzip {
    static func isCompressed(_ data: Data) -> Bool {
        data.count > 18 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    /// Strips the gzip wrapper and inflates the raw deflate stream.
    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0, bytes.count > offset + 2 { offset += 2 + Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        if flags & 0x08 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { return nil }
        let deflate = Data(bytes[offset..<(bytes.count - 8)])
        return try? (deflate as NSData).decompressed(using: .zlib) as Data
    }
}
