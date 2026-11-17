import SwiftUI

private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

/// Everything under the header: suggestions while Search is idle, a state message, or the grid.
struct SavesContent: View {
    let store: LibraryStore
    let list: SavesList
    let isSearch: Bool
    let isIdle: Bool
    let hasLoaded: Bool

    var body: some View {
        if isIdle {
            SearchSuggestions(tags: store.tags)
        } else if !list.saves.isEmpty {
            SavesGrid(store: store, list: list)
        } else if list.isLoading || !hasLoaded {
            SkeletonGrid()
        } else if let failure = list.failure {
            StateMessage(title: "Can't reach Pond", detail: failure, actionTitle: "Try again") {
                Task { await list.reload() }
            }
        } else if isSearch {
            NoResults(list: list)
        } else {
            EmptyScope(scope: list.scope)
        }
    }
}

private struct SavesGrid: View {
    let store: LibraryStore
    let list: SavesList

    @Namespace private var zoom

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(list.saves) { save in
                NavigationLink {
                    SavePager(save: save, store: store, list: list)
                        .navigationTransition(.zoom(sourceID: save.id, in: zoom))
                } label: {
                    Color.clear
                        .aspectRatio(4 / 5, contentMode: .fit)
                        .overlay { SaveTile(save: save, store: store) }
                        .overlay(alignment: .bottomLeading) {
                            if save.isVideo, save.thumbnail { VideoBadge() }
                        }
                        .clipped()
                }
                .buttonStyle(TilePressStyle())
                .accessibilityLabel(accessibilityLabel(for: save))
                .matchedTransitionSource(id: save.id, in: zoom)
                .onAppear {
                    guard save.id == list.saves.last?.id else { return }
                    Task { await list.loadMore() }
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: list.saves.map(\.id))
        if list.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: Theme.unit * 16)
        }
    }

    private func accessibilityLabel(for save: Save) -> String {
        let parts = [save.author, save.title].compactMap { $0 }.filter { !$0.isEmpty }
        let name = parts.isEmpty ? (save.siteName ?? "Save") : parts.joined(separator: ", ")
        return save.isVideo ? "\(name), video" : name
    }
}

/// Pinned to one size: at accessibility text sizes a scaling glyph outgrows its box and covers the tile.
private struct VideoBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.small)
            .imageScale(.small)
            .foregroundStyle(Theme.foreground)
            .frame(width: Theme.unit * 5, height: Theme.unit * 5)
            .background(Theme.background, in: .rect(cornerRadius: Theme.radiusCard))
            .padding(Theme.unit)
            .dynamicTypeSize(.large)
            .accessibilityHidden(true)
    }
}

private struct SkeletonGrid: View {
    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(0..<12, id: \.self) { _ in
                Color.clear
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .overlay { Skeleton(radius: 0) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading saves")
        .transition(.opacity)
    }
}

private struct SearchSuggestions: View {
    let tags: [LibraryTag]

    var body: some View {
        if tags.isEmpty {
            StateMessage(title: "Search your library", detail: "Type a word, or switch to Meaning to search by idea.")
        } else {
            LazyVStack(spacing: 0) {
                SectionHeading("Collections")
                ForEach(tags) { tag in
                    if tag.id != tags.first?.id { RowSeparator() }
                    let scope = LibraryScope.tag(tag.name)
                    NavigationLink(value: scope) {
                        ListRow(title: scope.title, icon: "tag", value: tag.count.formatted(), showsChevron: true)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .transition(.opacity)
        }
    }
}

private struct NoResults: View {
    let list: SavesList

    var body: some View {
        let query = list.keywords.trimmingCharacters(in: .whitespaces)
        StateMessage(
            title: "No saves match “\(query)”",
            detail: list.semantic ? "Try describing it another way." : "Try other words, or switch to Meaning.",
            actionTitle: "Clear search"
        ) {
            list.keywords = ""
        }
    }
}

private struct EmptyScope: View {
    let scope: LibraryScope

    var body: some View {
        switch scope {
        case .all:
            StateMessage(title: "Nothing saved yet", detail: "Share a link to Ripple from Instagram or Safari and it appears here.")
        case .trash:
            StateMessage(title: "Trash is empty", detail: "Saves you trash stay here until Pond removes them.")
        default:
            StateMessage(title: "No saves here", detail: "Saves you add to this collection show up here.")
        }
    }
}
