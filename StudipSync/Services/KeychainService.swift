import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct StudIPStoredCredentials: Codable {
    var apiKey: String?
    var username: String?
    var password: String?

    var hasAPIKey: Bool {
        if let apiKey {
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var hasBasicCredentials: Bool {
        guard let username, let password else { return false }
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var basicCredentials: HTTPBasicCredentials? {
        guard hasBasicCredentials else { return nil }
        return HTTPBasicCredentials(
            username: username!.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password!
        )
    }
}

struct HTTPBasicCredentials: Codable {
    let username: String
    let password: String
}

struct KeychainService {
    private let service = "StudipSync.Credentials"

    func saveAPIKey(_ apiKey: String, for baseURL: URL) throws {
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var stored = try readStoredCredentials(for: baseURL) ?? StudIPStoredCredentials()
        stored.apiKey = normalizedAPIKey.isEmpty ? nil : normalizedAPIKey
        try saveStoredCredentials(stored, for: baseURL)
    }

    func readAPIKey(for baseURL: URL) throws -> String? {
        guard let stored = try readStoredCredentials(for: baseURL) else {
            return nil
        }

        guard let apiKey = stored.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }

        return apiKey
    }

    func saveCredentials(_ credentials: HTTPBasicCredentials, for baseURL: URL) throws {
        var stored = try readStoredCredentials(for: baseURL) ?? StudIPStoredCredentials()
        stored.username = credentials.username.trimmingCharacters(in: .whitespacesAndNewlines)
        stored.password = credentials.password
        try saveStoredCredentials(stored, for: baseURL)
    }

    func readCredentials(for baseURL: URL) throws -> HTTPBasicCredentials? {
        guard let stored = try readStoredCredentials(for: baseURL) else {
            return nil
        }
        return stored.basicCredentials
    }

    func readStoredCredentials(for baseURL: URL) throws -> StudIPStoredCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName(for: baseURL),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        if let decoded = try? JSONDecoder().decode(StudIPStoredCredentials.self, from: data) {
            return decoded
        }

        if let legacyBasic = try? JSONDecoder().decode(HTTPBasicCredentials.self, from: data) {
            return StudIPStoredCredentials(
                apiKey: nil,
                username: legacyBasic.username,
                password: legacyBasic.password
            )
        }

        throw KeychainError.invalidData
    }

    func deleteCredentials(for baseURL: URL) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName(for: baseURL)
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func accountName(for baseURL: URL) -> String {
        var value = baseURL.absoluteString.lowercased()
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func saveStoredCredentials(_ credentials: StudIPStoredCredentials, for baseURL: URL) throws {
        let account = accountName(for: baseURL)
        let data = try JSONEncoder().encode(credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        let addQuery: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]) { _, new in new }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
