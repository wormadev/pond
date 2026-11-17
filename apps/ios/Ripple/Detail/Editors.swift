import SwiftUI

/// Picks tags or folders. `commit` receives what was added and removed.
struct ChoiceEditor: View {
    let title: String
    let icon: String
    let allowsNew: Bool
    let options: [(id: String, name: String)]
    let commit: ([String], [String]) async throws -> Void

    private let original: Set<String>
    @State private var selected: Set<String>
    @State private var added: [String] = []
    @State private var draft = ""
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        icon: String,
        allowsNew: Bool,
        options: [(String, String)],
        selected: Set<String>,
        commit: @escaping ([String], [String]) async throws -> Void
    ) {
        self.title = title
        self.icon = icon
        self.allowsNew = allowsNew
        self.options = options.map { (id: $0.0, name: $0.1) }
        self.commit = commit
        original = selected
        _selected = State(initialValue: selected)
    }

    private var rows: [(id: String, name: String)] {
        let known = Set(options.map(\.id))
        let extra = (added + original.sorted()).filter { !known.contains($0) }
        return extra.map { (id: $0, name: $0) } + options
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let failure {
                        EditorFailure(text: failure)
                    }
                    if allowsNew {
                        NewTagRow(draft: $draft, submit: addDraft)
                        RowSeparator()
                    }
                    if rows.isEmpty, !allowsNew {
                        StateMessage(title: "No folders yet", detail: "Create folders in Pond on your Mac.")
                    }
                    ForEach(rows, id: \.id) { row in
                        let isSelected = selected.contains(row.id)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { selected.formSymmetricDifference([row.id]) }
                        } label: {
                            ListRow(title: row.name, icon: isSelected ? "checkmark" : icon, iconColor: isSelected ? Theme.accent : Theme.muted)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        if row.id != rows.last?.id {
                            RowSeparator()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.selection, trigger: selected)
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { EditorToolbar(cancel: { dismiss() }, done: save) }
        }
        .font(.text)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }

    private func addDraft() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !rows.contains(where: { $0.id == name }) { added.append(name) }
        selected.insert(name)
        draft = ""
    }

    private func save() {
        addDraft()
        let add = selected.subtracting(original).sorted()
        let remove = original.subtracting(selected).sorted()
        guard !add.isEmpty || !remove.isEmpty else { return dismiss() }
        Task {
            do {
                try await commit(add, remove)
                dismiss()
            } catch {
                failure = error.pondMessage
            }
        }
    }
}

struct NoteEditor: View {
    @State var note: String
    let commit: (String) async throws -> Void

    @State private var failure: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let failure {
                    EditorFailure(text: failure)
                }
                TextEditor(text: $note)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Theme.unit * 3)
            }
            .background(Theme.background)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { EditorToolbar(cancel: { dismiss() }, done: save) }
            .onAppear { focused = true }
        }
        .font(.text)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }

    private func save() {
        Task {
            do {
                try await commit(note.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } catch {
                failure = error.pondMessage
            }
        }
    }
}

/// "Cancel" stays neutral; "Done" is the sheet's one accent action.
private struct EditorToolbar: ToolbarContent {
    let cancel: () -> Void
    let done: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: cancel).tint(Theme.foreground)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: done).fontWeight(.medium).tint(Theme.accent)
        }
    }
}

/// Same geometry as a `ListRow`, with a field in place of the title.
private struct NewTagRow: View {
    @Binding var draft: String
    let submit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.unit * 3) {
            Image(systemName: "plus").frame(width: Theme.iconColumn).foregroundStyle(Theme.muted)
            TextField("New tag", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submit)
        }
        .padding(.vertical, Theme.unit * 3)
        .frame(minHeight: Theme.rowHeight)
        .padding(.horizontal, Theme.gutter)
    }
}

private struct EditorFailure: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.small)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, Theme.unit * 3)
    }
}
