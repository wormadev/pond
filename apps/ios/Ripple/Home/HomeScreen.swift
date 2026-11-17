import SwiftUI

/// Home: recent Saves on top, then every collection as a cover.
struct HomeScreen: View {
    let store: LibraryStore
    var onSearch: () -> Void

    @State private var recent: SavesList
    @Namespace private var zoom

    init(store: LibraryStore, onSearch: @escaping () -> Void) {
        self.store = store
        self.onSearch = onSearch
        _recent = State(initialValue: SavesList(api: store.api, scope: .all))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader(info: store.info, isOffline: store.failure != nil)
                SearchEntry(action: onSearch)
                if let failure = store.failure, store.info == nil {
                    StateMessage(title: "Can't reach Pond", detail: failure, actionTitle: "Try again") {
                        Task { await load() }
                    }
                } else if let info = store.info {
                    if info.counts.active == 0 {
                        StateMessage(
                            title: "Nothing saved yet",
                            detail: "Share a link to Ripple from Instagram or Safari and it appears here."
                        )
                        if info.counts.trashed > 0 {
                            RowsGroup(title: "More", items: [(.trash, "trash", info.counts.trashed)])
                        }
                    } else {
                        RecentStrip(store: store, recent: recent, zoom: zoom)
                        CoverGrid(title: "Collections", store: store, items: store.tags.map { (LibraryScope.tag($0.name), $0.count) })
                        CoverGrid(title: "Folders", store: store, items: store.folders.map { (LibraryScope.folder($0), $0.count) })
                        RowsGroup(title: "Smart Folders", items: store.views.filter { $0.kind != "group" }.map {
                            (LibraryScope.view($0), $0.kind == "saved_view" ? "rectangle.stack" : "gearshape.2", nil)
                        })
                        RowsGroup(title: "Sources", items: store.sources.map { (LibraryScope.source($0.source), "arrow.down.circle", $0.count) })
                        RowsGroup(title: "More", items: [
                            (.inbox("review"), "tray", nil),
                            (.inbox("snoozed"), "moon.zzz", nil),
                            (.untagged, "tag.slash", nil),
                            (.uncategorized, "folder.badge.questionmark", nil),
                            (.trash, "trash", info.counts.trashed),
                        ])
                        RowSeparator()
                        NavigationLink { AssistantScreen(store: store) } label: {
                            ListRow(title: "Assistant", icon: "sparkles", showsChevron: true)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                } else {
                    HomeSkeleton()
                }
            }
            .padding(.bottom, Theme.unit * 8)
            .animation(.snappy(duration: 0.25), value: store.info == nil)
            .animation(.snappy(duration: 0.25), value: recent.saves.isEmpty)
        }
        .font(.text)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: LibraryScope.self) { SavesScreen(store: store, scope: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        await store.refreshSidebar()
        async let saves: Void = recent.reload()
        async let covers: Void = store.refreshCovers()
        _ = await (saves, covers)
    }
}

private let coverColumns = Array(repeating: GridItem(.flexible(), spacing: Theme.unit * 3, alignment: .top), count: 2)
private let coverHeight = Theme.unit * 32
private let recentSize = CGSize(width: Theme.unit * 24, height: Theme.unit * 30)

private struct HomeHeader: View {
    let info: LibraryInfo?
    let isOffline: Bool

    var body: some View {
        ScreenHeader(title: info?.name ?? "Pond", subtitle: subtitle)
    }

    private var subtitle: String? {
        guard let counts = info?.counts else { return nil }
        let ready = counts.active - counts.ingesting
        let waiting = counts.ingesting > 0 ? ", \(counts.ingesting.formatted()) downloading" : ""
        let offline = isOffline ? ", can't reach Pond" : ""
        return "\(ready.formatted()) \(ready == 1 ? "save" : "saves")\(waiting)\(offline)"
    }
}

private struct SearchEntry: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.unit * 2) {
                Image(systemName: "magnifyingglass")
                Text("Search your library").lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.unit * 3)
            .frame(minHeight: Theme.rowHeight)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
            .contentShape(.rect)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityLabel("Search your library")
        .padding(.horizontal, Theme.gutter)
    }
}

