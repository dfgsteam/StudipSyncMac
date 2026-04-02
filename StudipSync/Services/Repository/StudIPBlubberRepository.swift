import Foundation

struct BlubberPostingListQuery {
    var courseID: String?
    var userID: String?
    var include: String?
    var offset: Int?
    var limit: Int?

    init(courseID: String? = nil, userID: String? = nil, include: String? = nil, offset: Int? = nil, limit: Int? = nil) {
        self.courseID = courseID
        self.userID = userID
        self.include = include
        self.offset = offset
        self.limit = limit
    }
}

actor StudIPBlubberRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func fetchPostings(query: BlubberPostingListQuery = .init()) async throws -> [BlubberPostingDTO] {
        var queryItems: [URLQueryItem] = []

        if let courseID = query.courseID {
            queryItems.append(URLQueryItem(name: "filter[course]", value: canonicalStudIPID(courseID)))
        }
        if let userID = query.userID {
            queryItems.append(URLQueryItem(name: "filter[user]", value: canonicalStudIPID(userID)))
        }
        if let include = query.include, !include.isEmpty {
            queryItems.append(URLQueryItem(name: "include", value: include))
        }

        queryItems.append(contentsOf: StudIPRepositoryUtilities.pageQueryItems(offset: query.offset, limit: query.limit))

        let data = try await apiClient.performRequest(path: "/v1/blubber-postings", queryItems: queryItems)
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "blubber-postings", "collection", "items"])
    }

    func fetchPosting(id: String) async throws -> BlubberPostingDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/blubber-postings/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "blubber-postings", "item"])
    }

    func createPosting(
        attributes: BlubberPostingWriteAttributesDTO,
        context: JSONAPIResourceIdentifierDTO? = nil
    ) async throws -> BlubberPostingDTO {
        let relationships = context.map { BlubberPostingContextRelationshipsDTO(context: JSONAPIToOneRelationshipWriteDTO(data: $0)) }
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<BlubberPostingWriteAttributesDTO, BlubberPostingContextRelationshipsDTO>(
                type: "blubber-postings",
                attributes: attributes,
                relationships: relationships
            )
        )

        let data = try await apiClient.performRequest(path: "/v1/blubber-postings", method: .post, body: payload)
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "blubber-postings", "item"])
    }

    func updatePosting(id: String, attributes: BlubberPostingWriteAttributesDTO) async throws -> BlubberPostingDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<BlubberPostingWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "blubber-postings",
                id: id,
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/blubber-postings/\(escapedID)",
            method: .patch,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "blubber-postings", "item"])
    }

    func deletePosting(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/blubber-postings/\(escapedID)", method: .delete)
    }

    func fetchPostingComments(postingID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [BlubberPostingDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(postingID)
        let data = try await apiClient.performRequest(
            path: "/v1/blubber-postings/\(escapedID)/comments",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "blubber-postings", "comments", "collection", "items"])
    }

    func createPostingComment(postingID: String, content: String) async throws -> BlubberPostingDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(postingID)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<BlubberPostingWriteAttributesDTO, JSONAPIEmptyDTO>(
                type: "blubber-postings",
                attributes: BlubberPostingWriteAttributesDTO(content: content, contextType: nil),
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/blubber-postings/\(escapedID)/comments",
            method: .post,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "blubber-postings", "comments", "item"])
    }

    func fetchPostingAuthorRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await fetchRelationship(path: "/v1/blubber-postings/\(StudIPRepositoryUtilities.escapedPathID(postingID))/relationships/author")
    }

    func fetchPostingCommentsRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await fetchRelationship(path: "/v1/blubber-postings/\(StudIPRepositoryUtilities.escapedPathID(postingID))/relationships/comments")
    }

    func fetchPostingContextRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await fetchRelationship(path: "/v1/blubber-postings/\(StudIPRepositoryUtilities.escapedPathID(postingID))/relationships/context")
    }

    func fetchPostingMentions(postingID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [StudIPGenericResourceDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(postingID)
        let data = try await apiClient.performRequest(
            path: "/v1/blubber-postings/\(escapedID)/mentions",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "mentions", "users", "collection", "items"])
    }

    func fetchPostingMentionsRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await fetchRelationship(path: "/v1/blubber-postings/\(StudIPRepositoryUtilities.escapedPathID(postingID))/relationships/mentions")
    }

    func fetchPostingResharersRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await fetchRelationship(path: "/v1/blubber-postings/\(StudIPRepositoryUtilities.escapedPathID(postingID))/relationships/resharers")
    }

    func fetchStream(id: String) async throws -> BlubberStreamDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/blubber-streams/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "blubber-streams", "item"])
    }

    private func fetchRelationship(path: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        let data = try await apiClient.performRequest(path: path)

        if let wrapped = try? JSONDecoder().decode(JSONAPIRelationshipIdentifiersDocumentDTO.self, from: data) {
            return wrapped.identifiers
        }

        let genericResources: [StudIPGenericResourceDTO] = try responseDecoder.parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "collection", "items"]
        )

        return genericResources.map { JSONAPIResourceIdentifierDTO(type: $0.type, id: $0.id) }
    }
}
