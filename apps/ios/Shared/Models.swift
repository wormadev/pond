import Foundation

struct Save: Codable, Identifiable, Hashable {
    struct Media: Codable, Hashable {
        var files: Int
        var width: Double?
        var height: Double?
        var duration: Double?
    }

    var id: String
    var source: String
    var url: String
    var title: String?
    var description: String?
    var author: String?
    var siteName: String?
    var tags: [String]
    var folderIds: [String]
    var note: String?
    var rating: Int?
    /// Pond versions before favorites omit it.
    var favorite: Bool?
    var kind: String?
    var status: String
    var savedAt: Double
    var deletedAt: Double?
    var media: Media
    var thumbnail: Bool

    var savedDate: Date { Date(timeIntervalSince1970: savedAt / 1000) }
    var isVideo: Bool { kind == "video" }
    var isFavorite: Bool { favorite ?? false }
}

struct LibraryInfo: Codable {
    struct Counts: Codable {
        var active: Int
        var trashed: Int
        var ingesting: Int
        var failed: Int
    }

    struct Queue: Codable {
        var pending: Int
        var running: Int
    }

    var libraryId: String
    var name: String
    var counts: Counts
    var queue: Queue
}

struct LibraryTag: Codable, Hashable, Identifiable {
    var name: String
    var count: Int
    var id: String { name }
}

struct LibraryFolder: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var parentId: String?
    var count: Int
}

struct LibraryView: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var parentId: String?
    var query: JSONValue
    var sortKey: String
    var sortDir: String
}

struct LibrarySource: Codable, Hashable, Identifiable {
    var source: String
    var count: Int
    var id: String { source }
}

struct QueryRequest: Encodable {
    struct Scope: Encodable {
        var deletedOnly: Bool?
        var source: String?
        var untagged: Bool?
        var folderIds: [String]?
        var uncategorized: Bool?
        var tag: String?
        var inbox: String?
    }

    var query: JSONValue?
    var keywords: String?
    var scope: Scope?
    var sortKey: String?
    var sortDir: String?
    var limit = 60
    var cursor: JSONValue?
    var include = ["saves"]
}

struct QueryPage: Decodable {
    var saves: [Save]
    var total: Int
    var nextCursor: JSONValue?
}

struct SearchResult: Decodable {
    var saves: [Save]
}

struct SaveText: Decodable {
    var description: String
    var caption: String
    var ocr: String
    var transcript: String
}

struct EnqueueResult: Decodable {
    var id: String
    var created: Bool
}

/// A compression job running on the Mac. Poll it until it leaves `running`.
struct ConversionJob: Decodable {
    var id: String
    var status: String
    var changed: Int
    var skipped: Int
    var error: String?
}

struct EditResult: Decodable {
    var changed: Int
}

/// One file of a Save, as reported by the headers of `/saves/file`.
struct SaveFile: Identifiable, Hashable {
    var index: Int
    var name: String
    var contentType: String

    var id: Int { index }
    var isVideo: Bool { contentType.hasPrefix("video/") }
    var isImage: Bool { contentType.hasPrefix("image/") }
}

struct RecentLibrary: Decodable, Identifiable, Hashable {
    var path: String
    var name: String
    var available: Bool
    var active: Bool
    var id: String { path }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}
