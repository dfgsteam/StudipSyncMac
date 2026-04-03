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

enum StudIPHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

struct StudIPHTTPResponse {
    let data: Data
    let statusCode: Int
    let headers: [AnyHashable: Any]
}

final class StudIPAPIClient {
    enum APIClientError: LocalizedError {
        case invalidPath(String)
        case missingCredentials
        case invalidResponse(String)
        case unauthorized(String)
        case sandboxNetworkPermissionMissing
        case httpStatus(Int, String?, String)

        var errorDescription: String? {
            switch self {
            case .invalidPath(let requestReference):
                return "Ungueltiger API-Pfad. Request: \(requestReference)"
            case .missingCredentials:
                return "Kein Login hinterlegt. Bitte Username/Passwort speichern."
            case .invalidResponse(let requestURL):
                return "Ungueltige API-Antwort. URL: \(requestURL)"
            case .unauthorized(let requestURL):
                return "Autorisierung fehlgeschlagen (Username/Passwort pruefen). URL: \(requestURL)"
            case .sandboxNetworkPermissionMissing:
                return "App-Sandbox blockiert Netzwerk. Aktiviere in den Target Capabilities: Outgoing Connections (Client)."
            case .httpStatus(let code, let body, let requestURL):
                if let body, !body.isEmpty {
                    return "HTTP-Fehler \(code) auf \(requestURL): \(body)"
                }
                return "HTTP-Fehler \(code) auf \(requestURL)"
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
        try await performRequest(path: path, queryItems: queryItems, method: .get)
    }

    func performRawPathRequest(
        path: String,
        method: StudIPHTTPMethod = .get,
        body: Data? = nil,
        acceptHeader: String? = "*/*",
        contentTypeHeader: String? = nil
    ) async throws -> Data {
        let response = try await performRawPathRequestWithResponse(
            path: path,
            method: method,
            body: body,
            acceptHeader: acceptHeader,
            contentTypeHeader: contentTypeHeader
        )

        if method == .head {
            return response.data
        }

        return response.data
    }

    func performRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: StudIPHTTPMethod,
        body: Data? = nil,
        acceptHeader: String? = "application/vnd.api+json, application/json",
        contentTypeHeader: String? = nil
    ) async throws -> Data {
        let response = try await performRequestWithResponse(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
            acceptHeader: acceptHeader,
            contentTypeHeader: contentTypeHeader
        )

        if method == .head {
            return response.data
        }

        return normalizedResponseData(response.data)
    }

    func performRequest<Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: StudIPHTTPMethod,
        body: Body,
        acceptHeader: String? = "application/vnd.api+json, application/json",
        contentTypeHeader: String? = "application/vnd.api+json"
    ) async throws -> Data {
        let encodedBody = try JSONEncoder().encode(body)
        return try await performRequest(
            path: path,
            queryItems: queryItems,
            method: method,
            body: encodedBody,
            acceptHeader: acceptHeader,
            contentTypeHeader: contentTypeHeader
        )
    }

    func performRequestWithResponse(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: StudIPHTTPMethod,
        body: Data? = nil,
        acceptHeader: String? = "application/vnd.api+json, application/json",
        contentTypeHeader: String? = nil
    ) async throws -> StudIPHTTPResponse {
        guard hasOutgoingNetworkPermission() else {
            throw APIClientError.sandboxNetworkPermissionMissing
        }

        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        guard let url = buildURL(baseURL: baseURL, path: path, queryItems: queryItems) else {
            throw APIClientError.invalidPath(requestReference(baseURL: baseURL, path: path, queryItems: queryItems))
        }

        guard let credentials = try keychainService.readCredentials(for: baseURL) else {
            throw APIClientError.missingCredentials
        }

        return try await send(
            url: url,
            credentials: credentials,
            method: method,
            body: body,
            acceptHeader: acceptHeader,
            contentTypeHeader: contentTypeHeader
        )
    }

