import SwiftUI

struct RootScreen: View {
    var onDisconnect: () -> Void

    private enum Section: Hashable {
        case library, collections, settings, search
    }

    @State private var store: LibraryStore
    @State private var section = Section.collections
    @Environment(\.scenePhase) private var scenePhase

    init(api: PondAPI, onDisconnect: @escaping () -> Void) {
        _store = State(initialValue: LibraryStore(api: api))
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        TabView(selection: $section) {
            Tab("Library", systemImage: "square.grid.2x2", value: Section.library) {
                stack { SavesScreen(store: store, scope: .all) }
            }
            Tab("Collections", systemImage: "folder", value: Section.collections) {
                stack { HomeScreen(store: store, onSearch: { section = .search }) }
            }
            Tab("Settings", systemImage: "gearshape", value: Section.settings) {
                stack { SettingsScreen(store: store, onDisconnect: onDisconnect) }
            }
            Tab(value: Section.search, role: .search) {
                stack { SavesScreen(store: store, scope: .all, isSearch: true) }
            }
        }
        .tint(Theme.accent)
        .background(Theme.background)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await PendingSaves.flush(using: store.api)
            await store.refreshSidebar()
        }
    }

    /// Bar icons and back buttons take the foreground; accent stays for tab selection and explicit primary actions.
    private func stack(@ViewBuilder _ root: () -> some View) -> some View {
        NavigationStack {
            root().containerBackground(Theme.background, for: .navigation)
        }
        .tint(Theme.foreground)
    }
}
