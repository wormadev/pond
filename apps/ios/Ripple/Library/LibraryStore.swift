import SwiftUI

enum LibraryScope: Hashable {
    case all
    case uncategorized
    case untagged
    case trash
    case tag(String)
    case folder(LibraryFolder)
    case view(LibraryView)
    case source(String)
    /// `review` or `snoozed`.
    case inbox(String)

    var title: String {
        switch self {
        case .all: "Library"
        case .uncategorized: "Uncategorized"
        case .untagged: "Untagged"
        case .trash: "Trash"
        case .tag(let name): name.prefix(1).uppercased() + name.dropFirst()
        case .folder(let folder): folder.name
        case .view(let view): view.name
        case .source(let source): source.capitalized
        case .inbox(let state): state == "snoozed" ? "Snoozed" : "Inbox"
        }
    }

    var request: QueryRequest {
        var request = QueryRequest(sortKey: "savedAt", sortDir: "desc")
        switch self {
        case .all: break
        case .uncategorized: request.scope = .init(uncategorized: true)
        case .untagged: request.scope = .init(untagged: true)
        case .trash: request.scope = .init(deletedOnly: true)
        case .tag(let name): request.scope = .init(tag: name)
        case .folder(let folder): request.scope = .init(folderIds: [folder.id])
        case .source(let source): request.scope = .init(source: source)
        case .inbox(let state): request.scope = .init(inbox: state)
        case .view(let view):
            request.query = view.query
            request.sortKey = view.sortKey
            request.sortDir = view.sortDir
        }
        return request
    }
}

/// What the whole app shares: the library's counts, its collections and their covers.
@MainActor
@Observable
final class LibraryStore {
    let api: PondAPI

    var info: LibraryInfo?
    var tags: [LibraryTag] = []
    var folders: [LibraryFolder] = []
    var views: [LibraryView] = []
    var sources: [LibrarySource] = []
    private(set) var covers: [LibraryScope: [Save]] = [:]
    private(set) var failure: String?
    /// Width over height of each thumbnail seen this session. Pond's query often has no dimensions.
    var aspects: [String: CGFloat] = [:]

    init(api: PondAPI) {
        self.api = api
    }

    func refreshSidebar() async {
        do {
            info = try await api.libraryInfo()
            failure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            failure = error.pondMessage
            return
        }
        async let tags = try? api.tags()
        async let folders = try? api.folders()
        async let views = try? api.views()
        async let sources = try? api.sources()
        self.tags = await tags ?? self.tags
        self.folders = await folders ?? self.folders
        self.views = await views ?? self.views
        self.sources = await sources ?? self.sources
    }

    func refreshCovers() async {
        let scopes = tags.map { LibraryScope.tag($0.name) } + folders.map { LibraryScope.folder($0) }
        let api = api
        await withTaskGroup(of: (LibraryScope, [Save]?).self) { group in
            for scope in scopes {
                group.addTask {
                    var request = scope.request
                    request.limit = 3
                    return (scope, try? await api.query(request).saves)
                }
            }
            for await (scope, saves) in group {
                if let saves { covers[scope] = saves }
            }
        }
    }
}
