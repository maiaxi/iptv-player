import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var sidebar: SidebarItem? = .kind(.live)
    @State private var filter = CategoryFilter.all
    @State private var search = ""
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var library = library
        Group {
            if library.sources.isEmpty {
                WelcomeView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $sidebar)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } content: {
                    CategoryColumn(sidebar: sidebar ?? .kind(.live), selection: $filter)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
                } detail: {
                    NavigationStack(path: $path) {
                        BrowseView(sidebar: sidebar ?? .kind(.live), filter: filter, search: search)
                            .navigationDestination(for: MediaItem.self) { SeriesDetailView(series: $0) }
                    }
                }
                .searchable(text: $search, placement: .toolbar, prompt: "Search")
            }
        }
        .sheet(isPresented: $library.isAddingSource) {
            SourceFormView(source: nil)
        }
        .onChange(of: sidebar) {
            filter = CategoryFilter.all
            path = NavigationPath()
        }
        .onChange(of: filter) { path = NavigationPath() }
        #if DEBUG
        .modifier(DebugAutoplay())
        #endif
        .onChange(of: library.selectedSourceID) {
            filter = CategoryFilter.all
            path = NavigationPath()
        }
    }
}

#if DEBUG
/// `IPTV_AUTOPLAY=<url> swift run` opens the player straight away, for testing playback.
private struct DebugAutoplay: ViewModifier {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            guard let value = ProcessInfo.processInfo.environment["IPTV_AUTOPLAY"], let url = URL(string: value) else { return }
            let item = MediaItem(id: "debug", name: "Test", logo: nil, categoryID: "", kind: .live,
                                 streamURL: url, xtreamID: nil, rating: nil)
            PlaybackLauncher.play(item, queue: [item], library: library, player: player, openWindow: openWindow)
        }
    }
}
#endif

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(ContentKind.allCases, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .badge(library.count(for: kind))
                        .tag(SidebarItem.kind(kind))
                }
            }
            Section("Collections") {
                Label("Favorites", systemImage: "star")
                    .tag(SidebarItem.favorites)
                Label("Recents", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.recents)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SourceSwitcher()
                .padding(10)
        }
    }
}

private struct SourceSwitcher: View {
    @Environment(LibraryStore.self) private var library
    @State private var managing = false

    var body: some View {
        Menu {
            ForEach(library.sources) { source in
                Button {
                    library.select(sourceID: source.id)
                } label: {
                    if source.id == library.selectedSourceID {
                        Label(source.name, systemImage: "checkmark")
                    } else {
                        Text(source.name)
                    }
                }
            }
            Divider()
            Button("Add Source…") { library.isAddingSource = true }
            Button("Manage Sources…") { managing = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(library.selectedSource?.name ?? String(localized: "No source"))
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .sheet(isPresented: $managing) { ManageSourcesView() }
    }

    private var statusLine: String {
        if library.isLoading { return String(localized: "Loading…") }
        if let expires = library.library?.account?.expiresAt {
            return String(localized: "Expires \(expires.formatted(date: .abbreviated, time: .omitted))")
        }
        return library.selectedSource?.subtitle ?? ""
    }
}

// MARK: - Categories

private struct CategoryColumn: View {
    @Environment(LibraryStore.self) private var library
    let sidebar: SidebarItem
    @Binding var selection: String
    @State private var query = ""

    var body: some View {
        List(selection: Binding(get: { selection }, set: { selection = $0 ?? CategoryFilter.all })) {
            switch sidebar {
            case .kind(let kind):
                row(String(localized: "All"), systemImage: "square.grid.2x2", count: library.count(for: kind))
                    .tag(CategoryFilter.all)
                Section("Categories") {
                    ForEach(filtered(library.categories(for: kind))) { category in
                        Text(category.name)
                            .lineLimit(1)
                            .badge(library.count(in: category))
                            .tag(category.id)
                    }
                }
            case .favorites, .recents:
                row(String(localized: "All"), systemImage: "square.grid.2x2",
                    count: library.items(for: sidebar, filter: CategoryFilter.all, search: "").count)
                    .tag(CategoryFilter.all)
                ForEach(ContentKind.allCases, id: \.self) { kind in
                    row(kind.title, systemImage: kind.symbol,
                        count: library.items(for: sidebar, filter: kind.rawValue, search: "").count)
                        .tag(kind.rawValue)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if case .kind = sidebar {
                TextField("Filter categories", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch sidebar {
        case .kind(let kind): kind.title
        case .favorites: String(localized: "Favorites")
        case .recents: String(localized: "Recents")
        }
    }

    private func row(_ title: String, systemImage: String, count: Int) -> some View {
        Label(title, systemImage: systemImage).badge(count)
    }

    private func filtered(_ categories: [MediaCategory]) -> [MediaCategory] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return categories }
        return categories.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 120, height: 120)
                .background(LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .purple.opacity(0.35), radius: 24, y: 10)
            VStack(spacing: 8) {
                Text("Welcome to IPTV Player")
                    .font(.largeTitle.weight(.bold))
                Text("Add an M3U playlist or an Xtream Codes account to start watching TV, movies and series.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button {
                library.isAddingSource = true
            } label: {
                Label("Add Source", systemImage: "plus")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
