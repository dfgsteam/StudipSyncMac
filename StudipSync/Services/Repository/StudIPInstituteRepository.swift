import Foundation

actor StudIPInstituteRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func fetchInstitutes(offset: Int = 0, limit: Int = 200, search: String? = nil) async throws -> [InstituteDTO] {
        var queryItems = StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        if let search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "filter[search]", value: search))
        }

        let data = try await apiClient.performRequest(path: "/v1/institutes", queryItems: queryItems)
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "institutes", "collection", "items"])
    }

    func fetchInstitute(id: String) async throws -> InstituteDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/institutes/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "institutes", "item"])
    }
}
