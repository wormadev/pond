import Foundation
import UIKit
@testable import Ripple

/// Answers Pond's API from fixtures, so screens load through the same client as real data.
final class FixtureProtocol: URLProtocol {
    enum Mode: String { case full, worst, empty, failed, loading }

    static func api(_ mode: Mode) -> PondAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return PondAPI(
            connection: Connection(baseURL: URL(string: "https://\(mode.rawValue).example.ts.net:41610")!, token: "fixture"),
            session: URLSession(configuration: config)
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let mode = Mode(rawValue: request.url?.host()?.split(separator: ".").first.map(String.init) ?? "") ?? .full
        if mode == .loading { return }
        guard mode != .failed, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let path = url.path().replacing("/api/v2", with: "")
        if path == "/saves/thumb" {
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value ?? ""
            id == "broken" ? respond(404, Data(), "text/plain") : respond(200, Fixtures.thumbnail(for: id), "image/png")
        } else if let data = Fixtures.body(path, mode: mode, operation: operationName) {
            respond(200, data, "application/json")
        } else {
            respond(422, Data(#"{"status":"error","error":{"code":"invalid","message":"No such file."}}"#.utf8), "application/json")
        }
    }

    /// URLProtocol sees a POST body only as a stream.
    private var operationName: String? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["operation"] as? String
    }

    private func respond(_ status: Int, _ data: Data, _ type: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

enum Fixtures {
    static func body(_ path: String, mode: FixtureProtocol.Mode, operation: String? = nil) -> Data? {
        let worst = mode == .worst
        let empty = mode == .empty
        let data: Any
        switch path {
        case "/library/info":
            data = [
                "libraryId": "fixture", "name": worst ? "Abdulaziz's Very Long Personal Research Library" : "My Pond",
                "counts": ["active": empty ? 0 : worst ? 128_400 : 2255, "trashed": worst ? 1284 : 2, "ingesting": empty ? 0 : worst ? 99_999 : 1085, "failed": worst ? 312 : 2],
                "queue": ["pending": worst ? 1_284_000 : 7595, "running": worst ? 12 : 0],
            ]
        case "/library/tags":
            data = empty ? [] : worst ? worstTags : ["ai": 220, "shopping": 174, "tech": 146, "other": 130, "humor": 100, "coding": 99].map {
                ["name": $0.key, "count": $0.value, "starred": false]
            }.sorted { ($0["count"] as! Int) > ($1["count"] as! Int) }
        case "/library/folders":
            data = worst ? [["id": "f1", "name": "Reference-material-for-the-apartment-renovation-2026", "count": 1284], ["id": "f2", "name": "X", "count": 0]] : []
        case "/library/views":
            data = worst ? [["id": "v1", "name": "Videos saved this month that I have not rated yet", "kind": "saved_view", "query": [:], "sortKey": "savedAt", "sortDir": "desc"]] : []
        case "/library/sources":
            data = empty ? [] : [["source": "instagram", "count": worst ? 128_400 : 2255]]
        case "/library/query", "/library/search":
            let saves = empty ? [] : worst ? worstSaves : fullSaves
            data = ["saves": saves, "total": empty ? 0 : worst ? 1284 : 1168, "nextCursor": NSNull()]
        case "/saves/related":
            data = empty ? [] : Array((worst ? worstSaves : fullSaves).prefix(8))
        case "/library/recent":
            data = [
                ["path": "/Users/me/Pond", "name": worst ? "Abdulaziz's Very Long Personal Research Library" : "My Pond", "available": true, "active": true, "lastOpened": 0, "icon": NSNull(), "accent": NSNull()],
                ["path": "/Volumes/Archive/Design.pond", "name": "Design", "available": !worst, "active": false, "lastOpened": 0, "icon": NSNull(), "accent": NSNull()],
            ]
        case "/operations/preview":
            data = ["token": "fixture", "operation": operation ?? "", "libraryId": "fixture", "expiresAt": 0]
        case "/operations/run":
            guard let operation, let result = operationResult(operation, mode: mode) else { return nil }
            data = result
        case "/saves/info":
            data = (worst ? worstSaves : fullSaves)[0]
        case "/saves/text":
            data = ["description": "", "caption": worst ? String(repeating: "تتكون الهدية من حقيبة عدة البخور فيها مبخر طبقات وولاعة وملقط. ", count: 12) : "Animated websites, built in an afternoon.", "ocr": "", "transcript": ""]
        default:
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: ["status": "success", "data": data])
    }

    private static func source(_ id: String, _ source: String, _ handle: String, label: String? = nil, paused: Bool = false, error: String? = nil, syncing: Bool = false) -> [String: Any] {
        var sync: [String: Any] = ["lastSyncedAt": "2026-11-17T08:00:00.000Z", "paused": paused]
        sync["lastError"] = error
        var row: [String: Any] = ["id": id, "source": source, "handle": handle, "syncing": syncing, "connected": true, "sync": sync]
        row["label"] = label
        return row
    }

    private static func operationResult(_ name: String, mode: FixtureProtocol.Mode) -> Any? {
        let worst = mode == .worst
        let empty = mode == .empty
        switch name {
        case "accounts.list":
            return ["accounts": empty ? [] : [
                source("a1", "instagram", worst ? "averyveryverylongunbreakablehandlewithoutanyspaces" : "wormadev", syncing: worst),
                source("a2", "twitter", "wormadev", error: worst ? "Sign in again" : nil),
            ]]
        case "watches.list":
            return ["watches": empty ? [] : [source("w1", "youtube", "domestika", label: worst ? "Domestika: online courses for creatives, the long channel name" : "Domestika", paused: true)]]
        case "agent.chats":
            return empty ? [] : [
                ["id": "c1", "title": worst ? "Find every interior design reel I saved last spring and group them by room" : "Design references", "updatedAt": "2026-11-17T08:00:00.000Z", "fishId": "f"],
                ["id": "c2", "title": NSNull(), "updatedAt": "2026-11-10T08:00:00.000Z", "fishId": "f"],
            ]
        case "agent.messages":
            return [
                ["id": "m1", "role": "user", "content": worst ? String(repeating: "Which of my saves mention lamps? ", count: 8) : "Which saves mention lamps?"],
                ["id": "m2", "role": "assistant", "content": worst ? String(repeating: "I found **12 Saves** about lamps, mostly from Instagram. ", count: 10) : "I found **12 Saves** about lamps."],
            ]
        case "agent.listAvailableModels":
            return ["providers": [["provider": "anthropic", "ok": true, "models": [["id": "claude"]]]]]
        default:
            return nil
        }
    }

    static func save(_ mode: FixtureProtocol.Mode) -> Save {
        let raw = (mode == .worst ? worstSaves : fullSaves)[0]
        return try! JSONDecoder().decode(Save.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private static let worstTags: [[String: Any]] = [
        ["name": "interior-design-inspiration-for-the-new-apartment", "count": 1284, "starred": false],
        ["name": "a", "count": 1, "starred": false],
        ["name": "تصميم داخلي", "count": 0, "starred": false],
        ["name": "ai", "count": 128_400, "starred": false],
        ["name": "ai", "count": 7, "starred": false],
    ]

    private static func row(_ id: String, _ author: String?, _ title: String?, kind: String = "video", tags: [String] = ["ai"], status: String = "complete", thumbnail: Bool = true, note: String? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "id": id, "source": "instagram", "url": "https://www.instagram.com/reel/\(id)/", "tags": tags, "folderIds": [],
            "kind": kind, "status": status, "savedAt": 1_794_700_000_000.0, "media": ["files": 3], "thumbnail": thumbnail,
        ]
        row["author"] = author
        row["title"] = title
        row["note"] = note
        return row
    }

    private static let fullSaves: [[String: Any]] = (0..<24).map {
        row("s\($0)", ["Gadaou.AI", "Marcus Ng", "Bader Thiab", "Domestika"][$0 % 4], "Animated websites", kind: $0 % 3 == 0 ? "image" : "video", tags: ["design", "ai"])
    }

    private static let worstSaves: [[String: Any]] = [
        row("w0", "Abdelrahman-Soliman-Software-Engineer-And-Content-Creator-Official", "أحسن 3 Tools هتوفر عليك وقت ومجهود وأنت بتـ Code\nوالسطر الثاني", tags: ["interior-design-inspiration-for-the-new-apartment", "a", "تصميم داخلي", "ai", "coding", "shopping", "humor"], note: String(repeating: "Remember to compare this with the other three before buying. ", count: 6)),
        row("w1", "averyveryverylongunbreakablehandlewithoutanyspacesatall_1234567890@example.com", nil),
        row("w2", "J", "x", kind: "image"),
        row("w3", nil, nil, tags: []),
        row("w4", "Nguyễn Thị Hồng Nhung", "Phở bò tái nạm gầu gân sách, ก๋วยเตี๋ยวเรือ"),
        row("w5", "🩶🎀 𝔽𝕠𝕣 𝕎𝕒𝕤𝕙𝕚 🎀🩶", "😍😍😍"),
        row("w6", "Marcus Ng", "Same title"),
        row("w7", "Marcus Ng", "Same title"),
        row("broken", "Broken image", "Thumbnail that fails to load"),
        row("w9", "Still downloading", nil, status: "ingesting", thumbnail: false),
    ] + (10..<61).map { row("w\($0)", "Author \($0)", "Save \($0)") }

    /// A flat tile whose hue comes from the id; every third one is portrait like a reel.
    static func thumbnail(for id: String) -> Data {
        let seed = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let size = seed % 3 == 0 ? CGSize(width: 180, height: 180) : CGSize(width: 180, height: 320)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor(hue: CGFloat(seed % 12) / 12, saturation: 0.45, brightness: 0.7, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 1, alpha: 0.35).setFill()
            context.fill(CGRect(x: 20, y: size.height / 2 - 12, width: size.width - 40, height: 24))
        }
    }
}
