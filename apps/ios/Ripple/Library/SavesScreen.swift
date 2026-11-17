import SwiftUI

/// The grid of one scope: the whole library, a tag, a folder, the trash.
struct SavesScreen: View {
    let store: LibraryStore
    var isSearch = false

    @State private var list: SavesList
    @State private var showsBarTitle = false
    // SavesList can't tell "not loaded yet" from "loaded, empty"; without this the empty state flashes before the first load and during the search debounce.
    @State private var hasLoaded = false

    init(store: LibraryStore, scope: LibraryScope, isSearch: Bool = false) {
        self.store = store
        _list = State(initialValue: SavesList(api: store.api, scope: scope))
        self.isSearch = isSearch
    }

    var body: some View {
        if isSearch {
            content
                .searchable(text: $list.keywords, prompt: "Search your library")
                .navigationDestination(for: LibraryScope.self) { SavesScreen(store: store, scope: $0) }
        } else {
            content
        }
    }

    private var title: String { isSearch ? "Search" : list.scope.title }
    private var isPushed: Bool { !isSearch && list.scope != .all }
    private var isIdle: Bool { isSearch && list.keywords.trimmingCharacters(in: .whitespaces).isEmpty }

    // Search keeps the navigation bar: iOS 27 drops the search field when the bar is hidden.
    private var hidesNavigationBar: Bool { !isPushed && !isSearch }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                SavesHeader(list: list, title: title, isSearch: isSearch, isIdle: isIdle, hasLoaded: hasLoaded)
                if isSearch, !isIdle { ModePicker(list: list) }
                SavesContent(store: store, list: list, isSearch: isSearch, isIdle: isIdle, hasLoaded: hasLoaded)
            }
            .padding(.bottom, Theme.unit * 8)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background)
        .animation(.snappy(duration: 0.25), value: isIdle)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Theme.unit * 12
        } action: { _, scrolled in
            withAnimation(.snappy(duration: 0.2)) { showsBarTitle = scrolled }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title).font(.textStrong).opacity(showsBarTitle ? 1 : 0)
            }
        }
        .toolbar(hidesNavigationBar ? .hidden : .automatic, for: .navigationBar)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .refreshable {
            guard !isIdle else { return }
            await list.reload()
        }
        .onChange(of: list.reloadKey) { hasLoaded = false }
        .task(id: list.reloadKey) {
            if !list.keywords.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            guard !isIdle else { return }
            await list.reload()
            if !Task.isCancelled { hasLoaded = true }
        }
    }
}

private struct SavesHeader: View {
    let list: SavesList
    let title: String
    let isSearch: Bool
    let isIdle: Bool
    let hasLoaded: Bool

    private var showsSort: Bool {
        if case .view = list.scope { return false }
        return !isIdle && !(isSearch && list.semantic)
    }

    // A blank line holds the subtitle's height while loading, so the grid doesn't jump when the count lands.
    private var subtitle: String? {
        guard !isIdle else { return nil }
        let settled = hasLoaded && !list.isLoading && list.failure == nil
        guard !list.saves.isEmpty || settled else { return " " }
        let noun = isSearch ? (list.total == 1 ? "result" : "results") : (list.total == 1 ? "save" : "saves")
        return "\(list.total.formatted()) \(noun)"
    }

    var body: some View {
        ScreenHeader(title: title, subtitle: subtitle) {
            if showsSort { SortMenu(list: list) }
        }
        .animation(.snappy(duration: 0.25), value: subtitle)
    }
}

private struct SortMenu: View {
    @Bindable var list: SavesList

    var body: some View {
        Menu {
            Picker("Sort", selection: $list.newestFirst) {
                Text("Newest First").tag(true)
                Text("Oldest First").tag(false)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.textStrong)
                .foregroundStyle(Theme.foreground)
                .frame(width: Theme.unit * 9, height: Theme.unit * 9)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
        }
        .accessibilityLabel("Sort")
        .transition(.opacity)
    }
}

private struct ModePicker: View {
    let list: SavesList

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            segment("Keywords", semantic: false)
            segment("Meaning", semantic: true)
        }
        .padding(Theme.unit / 2)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, Theme.unit * 3)
        .transition(.opacity)
    }

    private func segment(_ label: String, semantic: Bool) -> some View {
        let selected = list.semantic == semantic
        return Button {
            withAnimation(.snappy(duration: 0.25)) { list.semantic = semantic }
        } label: {
            Text(label)
                .font(.textStrong)
                .foregroundStyle(selected ? Theme.foreground : Theme.muted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.unit * 8)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Theme.radiusCard)
                            .fill(Theme.border)
                            .matchedGeometryEffect(id: "mode", in: selection)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
