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
    @State private var page = 0
    @State private var related: [Save] = []
    @State private var toolStatus: String?
    @State private var mediaVersion = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var api: PondAPI { store.api }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MediaPager(save: save, files: files, store: store, isCurrent: isCurrent, width: proxy.size.width, maxHeight: proxy.size.height * 0.6, page: $page)
                        .id(mediaVersion)
                    SaveHeader(save: save)
                        .padding(.top, Theme.unit * 4)
                    if !bodyText.isEmpty {
                        ClampedText(text: bodyText)
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, Theme.unit * 3)
                    }
                    SaveProperties(save: save, folderNames: folderNames, rate: rate) { editor = $0 }
                        .padding(.top, Theme.unit * 6)
                    RelatedStrip(saves: related, store: store)
                }
                .padding(.bottom, Theme.unit * 8)
            }
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            if let toolStatus {
                Text(toolStatus)
                    .font(.small)
                    .padding(.horizontal, Theme.unit * 3)
                    .padding(.vertical, Theme.unit * 2)
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.border, lineWidth: 0.5))
                    .padding(.bottom, Theme.unit * 4)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: toolStatus)
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
            async let related = try? api.related(id: save.id)
            await loadFiles(files)
            let loaded = await text
            let found = [loaded?.caption, loaded?.description].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            withAnimation(.easeOut(duration: 0.2)) { caption = found }
            let others = await related ?? []
            withAnimation(.easeOut(duration: 0.2)) { self.related = others.filter { $0.id != save.id } }
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

    private func loadFiles(_ loaded: [SaveFile]) async {
        files = loaded
        page = MediaPager.media(in: loaded).first?.index ?? 0
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if save.deletedAt == nil {
                Button(save.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: save.isFavorite ? "heart.fill" : "heart") {
                    let favorite = !save.isFavorite
                    run { try await api.setFavorite(id: save.id, favorite: favorite) }
                }
                .tint(save.isFavorite ? Theme.accent : Theme.foreground)
                .symbolEffect(.bounce, value: save.isFavorite)
                .sensoryFeedback(.selection, trigger: save.isFavorite)
            }
            if let url = URL(string: save.url) {
                ShareLink(item: url).tint(Theme.foreground)
            }
            Menu("More", systemImage: "ellipsis") {
                if let url = URL(string: save.url) {
                    Button("Open Original", systemImage: "safari") { openURL(url) }
                }
                if save.kind == "image", save.deletedAt == nil, toolStatus == nil {
                    Menu("Image Tools", systemImage: "wand.and.stars") {
                        ForEach(ImageTool.allCases) { tool in
                            Button(tool.title, systemImage: tool.icon) { runTool(tool) }
                        }
                    }
                }
                if save.deletedAt == nil {
                    Menu("Inbox", systemImage: "tray") {
                        Button("Add to Inbox", systemImage: "tray.and.arrow.down") { setInbox(.string("review")) }
                        Button("Mark Processed", systemImage: "checkmark") { setInbox(.string("processed")) }
                        Button("Snooze Until Tomorrow", systemImage: "moon.zzz") { snooze(days: 1) }
                        Button("Snooze for a Week", systemImage: "calendar") { snooze(days: 7) }
                        Button("Remove from Inbox", systemImage: "tray.and.arrow.up") { setInbox(.null) }
                    }
                    Button("Move to Trash", systemImage: "trash", role: .destructive) { isConfirmingTrash = true }
                } else {
                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        run(removing: true) { try await api.restore(id: save.id) }
                    }
                }
            }
            .tint(Theme.foreground)
        }
    }

    /// Leaving an Inbox list takes the Save out of it, like trashing does.
    private var leavesList: Bool {
        if case .inbox = list.scope { return true }
        return false
    }

    private func setInbox(_ state: JSONValue) {
        bulkEdit(["kind": "inbox", "state": state])
    }

    /// Snoozed Saves come back to the Inbox at 9 in the morning.
    private func snooze(days: Int) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now)) ?? .now
        let until = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        bulkEdit(["kind": "snooze", "until": .number((until.timeIntervalSince1970 * 1000).rounded())])
    }

    private func bulkEdit(_ operation: [String: JSONValue]) {
        run(removing: leavesList) {
            let _: JSONValue = try await api.operation(
                "saves.bulkEdit",
                ["ids": .array([.string(save.id)]), "operation": .object(operation)],
                review: true
            )
        }
    }

    /// Starts the job on the Mac, then polls it; the Mac rewrites the file in place.
    private func runTool(_ tool: ImageTool) {
        Task {
            toolStatus = tool.busy
            defer { toolStatus = nil }
            do {
                var job = try await api.compress(id: save.id, fileIndex: page, mode: tool.rawValue)
                while job.status == "running" {
                    try await Task.sleep(for: .milliseconds(500))
                    job = try await api.conversion(id: job.id)
                }
                guard job.status == "complete" else {
                    if job.status != "cancelled" { failure = job.error ?? tool.failed }
                    return
                }
                guard job.changed > 0 else {
                    failure = "Pond skipped this image. It may already be as small as it gets."
                    return
                }
                await api.forgetMedia(of: save)
                await refresh()
                await loadFiles(await api.files(of: save))
                mediaVersion += 1
            } catch is CancellationError {
            } catch {
                failure = error.pondMessage
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

/// The compression modes Pond's desktop offers under Compress Images and Image Tools.
enum ImageTool: String, CaseIterable, Identifiable {
    case webp, lossless, quality
    case removeBackground = "remove-background"
    case upscale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webp: "Convert to WebP"
        case .lossless: "Compress Lossless"
        case .quality: "Compress at Quality 85"
        case .removeBackground: "Remove Background"
        case .upscale: "Upscale 2×"
        }
    }

    var icon: String {
        switch self {
        case .webp: "photo"
        case .lossless: "checkmark.shield"
        case .quality: "gauge.medium"
        case .removeBackground: "person.crop.rectangle"
        case .upscale: "arrow.up.left.and.arrow.down.right"
        }
    }

    var busy: String {
        switch self {
        case .webp: "Converting to WebP…"
        case .lossless, .quality: "Compressing…"
        case .removeBackground: "Removing background…"
        case .upscale: "Upscaling…"
        }
    }

    var failed: String {
        switch self {
        case .webp: "Couldn't convert this image."
        case .lossless, .quality: "Couldn't compress this image."
        case .removeBackground: "Couldn't remove this background."
        case .upscale: "Couldn't upscale this image."
        }
    }
}

/// Saves Pond finds similar by meaning. Hidden until it has some.
private struct RelatedStrip: View {
    let saves: [Save]
    let store: LibraryStore

    private let size = CGSize(width: Theme.unit * 24, height: Theme.unit * 30)

    var body: some View {
        if !saves.isEmpty {
            SectionHeading("Related")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.unit * 2) {
                    ForEach(saves) { save in
                        NavigationLink {
                            SavePager(save: save, store: store, list: SavesList(api: store.api, saves: saves))
                        } label: {
                            SaveTile(save: save, store: store)
                                .frame(width: size.width, height: size.height)
                                .clipShape(.rect(cornerRadius: Theme.radiusCard))
                        }
                        .buttonStyle(TilePressStyle())
                        .accessibilityLabel(save.title ?? save.author ?? "Save")
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .frame(height: size.height)
            .transition(.opacity)
        }
    }
}
