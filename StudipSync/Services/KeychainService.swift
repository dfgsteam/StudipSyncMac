import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct HTTPBasicCredentials: Codable {
    let username: String
    let password: String
}

struct KeychainService {
    private let service = "StudipSync.Credentials"

    func saveCredentials(_ credentials: HTTPBasicCredentials, for baseURL: URL) throws {
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

    func readCredentials(for baseURL: URL) throws -> HTTPBasicCredentials? {
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

        return try JSONDecoder().decode(HTTPBasicCredentials.self, from: data)
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
}
