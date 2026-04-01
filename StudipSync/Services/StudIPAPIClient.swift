import Foundation

final class StudIPAPIClient {
    enum APIClientError: Error {
        case invalidResponse
        case missingAPIKey
    }

    private let session: URLSession
    private let settingsStore: SettingsStore
    private let keychainService: KeychainService

    init(session: URLSession = .shared, settingsStore: SettingsStore, keychainService: KeychainService) {
        self.session = session
        self.settingsStore = settingsStore
        self.keychainService = keychainService
    }

    func performRequest(path: String) async throws -> Data {
        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw URLError(.badURL)
        }

        guard let key = try keychainService.readAPIKey(for: baseURL), !key.isEmpty else {
            throw APIClientError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIClientError.invalidResponse
        }

        return data
    }
}
