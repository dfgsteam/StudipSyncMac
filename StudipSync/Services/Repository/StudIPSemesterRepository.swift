import Foundation

actor StudIPSemesterRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func fetchSemesters(offset: Int, limit: Int) async throws -> [SemesterDTO] {
        let query = StudIPQuery<SemesterResource>()
            .paginate(offset: offset, limit: limit)
        return try await fetchCollection(query)
    }

    func fetchSemester(id: String) async throws -> SemesterDTO {
        try await fetchOne(StudIPQuery<SemesterResource>().byID(canonicalStudIPID(id)))
    }

    private func fetchCollection<Resource: StudIPResourceDescriptor>(_ query: StudIPQuery<Resource>) async throws -> [Resource.Model] {
        let data = try await apiClient.performRequest(path: query.path, queryItems: query.queryItems)
        return try responseDecoder.parseCollection(
            from: data,
            fallbackCollectionKeys: Resource.fallbackCollectionKeys
        )
    }

    private func fetchOne<Resource: StudIPResourceDescriptor>(_ query: StudIPQuery<Resource>) async throws -> Resource.Model {
        let data = try await apiClient.performRequest(path: query.path, queryItems: query.queryItems)
        return try responseDecoder.parseEntity(
            from: data,
            fallbackObjectKeys: Resource.fallbackCollectionKeys + ["data", "item"]
        )
    }
}
