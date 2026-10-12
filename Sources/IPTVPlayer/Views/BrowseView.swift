import SwiftUI

struct BrowseView: View {
    @Environment(LibraryStore.self) private var library
    let sidebar: SidebarItem
    let filter: String
    let search: String

    var body: some View {
        let items = library.items(for: sidebar, filter: filter, search: search)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth(items), maximum: 240), spacing: 22, alignment: .top)],
                      alignment: .leading, spacing: 26) {
                ForEach(items) { item in
                    MediaCard(item: item, queue: items)
                }
            }
            .padding(24)
        }
        .overlay { emptyState(items) }
        .navigationTitle(title)
        .navigationSubtitle(items.isEmpty ? "" : items.count == 1 ? String(localized: "1 item") : String(localized: "\(items.count.formatted()) items"))
        .toolbar {
            ToolbarItem {
                if library.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { library.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Refresh the library")
                }
            }
        }
    }

    private var title: String {
        if filter == CategoryFilter.all {
            switch sidebar {
            case .kind(let kind): return kind.title
            case .favorites: return String(localized: "Favorites")
            case .recents: return String(localized: "Recents")
            }
        }
        if let kind = ContentKind(rawValue: filter) { return kind.title }
        return library.library?.categories.first { $0.id == filter }?.name ?? ""
    }

    private func minWidth(_ items: [MediaItem]) -> CGFloat {
        items.allSatisfy({ $0.kind == .live }) ? 170 : 150
    }

    @ViewBuilder
    private func emptyState(_ items: [MediaItem]) -> some View {
        if !items.isEmpty {
            EmptyView()
        } else if library.isLoading && library.library == nil {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Loading library…").foregroundStyle(.secondary)
            }
        } else if let error = library.loadError, library.library == nil {
            ContentUnavailableView {
                Label("Couldn’t load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { library.refresh() }
            }
        } else if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if sidebar == .favorites {
            ContentUnavailableView("No Favorites", systemImage: "star",
                                   description: Text("Right-click a channel or movie to add it to your favorites."))
        } else if sidebar == .recents {
            ContentUnavailableView("Nothing Watched Yet", systemImage: "clock",
                                   description: Text("What you watch shows up here."))
        } else {
            ContentUnavailableView("No Content", systemImage: "tray")
        }
    }
}

// MARK: - Card

struct MediaCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(\.openWindow) private var openWindow
    let item: MediaItem
    let queue: [MediaItem]
    @State private var hovering = false

    var body: some View {
        Group {
            if item.isPlayable {
                Button { play() } label: { content }
            } else {
                NavigationLink(value: item) { content }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if item.isPlayable {
                Button("Play") { play() }
            }
            Button(library.isFavorite(item) ? LocalizedStringKey("Remove from Favorites") : "Add to Favorites") {
                library.toggleFavorite(item)
            }
            if let url = item.streamURL {
                Divider()
                Button("Copy Stream Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(hovering ? Color.accentColor : .primary.opacity(0.06), lineWidth: hovering ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if library.isFavorite(item) {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                }
                .overlay {
                    if hovering && item.isPlayable {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.45), in: Circle())
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.25 : 0.08), radius: hovering ? 14 : 4, y: hovering ? 8 : 2)
                .scaleEffect(hovering ? 1.03 : 1)
                .animation(.spring(duration: 0.25), value: hovering)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2, reservesSpace: item.kind != .live)
                    .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.85))
                // Reserve the line whenever a guide is loaded so grid rows stay aligned.
                if item.kind == .live, !library.guide.isEmpty {
                    NowPlayingLine(program: library.currentProgram(for: item), clock: library.clock)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var radius: CGFloat { item.kind == .live ? 14 : 12 }

    @ViewBuilder
    private var artwork: some View {
        if item.kind == .live {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.quaternary.opacity(0.55))
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    RemoteImage(url: item.logo) {
                        Monogram(name: item.name)
                    }
                    .padding(item.logo == nil ? 0 : 18)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    RemoteImage(url: item.logo, contentMode: .fill) {
                        Monogram(name: item.name, symbol: item.kind.symbol)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if let rating = item.rating {
                        Label(rating, systemImage: "star.fill")
                            .font(.caption2.weight(.bold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(8)
                    }
                }
        }
    }

    private func play() {
        PlaybackLauncher.play(item, queue: queue, library: library, player: player, openWindow: openWindow)
    }
}

enum PlaybackLauncher {
    @MainActor
    static func play(_ item: MediaItem, queue: [MediaItem], subtitle: String? = nil,
                     library: LibraryStore, player: PlayerModel, openWindow: OpenWindowAction,
                     recentItem: MediaItem? = nil) {
        library.markRecent(recentItem ?? item)
        player.play(item, queue: queue, subtitle: subtitle ?? library.categoryName(for: item))
        openWindow(id: "player")
    }
}

/// "What's on now" under a channel name: programme title plus a thin progress bar.
struct NowPlayingLine: View {
    let program: EPGEntry?
    let clock: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program?.title ?? String(localized: "No information"))
                .font(.caption)
                .foregroundStyle(program == nil ? .tertiary : .secondary)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.1))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * (program?.progress(at: clock) ?? 0))
                }
            }
            .frame(height: 3)
            .opacity(program == nil ? 0 : 1)
        }
        .help(program.map { "\($0.start.formatted(date: .omitted, time: .shortened)) – \($0.end.formatted(date: .omitted, time: .shortened))  \($0.title)" } ?? "")
    }
}

/// Placeholder artwork: a soft gradient derived from the name, with initials.
struct Monogram: View {
    let name: String
    var symbol: String? = nil

    var body: some View {
        // Stable across launches, unlike hashValue.
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(seed % 360) / 360
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.55),
                                    Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.title2).opacity(0.7)
                }
                Text(initials)
                    .font(.system(size: symbol == nil ? 26 : 20, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var initials: String {
        let words = name
            .replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .filter { !$0.isEmpty }
        return words.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
