import Foundation

struct PondError: LocalizedError {
    var code: String
    var message: String
    var errorDescription: String? { message }
}

struct PondAPI {
    let connection: Connection
    var session: URLSession = PondAPI.defaultSession

    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private struct Envelope<T: Decodable>: Decodable {
        struct Failure: Decodable {
            var code: String
            var message: String
        }

        var data: T?
        var error: Failure?
    }

    func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = connection.baseURL.appending(path: "api/v2" + path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await session.data(for: request)
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let error = envelope.error { throw PondError(code: error.code, message: error.message) }
        guard let value = envelope.data else {
            throw PondError(code: "internal", message: "Pond sent an empty response.")
        }
        return value
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(request(path, query: query))
    }

    private func post<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        var request = request(path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    func libraryInfo() async throws -> LibraryInfo { try await get("/library/info") }
    func tags() async throws -> [LibraryTag] { try await get("/library/tags") }
    func folders() async throws -> [LibraryFolder] { try await get("/library/folders") }
    func views() async throws -> [LibraryView] { try await get("/library/views") }
    func sources() async throws -> [LibrarySource] { try await get("/library/sources") }

    func query(_ body: QueryRequest) async throws -> QueryPage {
        try await post("/library/query", body)
    }

    func search(_ text: String) async throws -> [Save] {
        let result: SearchResult = try await post("/library/search", ["query": text])
        return result.saves
    }

    func save(id: String) async throws -> Save {
        try await get("/saves/info", query: [.init(name: "id", value: id)])
    }

    func text(id: String) async throws -> SaveText {
        try await get("/saves/text", query: [.init(name: "id", value: id)])
    }

    func thumbRequest(id: String, size: String) -> URLRequest {
        request("/saves/thumb", query: [.init(name: "id", value: id), .init(name: "size", value: size)])
    }

    func fileRequest(id: String, index: Int) -> URLRequest {
        request("/saves/file", query: [.init(name: "id", value: id), .init(name: "index", value: String(index))])
    }

    /// Pond has no file listing, so this reads the headers of each index and drops the body.
    func files(of save: Save) async -> [SaveFile] {
        await withTaskGroup(of: SaveFile?.self) { group in
            for index in 0..<save.media.files {
                group.addTask {
                    guard let (bytes, response) = try? await session.bytes(for: fileRequest(id: save.id, index: index)),
                          let http = response as? HTTPURLResponse
                    else { return nil }
                    bytes.task.cancel()
                    guard http.statusCode == 200 else { return nil }
                    return SaveFile(
                        index: index,
                        name: http.suggestedFilename ?? "",
                        contentType: http.value(forHTTPHeaderField: "Content-Type") ?? ""
                    )
                }
            }
            var files: [SaveFile] = []
            for await file in group { if let file { files.append(file) } }
            return files.sorted { $0.index < $1.index }
        }
    }

    func enqueue(url: String) async throws -> EnqueueResult {
        try await post("/enqueue", ["url": url, "trigger": "ios"])
    }

    private struct IdsEdit: Encodable {
        var ids: [String]
        var add: [String]?
        var remove: [String]?
        var rating: Int?
    }

    private struct NoteEdit: Encodable {
        var id: String
        var note: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(note, forKey: .note)
        }

        enum CodingKeys: CodingKey { case id, note }
    }

    func editTags(id: String, add: [String], remove: [String]) async throws {
        let _: EditResult = try await post("/saves/tags", IdsEdit(ids: [id], add: add, remove: remove))
    }

    func editFolders(id: String, add: [String], remove: [String]) async throws {
        let _: EditResult = try await post("/saves/folders", IdsEdit(ids: [id], add: add, remove: remove))
    }

    func setRating(id: String, rating: Int) async throws {
        let _: EditResult = try await post("/saves/rating", IdsEdit(ids: [id], rating: rating))
    }

    func setNote(id: String, note: String?) async throws {
        let _: EditResult = try await post("/saves/note", NoteEdit(id: id, note: note))
    }

    func trash(id: String) async throws {
        let _: EditResult = try await post("/saves/trash", IdsEdit(ids: [id]))
    }

    func restore(id: String) async throws {
        let _: EditResult = try await post("/saves/restore", IdsEdit(ids: [id]))
    }
}
