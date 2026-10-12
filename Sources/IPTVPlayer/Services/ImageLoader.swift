import AppKit
import SwiftUI

/// Memory + disk cached image loading. Channel logos are re-requested constantly while scrolling,
/// so AsyncImage (no caching) isn't good enough.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let memory = NSCache<NSURL, NSImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 1500
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 32 << 20,
            diskCapacity: 512 << 20,
            directory: Storage.cacheDir.appending(path: "images")
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> NSImage? { memory.object(forKey: url as NSURL) }

    func load(_ url: URL, maxPixelSize: CGFloat = 400) async -> NSImage? {
        if let image = cached(url) { return image }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        guard let image = downsample(data, maxPixelSize: maxPixelSize) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    private func downsample(_ data: Data, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageLoader.shared.cached(url) { image = hit; return }
            image = nil
            let loaded = await ImageLoader.shared.load(url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
