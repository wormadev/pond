import SwiftUI

/// Rename, merge and delete tags across the whole Library.
struct TagsScreen: View {
    let store: LibraryStore

    @State private var renaming: LibraryTag?
    @State private var newName = ""
    @State private var merging: LibraryTag?
    @State private var deleting: LibraryTag?
    @State private var failure: String?

    var body: some View {
        List {
            ForEach(store.tags) { tag in
                HStack {
                    Text(tag.name).lineLimit(1)
                    Spacer(minLength: Theme.unit * 3)
                    Text(tag.count, format: .number).font(.small).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.background)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = tag }
                    Button("Merge", systemImage: "arrow.triangle.merge") { merging = tag }
                    Button("Rename", systemImage: "pencil") {
                        newName = tag.name
                        renaming = tag
                    }
                    .tint(Theme.accent)
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        newName = tag.name
                        renaming = tag
                    }
                    Button("Merge Into…", systemImage: "arrow.triangle.merge") { merging = tag }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = tag }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if store.tags.isEmpty {
                StateMessage(title: "No tags yet", detail: "Tags you add to Saves appear here.")
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshSidebar() }
        .alert("Rename Tag", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { tag in
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { run("tags.rename", ["from": .string(tag.name), "to": .string(newName.trimmingCharacters(in: .whitespaces))]) }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { tag in
            Button("Delete Tag", role: .destructive) { run("tags.delete", ["name": .string(tag.name)]) }
        } message: { tag in
            Text("It comes off \(tag.count.counted("save")). The Saves stay.")
        }
        .sheet(item: $merging) { tag in
            MergePicker(source: tag, tags: store.tags.filter { $0.id != tag.id }) { target in
                run("tags.merge", ["from": .string(tag.name), "to": .string(target.name)])
            }
        }
        .alert("Couldn't change this tag", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func run(_ operation: String, _ arguments: [String: JSONValue]) {
        Task {
            do {
                let _: JSONValue = try await store.api.operation(operation, arguments, review: true)
                await store.refreshSidebar()
            } catch {
                failure = error.pondMessage
            }
        }
    }
}

private struct MergePicker: View {
    let source: LibraryTag
    let tags: [LibraryTag]
    let pick: (LibraryTag) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [LibraryTag] {
        query.isEmpty ? tags : tags.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(shown) { tag in
                Button {
                    pick(tag)
                    dismiss()
                } label: {
                    HStack {
                        Text(tag.name).foregroundStyle(Theme.foreground)
                        Spacer()
                        Text(tag.count, format: .number).font(.small).foregroundStyle(Theme.muted)
                    }
                }
                .listRowBackground(Theme.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, prompt: "Find a tag")
            .navigationTitle("Merge \(source.name) Into")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.foreground)
                }
            }
        }
    }
}
