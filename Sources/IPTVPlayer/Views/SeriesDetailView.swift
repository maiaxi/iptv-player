import SwiftUI

struct SeriesDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(\.openWindow) private var openWindow
    let series: MediaItem

    @State private var info: SeriesInfo?
    @State private var season = 1
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let info {
                    episodesSection(info)
                } else if let error {
                    ContentUnavailableView("Não foi possível carregar a série", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(series.name)
        .task(id: series.id) { await load() }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: info?.backdrop ?? info?.cover ?? series.logo, contentMode: .fill) {
                Color.secondary.opacity(0.15)
            }
            .frame(height: 340)
            .frame(maxWidth: .infinity)
            .clipped()
            .blur(radius: info?.backdrop == nil ? 30 : 0)
            .overlay {
                LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom)
            }

            HStack(alignment: .bottom, spacing: 24) {
                Color.clear
                    .frame(width: 170, height: 255)
                    .overlay {
                        RemoteImage(url: series.logo ?? info?.cover, contentMode: .fill) {
                            Monogram(name: series.name, symbol: "tv")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 10) {
                    Text(series.name)
                        .font(.system(size: 34, weight: .bold))
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        if let rating = series.rating {
                            Label(rating, systemImage: "star.fill").foregroundStyle(.yellow)
                        }
                        if let year = info?.releaseDate?.prefix(4), !year.isEmpty { Text(year) }
                        if let genre = info?.genre { Text(genre).lineLimit(1) }
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    if let plot = info?.plot {
                        Text(plot)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .frame(maxWidth: 640, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        Button {
                            if let first = episodes.first { play(first) }
                        } label: {
                            Label("Reproduzir", systemImage: "play.fill").padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(episodes.isEmpty)

                        Button {
                            library.toggleFavorite(series)
                        } label: {
                            Label(library.isFavorite(series) ? "Nos favoritos" : "Favorito",
                                  systemImage: library.isFavorite(series) ? "star.fill" : "star")
                        }
                        .controlSize(.large)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private var seasons: [Int] { info?.episodesBySeason.keys.sorted() ?? [] }
    private var episodes: [Episode] { info?.episodesBySeason[season] ?? [] }

    @ViewBuilder
    private func episodesSection(_ info: SeriesInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Episódios").font(.title2.weight(.bold))
                Spacer()
                if seasons.count > 1 {
                    Picker("Temporada", selection: $season) {
                        ForEach(seasons, id: \.self) { Text("Temporada \($0)").tag($0) }
                    }
                    .fixedSize()
                }
            }
            if episodes.isEmpty {
                Text("Esta série ainda não tem episódios disponíveis.").foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 6) {
                ForEach(episodes) { episode in
                    EpisodeRow(episode: episode, fallbackImage: info.backdrop ?? series.logo) { play(episode) }
                }
            }
        }
        .padding(.horizontal, 28)
    }

    private func load() async {
        do {
            let loaded = try await library.seriesInfo(for: series)
            info = loaded
            season = loaded?.episodesBySeason.keys.min() ?? 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func item(for episode: Episode) -> MediaItem {
        MediaItem(
            id: "\(series.id):ep:\(episode.id)",
            name: "T\(episode.season):E\(episode.number) · \(episode.title)",
            logo: series.logo,
            categoryID: series.categoryID,
            kind: .series,
            streamURL: episode.streamURL,
            xtreamID: nil,
            rating: nil
        )
    }

    private func play(_ episode: Episode) {
        PlaybackLauncher.play(item(for: episode), queue: episodes.map(item(for:)), subtitle: series.name,
                              library: library, player: player, openWindow: openWindow, recentItem: series)
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let fallbackImage: URL?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Color.clear
                    .frame(width: 176, height: 99)
                    .overlay {
                        RemoteImage(url: episode.image ?? fallbackImage, contentMode: .fill) {
                            Color.secondary.opacity(0.15)
                        }
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.45), in: Circle())
                            .opacity(hovering ? 1 : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(episode.number). \(episode.title)")
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        if let duration = episode.duration, !duration.isEmpty {
                            Text(duration).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if let plot = episode.plot, !plot.isEmpty {
                        Text(plot)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(8)
            .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