private struct RecentStrip: View {
    let store: LibraryStore
    let recent: SavesList
    let zoom: Namespace.ID

    var body: some View {
        if !recent.saves.isEmpty {
            SectionHeading("Recent")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.unit * 2) {
                    ForEach(recent.saves.prefix(12)) { save in
                        NavigationLink {
                            SavePager(save: save, store: store, list: recent)
                                .navigationTransition(.zoom(sourceID: save.id, in: zoom))
                        } label: {
                            SaveTile(save: save, store: store)
                                .frame(width: recentSize.width, height: recentSize.height)
                                .clipShape(.rect(cornerRadius: Theme.radiusCard))
                        }
                        .buttonStyle(TilePressStyle())
                        .matchedTransitionSource(id: save.id, in: zoom)
                        .accessibilityLabel(save.title ?? save.author ?? "Save")
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .frame(height: recentSize.height)
            .transition(.opacity)
        }
    }
}

private struct CoverGrid: View {
    let title: String
    let store: LibraryStore
    let items: [(scope: LibraryScope, count: Int)]

    var body: some View {
        if !items.isEmpty {
            SectionHeading(title)
            LazyVGrid(columns: coverColumns, alignment: .leading, spacing: Theme.unit * 5) {
                ForEach(items, id: \.scope) { item in
                    NavigationLink(value: item.scope) {
                        VStack(alignment: .leading, spacing: Theme.unit) {
                            CollectionCover(saves: store.covers[item.scope] ?? [], store: store)
                                .padding(.bottom, Theme.unit)
                            Text(item.scope.title)
                                .font(.textStrong)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(item.count, format: .number).font(.small).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(TilePressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.scope.title), \(item.count.formatted()) saves")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

private struct RowsGroup: View {
    let title: String
    let items: [(scope: LibraryScope, icon: String, count: Int?)]

    var body: some View {
        if !items.isEmpty {
            SectionHeading(title)
            VStack(spacing: 0) {
                ForEach(items, id: \.scope) { item in
                    NavigationLink(value: item.scope) {
                        ListRow(title: item.scope.title, icon: item.icon, value: item.count?.formatted(), showsChevron: true)
                    }
                    .buttonStyle(RowPressStyle())
                    if item.scope != items.last?.scope {
                        RowSeparator()
                    }
                }
            }
        }
    }
}

/// First load: the recent strip and a cover grid at their real sizes.
private struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Color.clear
                .frame(height: recentSize.height)
                .overlay(alignment: .leading) {
                    HStack(spacing: Theme.unit * 2) {
                        ForEach(0..<4, id: \.self) { _ in
                            Skeleton().frame(width: recentSize.width, height: recentSize.height)
                        }
                    }
                    .padding(.leading, Theme.gutter)
                }
                .clipped()
            heading
            LazyVGrid(columns: coverColumns, alignment: .leading, spacing: Theme.unit * 5) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.unit * 2) {
                        Skeleton().frame(height: coverHeight).padding(.bottom, Theme.unit)
                        Skeleton(radius: Theme.unit).frame(width: Theme.unit * 24, height: Theme.unit * 3)
                        Skeleton(radius: Theme.unit).frame(width: Theme.unit * 10, height: Theme.unit * 3)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading…")
    }

    private var heading: some View {
        Skeleton(radius: Theme.unit)
            .frame(width: Theme.unit * 20, height: Theme.unit * 4)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.unit * 8)
            .padding(.bottom, Theme.unit * 3)
    }
}

/// One large thumbnail beside two small ones.
private struct CollectionCover: View {
    let saves: [Save]
    let store: LibraryStore

    var body: some View {
        GeometryReader { proxy in
            let gap = Theme.unit
            let small = (proxy.size.width - gap) / 3
            HStack(spacing: gap) {
                cell(0).frame(width: proxy.size.width - gap - small)
                VStack(spacing: gap) {
                    cell(1)
                    cell(2)
                }
                .frame(width: small)
            }
        }
        .frame(height: coverHeight)
        .clipShape(.rect(cornerRadius: Theme.radiusCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if saves.indices.contains(index) {
            Color.clear.overlay { SaveTile(save: saves[index], store: store) }.clipped()
        } else {
            Theme.surface
        }
    }
}
