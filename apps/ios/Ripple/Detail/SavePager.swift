import SwiftUI

/// Swipe sideways through the Saves of one list.
struct SavePager: View {
    let store: LibraryStore
    let list: SavesList

    @State private var current: String?

    init(save: Save, store: LibraryStore, list: SavesList) {
        self.store = store
        self.list = list
        _current = State(initialValue: save.id)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(list.saves) { save in
                    SaveDetailScreen(save: save, store: store, list: list, isCurrent: save.id == current)
                        .containerRelativeFrame(.horizontal)
                        .onAppear {
                            guard save.id == list.saves.last?.id else { return }
                            Task { await list.loadMore() }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
