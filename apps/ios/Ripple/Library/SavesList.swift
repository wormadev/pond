import SwiftUI

/// One scoped, paged query over the library.
@MainActor
@Observable
final class SavesList {
    let api: PondAPI
    let scope: LibraryScope

    var keywords = ""
    var semantic = false
    var newestFirst = true

    private(set) var saves: [Save] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var failure: String?

    private var cursor: JSONValue?
    private var generation = 0

    init(api: PondAPI, scope: LibraryScope) {
        self.api = api
        self.scope = scope
    }

    var reloadKey: [String] { [keywords, String(semantic), String(newestFirst)] }

    func reload() async {
        generation += 1
        cursor = nil
        await load(replacing: true)
    }

    func loadMore() async {
        guard cursor != nil, !isLoading else { return }
        await load(replacing: false)
    }

    func replace(_ save: Save) {
        guard let index = saves.firstIndex(where: { $0.id == save.id }) else { return }
        saves[index] = save
    }

    func remove(id: String) {
        saves.removeAll { $0.id == id }
        total = max(0, total - 1)
    }

    private func load(replacing: Bool) async {
        let started = generation
        isLoading = true
        defer { if started == generation { isLoading = false } }
        do {
            let text = keywords.trimmingCharacters(in: .whitespaces)
            if semantic, !text.isEmpty {
                let found = try await api.search(text)
                guard started == generation else { return }
                saves = found
                total = found.count
                cursor = nil
            } else {
                var request = scope.request
                request.keywords = text.isEmpty ? nil : text
                if case .view = scope {} else { request.sortDir = newestFirst ? "desc" : "asc" }
                request.cursor = cursor
                let page = try await api.query(request)
                guard started == generation else { return }
                saves = replacing ? page.saves : saves + page.saves
                total = page.total
                cursor = page.nextCursor
            }
            failure = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard started == generation else { return }
            failure = error.pondMessage
        }
    }
}