    func performRawPathRequestWithResponse(
        path: String,
        method: StudIPHTTPMethod = .get,
        body: Data? = nil,
        acceptHeader: String? = "*/*",
        contentTypeHeader: String? = nil
    ) async throws -> StudIPHTTPResponse {
        guard hasOutgoingNetworkPermission() else {
            throw APIClientError.sandboxNetworkPermissionMissing
        }

        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        guard let url = buildRawURL(baseURL: baseURL, path: path) else {
            throw APIClientError.invalidPath("\(baseURL.absoluteString) | \(path)")
        }

        guard let credentials = try keychainService.readCredentials(for: baseURL) else {
            throw APIClientError.missingCredentials
        }

        return try await send(
            url: url,
            credentials: credentials,
            method: method,
            body: body,
            acceptHeader: acceptHeader,
            contentTypeHeader: contentTypeHeader
        )
    }

    func makeCURL(path: String, queryItems: [URLQueryItem] = []) async throws -> String {
        try await makeCURL(path: path, queryItems: queryItems, method: .get)
    }

    func makeCURL(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: StudIPHTTPMethod,
        body: Data? = nil,
        contentTypeHeader: String? = nil
    ) async throws -> String {
        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        guard let url = buildURL(baseURL: baseURL, path: path, queryItems: queryItems) else {
            throw APIClientError.invalidPath(requestReference(baseURL: baseURL, path: path, queryItems: queryItems))
        }

        guard let credentials = try keychainService.readCredentials(for: baseURL) else {
            throw APIClientError.missingCredentials
        }

        // Never leak live credentials in debug output.
        let authorizationHeader = "Authorization: Basic <REDACTED>"

        var parts = [
            "curl",
            "-i",
            "-X",
            method.rawValue,
            "'\(shellEscaped(url.absoluteString))'",
            "-H",
            "'\(shellEscaped(authorizationHeader))'"
        ]

        if let contentTypeHeader {
            parts.append(contentsOf: ["-H", "'\(shellEscaped("Content-Type: \(contentTypeHeader)"))'"])
        }

        if let body, !body.isEmpty, let bodyString = String(data: body, encoding: .utf8) {
            parts.append(contentsOf: ["--data", "'\(shellEscaped(bodyString))'"])
        }

        return parts.joined(separator: " ")
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

    private func buildRawURL(baseURL: URL, path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absoluteURL = URL(string: trimmed), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let supplied = URLComponents(string: trimmed) {
            let resolvedPath: String
            if supplied.path.isEmpty {
                resolvedPath = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
            } else {
                resolvedPath = supplied.path.hasPrefix("/") ? supplied.path : "/\(supplied.path)"
            }

            components.path = resolvedPath
            components.percentEncodedQuery = supplied.percentEncodedQuery
            return components.url
        }

        components.path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return components.url
    }

    private func send(
        url: URL,
        credentials: HTTPBasicCredentials,
        method: StudIPHTTPMethod,
        body: Data?,
        acceptHeader: String?,
        contentTypeHeader: String?
    ) async throws -> StudIPHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30

        if let acceptHeader {
            request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        }
        if let contentTypeHeader {
            request.setValue(contentTypeHeader, forHTTPHeaderField: "Content-Type")
        }
        if let body {
            request.httpBody = body
        }

        let raw = "\(credentials.username):\(credentials.password)"
        let token = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse(url.absoluteString)
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIClientError.unauthorized(url.absoluteString)
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)
            throw APIClientError.httpStatus(http.statusCode, bodyText, url.absoluteString)
        }

        return StudIPHTTPResponse(data: data, statusCode: http.statusCode, headers: http.allHeaderFields)
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

    private func requestReference(baseURL: URL, path: String, queryItems: [URLQueryItem]) -> String {
        let query = URLComponents(url: URL(string: "https://stub.invalid")!, resolvingAgainstBaseURL: false)
        let queryString: String
        if queryItems.isEmpty {
            queryString = ""
        } else {
            var components = query
            components?.queryItems = queryItems
            let encoded = components?.percentEncodedQuery ?? ""
            queryString = encoded.isEmpty ? "" : "?\(encoded)"
        }

        return "\(baseURL.absoluteString) | \(path)\(queryString)"
    }
}
