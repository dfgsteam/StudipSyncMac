import Foundation

enum StudIPJSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: StudIPJSONValue])
    case array([StudIPJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([StudIPJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: StudIPJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct StudIPGenericResourceDTO: Decodable, Hashable, Identifiable {
    let id: String
    let type: String
    let attributes: [String: StudIPJSONValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case attributes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing generic resource id")
            )
        }

        id = canonicalStudIPID(rawID)
        type = container.decodeNonEmptyString(forKey: .type) ?? "unknown"
        attributes = try? container.decodeIfPresent([String: StudIPJSONValue].self, forKey: .attributes)
    }
}

struct JSONAPIResourceIdentifierDTO: Codable, Hashable {
    let type: String
    let id: String

    init(type: String, id: String) {
        self.type = type
        self.id = canonicalStudIPID(id)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.decodeNonEmptyString(forKey: .type) ?? "unknown"

        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing relationship resource id")
            )
        }
        id = canonicalStudIPID(rawID)
    }
}

struct JSONAPIRelationshipIdentifiersDocumentDTO: Decodable {
    let identifiers: [JSONAPIResourceIdentifierDTO]

    enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let many = try? container.decode([JSONAPIResourceIdentifierDTO].self, forKey: .data) {
            identifiers = many
            return
        }

        if let one = try? container.decode(JSONAPIResourceIdentifierDTO.self, forKey: .data) {
            identifiers = [one]
            return
        }

        identifiers = []
    }
}

struct JSONAPIToOneRelationshipWriteDTO: Codable {
    let data: JSONAPIResourceIdentifierDTO?
}

struct JSONAPIToManyRelationshipWriteDTO: Codable {
    let data: [JSONAPIResourceIdentifierDTO]
}

struct JSONAPIWriteDocument<Attributes: Encodable, Relationships: Encodable>: Encodable {
    let data: JSONAPIWriteData<Attributes, Relationships>
}

struct JSONAPIWriteData<Attributes: Encodable, Relationships: Encodable>: Encodable {
    let type: String
    let id: String?
    let attributes: Attributes?
    let relationships: Relationships?

    init(type: String, id: String? = nil, attributes: Attributes? = nil, relationships: Relationships? = nil) {
        self.type = type
        self.id = id.map(canonicalStudIPID)
        self.attributes = attributes
        self.relationships = relationships
    }
}

struct JSONAPIEmptyDTO: Codable {}

struct TermsOfUseDTO: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let details: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case name
        case details = "description"
        case icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing terms-of-use id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)

        id = canonicalStudIPID(rawID)
        name = attributes?.decodeNonEmptyString(forKey: .name)
        details = attributes?.decodeNonEmptyString(forKey: .details)
        icon = attributes?.decodeNonEmptyString(forKey: .icon)
    }
}

struct FolderDTO: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let details: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case name
        case details = "description"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing folder id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        name = attributes?.decodeNonEmptyString(forKey: .name)
        details = attributes?.decodeNonEmptyString(forKey: .details)
    }
}

struct EventDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let details: String?
    let start: String?
    let end: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case details = "description"
        case start
        case end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing event id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        title = attributes?.decodeNonEmptyString(forKey: .title)
        details = attributes?.decodeNonEmptyString(forKey: .details)
        start = attributes?.decodeNonEmptyString(forKey: .start)
        end = attributes?.decodeNonEmptyString(forKey: .end)
    }
}

struct ScheduleEntryDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let start: String?
    let end: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case start
        case end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing schedule-entry id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        title = attributes?.decodeNonEmptyString(forKey: .title)
        start = attributes?.decodeNonEmptyString(forKey: .start)
        end = attributes?.decodeNonEmptyString(forKey: .end)
    }
}

struct SeminarCycleDateDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let start: String?
    let end: String?
    let weekday: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case start
        case end
        case weekday
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing seminar-cycle-date id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        title = attributes?.decodeNonEmptyString(forKey: .title)
        start = attributes?.decodeNonEmptyString(forKey: .start)
        end = attributes?.decodeNonEmptyString(forKey: .end)
        weekday = attributes?.decodeIntLossy(forKey: .weekday)
    }
}

