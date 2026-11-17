import Foundation
import Security

struct Connection: Equatable {
    var baseURL: URL
    var token: String
}

enum ConnectionStore {
    static let group = "group.com.wormadev.ripple"
    private static let service = "com.wormadev.ripple"
    private static let account = "pond-token"
    private static let urlKey = "baseURL"

    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func load() -> Connection? {
        guard let url = defaults.url(forKey: urlKey), let token = readToken() else { return nil }
        return Connection(baseURL: url, token: token)
    }

    static func save(_ connection: Connection) throws {
        clearToken()
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: Data(connection.token.utf8),
        ] as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        defaults.set(connection.baseURL, forKey: urlKey)
    }

    static func clear() {
        clearToken()
        defaults.removeObject(forKey: urlKey)
    }

    private static func readToken() -> String? {
        var out: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
        ] as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func clearToken() {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}
