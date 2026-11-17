import SwiftUI

enum SaveEditor: String, Identifiable {
    case tags, folders, note
    var id: String { rawValue }
}

struct SaveDetailScreen: View {
    @State var save: Save
    let store: LibraryStore
    let list: SavesList
    var isCurrent = true

    @State private var files: [SaveFile] = []
    @State private var caption = ""
    @State private var editor: SaveEditor?
    @State private var failure: String?
    @State private var isConfirmingTrash = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var api: PondAPI { store.api }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MediaPager(save: save, files: files, store: store, isCurrent: isCurrent, width: proxy.size.width, maxHeight: proxy.size.height * 0.6)
                    SaveHeader(save: save)
                        .padding(.top, Theme.unit * 4)
                    if !bodyText.isEmpty {
                        ClampedText(text: bodyText)
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, Theme.unit * 3)
                    }
                    SaveProperties(save: save, folderNames: folderNames, rate: rate) { editor = $0 }
                        .padding(.top, Theme.unit * 6)
                }
                .padding(.bottom, Theme.unit * 8)
            }
        }
        .background(Theme.background)
        .toolbar { if isCurrent { toolbar } }
        .sheet(item: $editor) { editor in
            switch editor {
            case .tags:
                ChoiceEditor(title: "Tags", icon: "tag", allowsNew: true, options: store.tags.map { ($0.name, $0.name) }, selected: Set(save.tags)) { add, remove in
                    try await api.editTags(id: save.id, add: add, remove: remove)
                    await refresh()
                }
            case .folders:
                ChoiceEditor(title: "Folders", icon: "folder", allowsNew: false, options: store.folders.map { ($0.id, $0.name) }, selected: Set(save.folderIds)) { add, remove in
                    try await api.editFolders(id: save.id, add: add, remove: remove)
                    await refresh()
                }
            case .note:
                NoteEditor(note: save.note ?? "") { note in
                    try await api.setNote(id: save.id, note: note.isEmpty ? nil : note)
                    await refresh()
                }
            }
        }
        .confirmationDialog("Move to Trash?", isPresented: $isConfirmingTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                run(removing: true) { try await api.trash(id: save.id) }
            }
        } message: {
            Text("You can restore it from Trash.")
        }
        .alert("Couldn't update this save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .task {
            async let files = api.files(of: save)
            async let text = try? api.text(id: save.id)
            self.files = await files
            let loaded = await text
            let found = [loaded?.caption, loaded?.description].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            withAnimation(.easeOut(duration: 0.2)) { caption = found }
        }
    }

    /// The caption, else the title Pond stored; empty when the Save has neither.
    private var bodyText: String {
        caption.isEmpty ? (save.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : caption
    }

    private var folderNames: [String] {
        store.folders.filter { save.folderIds.contains($0.id) }.map(\.name)
    }

    private func rate(_ value: Int) {
        run { try await api.setRating(id: save.id, rating: value) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let url = URL(string: save.url) {
                ShareLink(item: url).tint(Theme.foreground)
                Button("Open Original", systemImage: "safari") { openURL(url) }.tint(Theme.foreground)
            }
            if save.deletedAt == nil {
                Button("Move to Trash", systemImage: "trash") { isConfirmingTrash = true }.tint(Theme.foreground)
            } else {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    run(removing: true) { try await api.restore(id: save.id) }
                }
                .tint(Theme.foreground)
            }
        }
    }

    private func run(removing: Bool = false, _ edit: @escaping () async throws -> Void) {
        Task {
            do {
                try await edit()
                if removing {
                    list.remove(id: save.id)
                    dismiss()
                } else {
                    await refresh()
                }
            } catch {
                failure = error.pondMessage
            }
        }
    }

    private func refresh() async {
        guard let fresh = try? await api.save(id: save.id) else { return }
        withAnimation(.snappy) { save = fresh }
        list.replace(fresh)
        await store.refreshSidebar()
    }
}
