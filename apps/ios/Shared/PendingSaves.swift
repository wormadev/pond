import Foundation

/// URLs shared while the Mac was unreachable. The app sends them on next launch.
enum PendingSaves {
    private static let key = "pendingSaves"

    static var urls: [String] {
        ConnectionStore.defaults.stringArray(forKey: key) ?? []
    }

    static func add(_ url: String) {
        ConnectionStore.defaults.set(urls.filter { $0 != url } + [url], forKey: key)
    }

    static func remove(_ url: String) {
        ConnectionStore.defaults.set(urls.filter { $0 != url }, forKey: key)
    }

    /// Sends every queued URL. A URL Pond rejects is dropped; one that fails to send stays queued.
    static func flush(using api: PondAPI) async {
        for url in urls {
            do {
                _ = try await api.enqueue(url: url)
                remove(url)
            } catch let error as PondError where error.code == "unsupported_url" {
                remove(url)
            } catch {
                return
            }
        }
    }
}
