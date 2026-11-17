import SwiftUI

/// The Libraries Pond opened recently on the Mac. Choosing one reopens Pond into it.
struct LibrariesScreen: View {
    let store: LibraryStore

    @State private var libraries: [RecentLibrary]?
    @State private var failure: String?
    @State private var confirming: RecentLibrary?
    @State private var switching: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Libraries", subtitle: switching.map { "Opening \($0) on your Mac…" })
                if let failure, libraries == nil {
                    StateMessage(title: "Couldn't load Libraries", detail: failure, actionTitle: "Try again") {
                        Task { await load() }
                    }
                } else if let libraries {
                    ForEach(libraries) { library in
                        Button { if !library.active { confirming = library } } label: {
                            ListRow(
                                title: library.name,
                                icon: library.active ? "checkmark.circle.fill" : "books.vertical",
                                value: library.available ? nil : "Missing",
                                iconColor: library.active ? Theme.accent : Theme.muted
                            )
                        }
                        .buttonStyle(RowPressStyle())
                        .disabled(!library.available || switching != nil)
                        if library.id != libraries.last?.id { RowSeparator() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.unit * 8)
                }
            }
            .padding(.bottom, Theme.unit * 8)
        }
        .background(Theme.background)
        .navigationTitle("Libraries")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "Open \(confirming?.name ?? "")?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { library in
            Button("Open Library") { open(library) }
        } message: { _ in
            Text("Pond on your Mac reopens into this Library.")
        }
        .alert("Couldn't switch Libraries", isPresented: Binding(get: { failure != nil && libraries != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func load() async {
        do {
            libraries = try await store.api.recentLibraries()
            failure = nil
        } catch is CancellationError {
        } catch {
            failure = error.pondMessage
        }
    }

    private func open(_ library: RecentLibrary) {
        Task {
            switching = library.name
            defer { switching = nil }
            do {
                try await store.api.switchLibrary(path: library.path)
            } catch {
                failure = error.pondMessage
                return
            }
            // Pond relaunches; wait until it answers again before reloading.
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                if (try? await store.api.libraryInfo()) != nil { break }
            }
            await store.refreshSidebar()
            await load()
        }
    }
}
