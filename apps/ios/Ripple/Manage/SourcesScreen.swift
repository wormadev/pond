import SwiftUI

/// Signed-in accounts and watched accounts Pond syncs from, with their last run.
struct SourcesScreen: View {
    let store: LibraryStore

    @State private var accounts: [SyncedSource]?
    @State private var watches: [SyncedSource] = []
    @State private var failure: String?
    @State private var isAdding = false
    @State private var removing: SyncedSource?

    private var api: PondAPI { store.api }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Sources") {
                    Button("Watch an Account", systemImage: "plus") { isAdding = true }
                        .labelStyle(.iconOnly)
                        .font(.textStrong)
                        .foregroundStyle(Theme.foreground)
                        .frame(width: Theme.unit * 9, height: Theme.unit * 9)
                        .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
                }
                if let failure, accounts == nil {
                    StateMessage(title: "Couldn't load Sources", detail: failure, actionTitle: "Try again") {
                        Task { await load() }
                    }
                } else if let accounts {
                    if accounts.isEmpty, watches.isEmpty {
                        StateMessage(title: "No Sources yet", detail: "Connect an account in Pond on your Mac, or watch a public account here.")
                    }
                    group("Accounts", accounts)
                    group("Watching", watches)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.unit * 8)
                }
            }
            .padding(.bottom, Theme.unit * 8)
        }
        .background(Theme.background)
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $isAdding) {
            WatchForm { source, handle in
                let _: JSONValue = try await api.operation("watches.add", ["source": .string(source), "handle": .string(handle)], review: true)
                await load()
            }
        }
        .confirmationDialog(
            "Stop watching \(removing?.title ?? "")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { source in
            Button("Stop Watching", role: .destructive) {
                run { let _: JSONValue = try await api.operation("watches.remove", ["watchId": .string(source.id)], review: true) }
            }
        } message: { _ in
            Text("Saves it already brought in stay.")
        }
        .alert("Couldn't update this Source", isPresented: Binding(get: { failure != nil && accounts != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [SyncedSource]) -> some View {
        if !items.isEmpty {
            SectionHeading(title)
            ForEach(items) { source in
                SourceRow(source: source)
                    .contextMenu {
                        Button(source.sync.isPaused ? "Resume Scheduled Syncs" : "Pause Scheduled Syncs",
                               systemImage: source.sync.isPaused ? "play" : "pause") {
                            setPaused(source, !source.sync.isPaused)
                        }
                        if source.kind == "watch" {
                            Button("Stop Watching", systemImage: "eye.slash", role: .destructive) { removing = source }
                        }
                    }
                if source.id != items.last?.id { RowSeparator() }
            }
        }
    }

    private func setPaused(_ source: SyncedSource, _ paused: Bool) {
        run {
            let arguments: [String: JSONValue] = [
                "kind": .string(source.kind),
                "id": .string(source.id),
                "paused": .bool(paused),
                "intervalHours": source.sync.intervalHours.map { .number($0) } ?? .null,
            ]
            let _: JSONValue = try await api.operation("sources.setSchedule", arguments, review: true)
        }
    }

    private func run(_ change: @escaping () async throws -> Void) {
        Task {
            do {
                try await change()
                await load()
            } catch {
                failure = error.pondMessage
            }
        }
    }

    private func load() async {
        do {
            async let accounts: AccountsResult = api.operation("accounts.list")
            async let watches: WatchesResult = api.operation("watches.list")
            let (a, w) = try await (accounts, watches)
            self.accounts = a.accounts.map { $0.with(kind: "account") }
            self.watches = w.watches.map { $0.with(kind: "watch") }
            failure = nil
        } catch is CancellationError {
        } catch {
            failure = error.pondMessage
        }
    }
}

struct SyncedSource: Decodable, Identifiable {
    struct Sync: Decodable {
        var lastSyncedAt: String?
        var lastError: String?
        var paused: Bool?
        var intervalHours: Double?
        var isPaused: Bool { paused ?? false }
    }

    var id: String
    var source: String
    var handle: String?
    var label: String?
    var syncing: Bool?
    var sync: Sync
    /// `account` or `watch`, which Pond's schedule operation needs. Not in the payload.
    var kind = "account"

    enum CodingKeys: CodingKey { case id, source, handle, label, syncing, sync }

    var title: String { label ?? handle.map { "@\($0)" } ?? source.capitalized }

    func with(kind: String) -> SyncedSource {
        var copy = self
        copy.kind = kind
        return copy
    }
}

private struct AccountsResult: Decodable { var accounts: [SyncedSource] }
private struct WatchesResult: Decodable { var watches: [SyncedSource] }

private struct SourceRow: View {
    let source: SyncedSource

    private var status: String {
        if source.syncing == true { return "Syncing…" }
        if source.sync.lastError != nil { return "Last sync failed" }
        let paused = source.sync.isPaused ? "Paused · " : ""
        guard let raw = source.sync.lastSyncedAt, let date = try? Date(raw, strategy: .iso8601) else {
            return paused + "Not synced yet"
        }
        return paused + "Synced " + date.formatted(.relative(presentation: .named))
    }

    var body: some View {
        let failed = source.sync.lastError != nil
        HStack(alignment: .firstTextBaseline, spacing: Theme.unit * 3) {
            Image(systemName: failed ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                .frame(width: Theme.iconColumn)
                .foregroundStyle(failed ? .red : Theme.muted)
            VStack(alignment: .leading, spacing: Theme.unit) {
                Text(source.title).lineLimit(2)
                Text("\(source.source.capitalized) · \(status)").font(.small).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.unit * 3)
        .frame(minHeight: Theme.rowHeight)
        .padding(.horizontal, Theme.gutter)
        .contentShape(.rect)
    }
}

private struct WatchForm: View {
    let add: (String, String) async throws -> Void

    private static let sources: [(id: String, label: String)] = [
        ("instagram", "Instagram"), ("twitter", "X"), ("tiktok", "TikTok"), ("youtube", "YouTube"),
        ("pinterest", "Pinterest"), ("arena", "Are.na"), ("cosmos", "Cosmos"), ("web", "RSS Feed"),
    ]

    @State private var source = "instagram"
    @State private var handle = ""
    @State private var isSaving = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $source) {
                    ForEach(Self.sources, id: \.id) { Text($0.label).tag($0.id) }
                }
                TextField(source == "web" ? "Feed address" : "Handle or link", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let failure {
                    Text(failure).font(.small).foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Watch an Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.foreground)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Watch") { save() }
                        .fontWeight(.medium)
                        .tint(Theme.accent)
                        .disabled(handle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await add(source, handle.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                failure = error.pondMessage
            }
        }
    }
}
