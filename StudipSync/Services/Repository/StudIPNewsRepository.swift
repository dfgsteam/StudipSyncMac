import Foundation

actor StudIPNewsRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func createNews(attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        try await createNews(path: "/v1/news", attributes: attributes)
    }

    func createCourseNews(courseID: String, attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(courseID)
        return try await createNews(path: "/v1/courses/\(escapedID)/news", attributes: attributes)
    }

    func createUserNews(userID: String, attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(userID)
        return try await createNews(path: "/v1/users/\(escapedID)/news", attributes: attributes)
    }

    func createNewsComment(newsID: String, content: String) async throws -> NewsCommentDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(newsID)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<CommentWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "comments",
                attributes: CommentWriteAttributesDTO(content: content),
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/news/\(escapedID)/comments",
            method: .post,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "comments", "item"])
    }

    func updateNews(newsID: String, attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(newsID)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<NewsWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "news",
                id: newsID,
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/news/\(escapedID)",
            method: .patch,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "news", "item"])
    }

    func fetchNews(id: String) async throws -> NewsDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/news/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "news", "item"])
    }

    func fetchCourseNews(courseID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(courseID)
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/news",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "news", "collection", "items"])
    }

    func fetchUserNews(userID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(userID)
        let data = try await apiClient.performRequest(
            path: "/v1/users/\(escapedID)/news",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "news", "collection", "items"])
    }

    func fetchNewsComments(newsID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [NewsCommentDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(newsID)
        let data = try await apiClient.performRequest(
            path: "/v1/news/\(escapedID)/comments",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "comments", "news-comments", "collection", "items"])
    }

    func fetchStudipNews(offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        let data = try await apiClient.performRequest(
            path: "/v1/studip/news",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "news", "collection", "items"])
    }

    func fetchAllNews(offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        let data = try await apiClient.performRequest(
            path: "/v1/news",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "news", "collection", "items"])
    }

    func deleteNews(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/news/\(escapedID)", method: .delete)
    }

    func deleteComment(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/comments/\(escapedID)", method: .delete)
    }

    func fetchNewsRanges(newsID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(newsID)
        let data = try await apiClient.performRequest(path: "/v1/news/\(escapedID)/relationships/ranges")

        if let wrapped: JSONAPIRelationshipIdentifiersDocumentDTO = try? JSONDecoder().decode(JSONAPIRelationshipIdentifiersDocumentDTO.self, from: data) {
            return wrapped.identifiers
        }

        let genericResources: [StudIPGenericResourceDTO] = try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "ranges", "collection", "items"])
        return genericResources.map { JSONAPIResourceIdentifierDTO(type: $0.type, id: $0.id) }
    }

    func patchNewsRanges(newsID: String, ranges: [JSONAPIResourceIdentifierDTO]) async throws {
        try await writeNewsRanges(newsID: newsID, method: .patch, ranges: ranges)
    }

    func postNewsRanges(newsID: String, ranges: [JSONAPIResourceIdentifierDTO]) async throws {
        try await writeNewsRanges(newsID: newsID, method: .post, ranges: ranges)
    }

    func deleteNewsRanges(newsID: String, ranges: [JSONAPIResourceIdentifierDTO]? = nil) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(newsID)

        if let ranges {
            let payload = JSONAPIToManyRelationshipWriteDTO(data: ranges)
            _ = try await apiClient.performRequest(
                path: "/v1/news/\(escapedID)/relationships/ranges",
                method: .delete,
                body: payload
            )
            return
        }

        _ = try await apiClient.performRequest(path: "/v1/news/\(escapedID)/relationships/ranges", method: .delete)
    }

    private func createNews(path: String, attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<NewsWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "news",
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(path: path, method: .post, body: payload)
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "news", "item"])
    }

    private func writeNewsRanges(newsID: String, method: StudIPHTTPMethod, ranges: [JSONAPIResourceIdentifierDTO]) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(newsID)
        let payload = JSONAPIToManyRelationshipWriteDTO(data: ranges)

        _ = try await apiClient.performRequest(
            path: "/v1/news/\(escapedID)/relationships/ranges",
            method: method,
            body: payload
        )
    }
}
