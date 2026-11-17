import CommonCrypto
import Foundation

/// The Pond Connect account service: sign in, then reach a linked Mac through its relay.
enum PondAccount {
    static let server = URL(string: "https://ponds.worma.dev")!

    struct Machine: Decodable, Identifiable, Hashable {
        var id: String
        var name: String
        var online: Bool
    }

    private struct Envelope<T: Decodable>: Decodable {
        struct Failure: Decodable {
            var code: String
            var message: String
        }

        var data: T?
        var error: Failure?
    }

    private struct Token: Decodable { var token: String }
    private struct Me: Decodable { var machines: [Machine] }
    private struct Empty: Decodable {}

    private struct Credentials: Encodable {
        struct Device: Encodable {
            var kind = "phone"
            var name: String
        }

        var email: String
        var key: String
        var device: Device
    }

    static func signIn(email: String, password: String, creating: Bool, deviceName: String) async throws -> String {
        let key = try await Task.detached { try deriveKey(email: email, password: password) }.value
        let body = Credentials(email: email, key: key, device: .init(name: deviceName))
        let result: Token = try await send(creating ? "/v1/signup" : "/v1/login", method: "POST", body: body)
        return result.token
    }

    static func machines(token: String) async throws -> [Machine] {
        let me: Me = try await send("/v1/me", token: token)
        return me.machines
    }

    static func signOut(token: String) async {
        let _: Empty? = try? await send("/v1/logout", method: "POST", token: token)
    }

    static func connection(to machine: Machine, token: String) -> Connection {
        Connection(baseURL: server.appending(path: "m/\(machine.id)"), token: token)
    }

    /// The password stays on this phone. The service only ever sees this stretched key.
    private static func deriveKey(email: String, password: String) throws -> String {
        let salt = Array("pond-connect:\(email.trimmingCharacters(in: .whitespaces).lowercased())".utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
            salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000,
            &derived, derived.count
        )
        guard status == kCCSuccess else { throw PondError(code: "internal", message: "Couldn't prepare the password.") }
        return Data(derived).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func send<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil, body: (some Encodable)? = Optional<Credentials>.none) async throws -> T {
        var request = URLRequest(url: server.appending(path: path))
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let error = envelope.error { throw PondError(code: error.code, message: error.message) }
        guard let value = envelope.data else { throw PondError(code: "internal", message: "Pond Connect sent an empty response.") }
        return value
    }
}
