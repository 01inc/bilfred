import Foundation
import Security
import OSLog

enum Keychain {
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bilfred.session", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            Logger(subsystem: "com.bilfred.ios", category: "session").notice("Credential read status: \(status)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bilfred.session", kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            Logger(subsystem: "com.bilfred.ios", category: "session").error("Credential write status: \(status)")
            throw APIError(message: "Økten kunne ikke lagres sikkert på enheten.", status: 0)
        }
    }
}

struct APIError: LocalizedError, Sendable {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

actor APIClient {
    let baseURL: URL
    private var token: String?
    private var sessionTask: Task<String, Error>?
    private(set) var didCreateSession = false
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "BilfredAPIBaseURL") as? String
        let url = URL(string: configured ?? "http://localhost:8008")!
        baseURL = url
        token = Keychain.read(url.absoluteString)
        encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private func ensureSession() async throws -> String {
        if let token { return token }
        if let sessionTask { return try await sessionTask.value }
        let task = Task<String, Error> {
            let installation: Installation = try await self.request("/v1/installations", method: "POST", authenticated: false)
            return installation.token
        }
        sessionTask = task
        do {
            let value = try await task.value
            try Keychain.save(value, account: baseURL.absoluteString)
            token = value; didCreateSession = true; sessionTask = nil
            return value
        } catch { sessionTask = nil; throw error }
    }

    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", data: Data? = nil, authenticated: Bool = true) async throws -> T {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = data; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated { request.setValue("Bearer \(try await ensureSession())", forHTTPHeaderField: "Authorization") }
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "Vi får ikke kontakt akkurat nå.", status: 0) }
        guard 200..<300 ~= http.statusCode else {
            Logger(subsystem: "com.bilfred.ios", category: "api").error("Request failed: HTTP \(http.statusCode)")
            let detail = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["detail"] as? String
            throw APIError(message: detail ?? "Noe gikk galt. Prøv igjen.", status: http.statusCode)
        }
        do { return try decoder.decode(T.self, from: body) }
        catch {
            Logger(subsystem: "com.bilfred.ios", category: "api").error("Response format mismatch: \(String(describing: error), privacy: .private)")
            throw APIError(message: "Vi kunne ikke lese svaret. Prøv igjen.", status: 0)
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B) async throws -> T {
        try await request(path, method: "POST", data: encoder.encode(body))
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B) async throws -> T {
        try await request(path, method: "PATCH", data: encoder.encode(body))
    }
}
