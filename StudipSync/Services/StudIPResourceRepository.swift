import Foundation

actor StudIPResourceRepository {
    private let apiClient: StudIPAPIClient

    init(apiClient: StudIPAPIClient) {
        self.apiClient = apiClient
    }

    func fetchSemesters() async throws -> [SemesterDTO] {
        let data = try await apiClient.performRequest(path: "/api.php/semesters")
        return try JSONDecoder().decode([SemesterDTO].self, from: data)
    }
}

struct SemesterDTO: Codable, Hashable, Identifiable {
    let id: String
    let title: String
}
