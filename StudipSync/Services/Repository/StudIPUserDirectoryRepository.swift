import Foundation

actor StudIPUserDirectoryRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func fetchUsers(offset: Int = 0, limit: Int = 30, search: String? = nil) async throws -> [UserDTO] {
        var queryItems = StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        if let search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "filter[search]", value: search))
        }

        let data = try await apiClient.performRequest(path: "/v1/users", queryItems: queryItems)
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "users", "collection", "items"])
    }

    func fetchMe() async throws -> UserDTO {
        let data = try await apiClient.performRequest(path: "/v1/users/me")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "users", "item"])
    }

    func fetchUser(id: String) async throws -> UserDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/users/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "users", "item"])
    }

    func deleteUser(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/users/\(escapedID)", method: .delete)
    }

    func fetchInstituteMemberships(userID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [InstituteMembershipDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(userID)
        let data = try await apiClient.performRequest(
            path: "/v1/users/\(escapedID)/institute-memberships",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "institute-memberships", "collection", "items"])
    }
}
