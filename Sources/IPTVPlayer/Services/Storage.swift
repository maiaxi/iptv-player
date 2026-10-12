import Foundation

enum Storage {
    static let supportDir: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "IPTVPlayer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let cacheDir: URL = {
        let dir = URL.cachesDirectory.appending(path: "IPTVPlayer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var sourcesFile: URL { supportDir.appending(path: "sources.json") }

    static func loadSources() -> [Source] {
        guard let data = try? Data(contentsOf: sourcesFile) else { return [] }
        return (try? JSONDecoder().decode([Source].self, from: data)) ?? []
    }

    /// Sources contain credentials, so the file is only readable by the current user.
    static func saveSources(_ sources: [Source]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        try? data.write(to: sourcesFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourcesFile.path())
    }

    /// Bump when LibraryData gains fields that old caches can't provide.
    private static func libraryFile(_ id: UUID) -> URL { cacheDir.appending(path: "\(id)-v2.json") }

    static func loadLibrary(for id: UUID) -> LibraryData? {
        guard let data = try? Data(contentsOf: libraryFile(id)) else { return nil }
        return try? JSONDecoder().decode(LibraryData.self, from: data)
    }

    static func saveLibrary(_ library: LibraryData, for id: UUID) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: libraryFile(id), options: .atomic)
    }

    static func removeLibrary(for id: UUID) {
        for name in ["\(id).json", "\(id)-v2.json", "\(id)-epg.xml"] {
            try? FileManager.default.removeItem(at: cacheDir.appending(path: name))
        }
    }
}
