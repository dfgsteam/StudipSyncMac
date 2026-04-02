import Foundation

actor StudIPForumRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func fetchCourseForumCategories(courseID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [ForumCategoryDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(courseID)
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/forum-categories",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "forum-categories", "collection", "items"])
    }

    func fetchForumCategory(id: String) async throws -> ForumCategoryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/forum-categories/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "forum-categories", "item"])
    }

    func fetchForumCategoryEntries(categoryID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [ForumEntryDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(categoryID)
        let data = try await apiClient.performRequest(
            path: "/v1/forum-categories/\(escapedID)/entries",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "forum-entries", "entries", "collection", "items"])
    }

    func createCourseForumCategory(courseID: String, attributes: ForumCategoryWriteAttributesDTO) async throws -> ForumCategoryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(courseID)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<ForumCategoryWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "forum-categories",
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/forum-categories",
            method: .post,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "forum-categories", "item"])
    }

    func updateForumCategory(id: String, attributes: ForumCategoryWriteAttributesDTO) async throws -> ForumCategoryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<ForumCategoryWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "forum-categories",
                id: id,
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/forum-categories/\(escapedID)",
            method: .patch,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "forum-categories", "item"])
    }

    func deleteForumCategory(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/forum-categories/\(escapedID)", method: .delete)
    }

    func fetchForumEntry(id: String) async throws -> ForumEntryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/forum-entries/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "forum-entries", "item"])
    }

    func fetchForumEntryEntries(entryID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [ForumEntryDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(entryID)
        let data = try await apiClient.performRequest(
            path: "/v1/forum-entries/\(escapedID)/entries",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "forum-entries", "entries", "collection", "items"])
    }

    func createForumEntryInCategory(categoryID: String, attributes: ForumEntryWriteAttributesDTO) async throws -> ForumEntryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(categoryID)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<ForumEntryWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "forum-entries",
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/forum-categories/\(escapedID)/entries",
            method: .post,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "forum-entries", "item"])
    }

    func createForumEntryReply(entryID: String, attributes: ForumEntryWriteAttributesDTO) async throws -> ForumEntryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(entryID)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<ForumEntryWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "forum-entries",
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/forum-entries/\(escapedID)/entries",
            method: .post,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "forum-entries", "item"])
    }

    func updateForumEntry(id: String, attributes: ForumEntryWriteAttributesDTO) async throws -> ForumEntryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<ForumEntryWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "forum-entries",
                id: id,
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/forum-entries/\(escapedID)",
            method: .patch,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "forum-entries", "item"])
    }

    func deleteForumEntry(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/forum-entries/\(escapedID)", method: .delete)
    }
}
