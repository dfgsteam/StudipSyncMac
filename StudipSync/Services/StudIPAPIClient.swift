import Foundation
import Security

final class StudIPAPIClient {
    enum APIClientError: LocalizedError {
        case invalidPath
        case missingAPIKey
        case invalidResponse
        case unauthorized
        case sandboxNetworkPermissionMissing
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "Ungueltiger API-Pfad."
            case .missingAPIKey:
                return "Kein API-Key hinterlegt."
            case .invalidResponse:
                return "Ungueltige API-Antwort."
            case .unauthorized:
                return "Autorisierung fehlgeschlagen (API-Key/Auth-Schema pruefen)."
            case .sandboxNetworkPermissionMissing:
                return "App-Sandbox blockiert Netzwerk. Aktiviere in den Target Capabilities: Outgoing Connections (Client)."
            case .httpStatus(let code, let body):
                if let body, !body.isEmpty {
                    return "HTTP-Fehler \(code): \(body)"
                }
                return "HTTP-Fehler: \(code)"
            }
        }
    }

    private enum AuthScheme {
        case bearer
        case basic
    }

    private let session: URLSession
    private let settingsStore: SettingsStore
    private let keychainService: KeychainService

    init(session: URLSession = .shared, settingsStore: SettingsStore, keychainService: KeychainService) {
        self.session = session
        self.settingsStore = settingsStore
        self.keychainService = keychainService
    }

    func performRequest(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        guard hasOutgoingNetworkPermission() else {
            throw APIClientError.sandboxNetworkPermissionMissing
        }

        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        guard let url = buildURL(baseURL: baseURL, path: path, queryItems: queryItems) else {
            throw APIClientError.invalidPath
        }

        guard let key = try keychainService.readAPIKey(for: baseURL), !key.isEmpty else {
            throw APIClientError.missingAPIKey
        }

        do {
            return try await send(url: url, apiKey: key, scheme: .bearer)
        } catch APIClientError.unauthorized {
            return try await send(url: url, apiKey: key, scheme: .basic)
        }
    }

    private func hasOutgoingNetworkPermission() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return true
        }

        let sandboxEntitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        guard let isSandboxed = sandboxEntitlement as? Bool, isSandboxed else {
            return true
        }

        let networkEntitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil)
        return (networkEntitlement as? Bool) == true
    }

    private func buildURL(baseURL: URL, path: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let basePath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
        components.path = basePath + normalizedPath
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url
    }

    private func send(url: URL, apiKey: String, scheme: AuthScheme) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch scheme {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .basic:
            let raw = "\(apiKey):"
            let token = Data(raw.utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIClientError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw APIClientError.httpStatus(http.statusCode, body)
        }

        return data
    }
}