struct NewsDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let content: String?
    let commentsAllowed: Bool?
    let mkdate: String?
    let chdate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case content
        case commentsAllowed = "comments-allowed"
        case mkdate
        case chdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing news id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        title = attributes?.decodeNonEmptyString(forKey: .title)
        content = attributes?.decodeNonEmptyString(forKey: .content)
        commentsAllowed = attributes?.decodeBoolLossy(forKey: .commentsAllowed)
        mkdate = attributes?.decodeNonEmptyString(forKey: .mkdate)
        chdate = attributes?.decodeNonEmptyString(forKey: .chdate)
    }
}

struct NewsCommentDTO: Decodable, Hashable, Identifiable {
    let id: String
    let content: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing comment id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        content = attributes?.decodeNonEmptyString(forKey: .content)
    }
}

struct BlubberPostingDTO: Decodable, Hashable, Identifiable {
    let id: String
    let content: String?
    let contentHTML: String?
    let contextType: String?
    let mkdate: String?
    let chdate: String?
    let discussionTime: String?
    let authorID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
        case relationships
    }

    enum AttributesCodingKeys: String, CodingKey {
        case content
        case contentHTML = "content-html"
        case contextType = "context-type"
        case mkdate
        case chdate
        case discussionTime = "discussion-time"
    }

    enum RelationshipsCodingKeys: String, CodingKey {
        case author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing blubber-posting id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        let relationships = try? container.nestedContainer(keyedBy: RelationshipsCodingKeys.self, forKey: .relationships)

        id = canonicalStudIPID(rawID)
        content = attributes?.decodeNonEmptyString(forKey: .content)
        contentHTML = attributes?.decodeNonEmptyString(forKey: .contentHTML)
        contextType = attributes?.decodeNonEmptyString(forKey: .contextType)
        mkdate = attributes?.decodeNonEmptyString(forKey: .mkdate)
        chdate = attributes?.decodeNonEmptyString(forKey: .chdate)
        discussionTime = attributes?.decodeNonEmptyString(forKey: .discussionTime)
        authorID = (try? relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .author)?.data?.id).map(canonicalStudIPID)
    }
}

struct BlubberStreamDTO: Decodable, Hashable, Identifiable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing blubber-stream id"))
        }
        id = canonicalStudIPID(rawID)
    }
}

struct ForumCategoryDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing forum-category id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        title = attributes?.decodeNonEmptyString(forKey: .title)
        position = attributes?.decodeIntLossy(forKey: .position)
    }
}

struct ForumEntryDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let content: String?
    let area: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case content
        case area
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing forum-entry id"))
        }

        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        id = canonicalStudIPID(rawID)
        title = attributes?.decodeNonEmptyString(forKey: .title)
        content = attributes?.decodeNonEmptyString(forKey: .content)
        area = attributes?.decodeIntLossy(forKey: .area)
    }
}

struct InstituteMembershipDTO: Decodable, Hashable, Identifiable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.decodeStringLossy(forKey: .id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing institute-membership id"))
        }
        id = canonicalStudIPID(rawID)
    }
}

struct FileRefPatchAttributesDTO: Encodable {
    let name: String?
    let description: String?
}

struct FolderPatchAttributesDTO: Encodable {
    let name: String?
    let description: String?
}

struct NewsWriteAttributesDTO: Encodable {
    let title: String?
    let content: String?
}

struct CommentWriteAttributesDTO: Encodable {
    let content: String
}

struct BlubberPostingWriteAttributesDTO: Encodable {
    let content: String?
    let contextType: String?

    enum CodingKeys: String, CodingKey {
        case content
        case contextType = "context-type"
    }
}

struct BlubberPostingContextRelationshipsDTO: Encodable {
    let context: JSONAPIToOneRelationshipWriteDTO
}

struct ForumCategoryWriteAttributesDTO: Encodable {
    let title: String?
    let position: Int?
}

struct ForumEntryWriteAttributesDTO: Encodable {
    let title: String?
    let content: String?
    let area: Int?
}
