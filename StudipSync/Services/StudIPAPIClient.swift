import Foundation
import Security

enum StudIPAPIPathResolver {
    private static let canonicalAPIPrefix = "/jsonapi.php/v1"

    static func buildURL(baseURL: URL, path: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = trimmedTrailingSlash(components.path)
        let apiBasePath = normalizedAPIBasePath(from: basePath)
        let endpointPath = normalizedEndpointPath(path)

        components.path = apiBasePath + endpointPath
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    static func normalizedAPIBasePath(from basePath: String) -> String {
        if basePath.hasSuffix(canonicalAPIPrefix) {
            return basePath
        }
        if basePath.hasSuffix("/jsonapi.php") {
            return basePath + "/v1"
        }
        if basePath.hasSuffix("/v1") {
            return basePath
        }
        if basePath.isEmpty {
            return canonicalAPIPrefix
        }
        return basePath + canonicalAPIPrefix
    }

    static func normalizedEndpointPath(_ path: String) -> String {
        let candidate = path.hasPrefix("/") ? path : "/\(path)"

        if let suffix = removingPrefix("/jsonapi.php/v1", from: candidate) {
            return suffix
        }
        if let suffix = removingPrefix("/v1", from: candidate) {
            return suffix
        }
        return candidate
    }

    private static func trimmedTrailingSlash(_ path: String) -> String {
        if path == "/" {
            return ""
        }
        if path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    private static func removingPrefix(_ prefix: String, from value: String) -> String? {
        if value == prefix {
            return ""
        }

        let prefixWithSlash = "\(prefix)/"
        guard value.hasPrefix(prefixWithSlash) else {
            return nil
        }

        return "/\(value.dropFirst(prefixWithSlash.count))"
    }
}

final class StudIPAPIClient {
    enum APIClientError: LocalizedError {
        case invalidPath
        case missingCredentials
        case invalidResponse
        case unauthorized
        case sandboxNetworkPermissionMissing
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "Ungueltiger API-Pfad."
            case .missingCredentials:
                return "Kein Login hinterlegt. Bitte Username/Passwort speichern."
            case .invalidResponse:
                return "Ungueltige API-Antwort."
            case .unauthorized:
                return "Autorisierung fehlgeschlagen (Username/Passwort pruefen)."
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

        guard let credentials = try keychainService.readCredentials(for: baseURL) else {
            throw APIClientError.missingCredentials
        }

        return try await send(url: url, credentials: credentials)
    }

    func makeCURL(path: String, queryItems: [URLQueryItem] = []) async throws -> String {
        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        guard let url = buildURL(baseURL: baseURL, path: path, queryItems: queryItems) else {
            throw APIClientError.invalidPath
        }

        guard let credentials = try keychainService.readCredentials(for: baseURL) else {
            throw APIClientError.missingCredentials
        }

        let raw = "\(credentials.username):\(credentials.password)"
        let token = Data(raw.utf8).base64EncodedString()
        let authorizationHeader = "Authorization: Basic \(token)"

        return "curl -i -X GET '\(shellEscaped(url.absoluteString))' -H '\(shellEscaped(authorizationHeader))'"
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
        StudIPAPIPathResolver.buildURL(baseURL: baseURL, path: path, queryItems: queryItems)
    }

    private func send(url: URL, credentials: HTTPBasicCredentials) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/vnd.api+json, application/json", forHTTPHeaderField: "Accept")

        let raw = "\(credentials.username):\(credentials.password)"
        let token = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")

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

        return normalizedResponseData(data)
    }

    private func normalizedResponseData(_ data: Data) -> Data {
        var current = data

        for _ in 0..<2 {
            guard let decoded = try? JSONSerialization.jsonObject(with: current) else {
                return current
            }

            if let stringPayload = decoded as? String {
                let trimmed = stringPayload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                    || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
                    return current
                }
                if let reencoded = trimmed.data(using: .utf8) {
                    current = reencoded
                    continue
                }
            }

            return current
        }

        return current
    }

    private func shellEscaped(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "'\\''")
    }
}
