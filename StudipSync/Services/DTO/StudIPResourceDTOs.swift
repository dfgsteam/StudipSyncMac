import Foundation

struct SemesterDTO: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let token: String?
    let begin: Date?
    let end: Date?
    let startOfLectures: Date?
    let endOfLectures: Date?
    let visible: Bool?
    let isCurrent: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case token
        case begin
        case end
        case startOfLectures = "start-of-lectures"
        case endOfLectures = "end-of-lectures"
        case visible
        case isCurrent = "is-current"
        case attributes
        case links
        case name
        case start
        case semesterID = "semester_id"
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case name
        case token
        case begin
        case end
        case start
        case startOfLectures = "start-of-lectures"
        case endOfLectures = "end-of-lectures"
        case visible
        case isCurrent = "is-current"
        case semesterID = "semester_id"
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(
        id: String,
        title: String,
        token: String? = nil,
        begin: Date? = nil,
        end: Date? = nil,
        startOfLectures: Date? = nil,
        endOfLectures: Date? = nil,
        visible: Bool? = nil,
        isCurrent: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.token = token
        self.begin = begin
        self.end = end
        self.startOfLectures = startOfLectures
        self.endOfLectures = endOfLectures
        self.visible = visible
        self.isCurrent = isCurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedAttributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)

        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)
        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id)
            ?? nestedAttributes?.decodeStringLossy(forKey: .semesterID)
            ?? container.decodeStringLossy(forKey: .semesterID)
            ?? idFromLinks

        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing semester id")
            )
        }
        id = canonicalStudIPID(decodedID)

        if let attributes = nestedAttributes {
            title = attributes.decodeNonEmptyString(forKey: .title)
                ?? attributes.decodeNonEmptyString(forKey: .name)
                ?? "Semester \(id)"
            token = attributes.decodeNonEmptyString(forKey: .token)
            begin = try SemesterDTO.decodeDate(from: attributes, primary: .begin, fallback: .start)
            end = try SemesterDTO.decodeDate(from: attributes, primary: .end, fallback: nil)
            startOfLectures = try SemesterDTO.decodeDate(from: attributes, primary: .startOfLectures, fallback: nil)
            endOfLectures = try SemesterDTO.decodeDate(from: attributes, primary: .endOfLectures, fallback: nil)
            visible = attributes.decodeBoolLossy(forKey: .visible)
            isCurrent = attributes.decodeBoolLossy(forKey: .isCurrent)
            return
        }

        title = container.decodeNonEmptyString(forKey: .title)
            ?? container.decodeNonEmptyString(forKey: .name)
            ?? "Semester \(id)"
        token = container.decodeNonEmptyString(forKey: .token)
        begin = try SemesterDTO.decodeDate(from: container, primary: .begin, fallback: .start)
        end = try SemesterDTO.decodeDate(from: container, primary: .end, fallback: nil)
        startOfLectures = try SemesterDTO.decodeDate(from: container, primary: .startOfLectures, fallback: nil)
        endOfLectures = try SemesterDTO.decodeDate(from: container, primary: .endOfLectures, fallback: nil)
        visible = container.decodeBoolLossy(forKey: .visible)
        isCurrent = container.decodeBoolLossy(forKey: .isCurrent)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(token, forKey: .token)
        try container.encodeIfPresent(begin?.timeIntervalSince1970, forKey: .begin)
        try container.encodeIfPresent(end?.timeIntervalSince1970, forKey: .end)
        try container.encodeIfPresent(startOfLectures?.timeIntervalSince1970, forKey: .startOfLectures)
        try container.encodeIfPresent(endOfLectures?.timeIntervalSince1970, forKey: .endOfLectures)
        try container.encodeIfPresent(visible, forKey: .visible)
        try container.encodeIfPresent(isCurrent, forKey: .isCurrent)
    }

    private static func decodeDate<K: CodingKey>(from container: KeyedDecodingContainer<K>, primary: K, fallback: K?) throws -> Date? {
        if let date = decodeDateValue(from: container, forKey: primary) {
            return date
        }

        if let fallback {
            return decodeDateValue(from: container, forKey: fallback)
        }

        return nil
    }

    private static func decodeDateValue<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) -> Date? {
        if let seconds = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let seconds = TimeInterval(trimmed) {
                return Date(timeIntervalSince1970: seconds)
            }

            if let date = iso8601WithFractionalSeconds.date(from: trimmed) ?? iso8601.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct CourseDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let courseNumber: String?
    let courseType: Int?
    let courseTypeID: String?
    let description: String?
    let location: String?
    let miscellaneous: String?
    let instituteID: String?
    let semClassID: String?
    let semTypeID: String?
    let semesterID: String?
    let startSemesterRef: String?
    let endSemesterRef: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case courseNumber = "course-number"
        case courseType = "course-type"
        case description
        case location
        case miscellaneous
        case attributes
        case links
        case name
        case courseID = "course_id"
        case semesterID = "semester_id"
        case startSemester = "start_semester"
        case endSemester = "end_semester"
        case relationships
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case name
        case subtitle
        case courseNumber = "course-number"
        case courseType = "course-type"
        case description
        case location
        case miscellaneous
        case courseID = "course_id"
        case semesterID = "semester_id"
        case startSemester = "start_semester"
        case endSemester = "end_semester"
    }

    enum RelationshipsCodingKeys: String, CodingKey {
        case semester
        case institute
        case startSemester = "start-semester"
        case endSemester = "end-semester"
        case semClass = "sem-class"
        case semType = "sem-type"
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedAttributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)

        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)
        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id)
            ?? nestedAttributes?.decodeStringLossy(forKey: .courseID)
            ?? container.decodeStringLossy(forKey: .courseID)
            ?? idFromLinks

        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing course id")
            )
        }
        id = canonicalStudIPID(decodedID)

        if let attributes = nestedAttributes {
            title = attributes.decodeNonEmptyString(forKey: .title)
                ?? attributes.decodeNonEmptyString(forKey: .name)
                ?? "Course \(id)"
            subtitle = attributes.decodeNonEmptyString(forKey: .subtitle)
            courseNumber = attributes.decodeNonEmptyString(forKey: .courseNumber)
            courseType = attributes.decodeIntLossy(forKey: .courseType)
            description = attributes.decodeNonEmptyString(forKey: .description)
            location = attributes.decodeNonEmptyString(forKey: .location)
            miscellaneous = attributes.decodeNonEmptyString(forKey: .miscellaneous)
        } else {
            title = container.decodeNonEmptyString(forKey: .title)
                ?? container.decodeNonEmptyString(forKey: .name)
                ?? "Course \(id)"
            subtitle = container.decodeNonEmptyString(forKey: .subtitle)
            courseNumber = container.decodeNonEmptyString(forKey: .courseNumber)
            courseType = container.decodeIntLossy(forKey: .courseType)
            description = container.decodeNonEmptyString(forKey: .description)
            location = container.decodeNonEmptyString(forKey: .location)
            miscellaneous = container.decodeNonEmptyString(forKey: .miscellaneous)
        }

        let topSemester = container.decodeStringLossy(forKey: .semesterID)
        let attrSemester = nestedAttributes?.decodeStringLossy(forKey: .semesterID)

        let topStart = container.decodeStringLossy(forKey: .startSemester)
        let attrStart = nestedAttributes?.decodeStringLossy(forKey: .startSemester)

        let topEnd = container.decodeStringLossy(forKey: .endSemester)
        let attrEnd = nestedAttributes?.decodeStringLossy(forKey: .endSemester)

        let relationships = try? container.nestedContainer(keyedBy: RelationshipsCodingKeys.self, forKey: .relationships)
        let relSemester = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .semester)?.data?.id
        let relInstitute = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .institute)?.data?.id
        let relStart = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .startSemester)?.data?.id
        let relEnd = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .endSemester)?.data?.id
        let relSemClass = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .semClass)?.data?.id
        let relSemType = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .semType)?.data?.id

        semesterID = (topSemester ?? attrSemester ?? relSemester).map(canonicalStudIPID)
        startSemesterRef = (topStart ?? attrStart ?? relStart).map(canonicalStudIPID)
        endSemesterRef = (topEnd ?? attrEnd ?? relEnd).map(canonicalStudIPID)
        instituteID = relInstitute.map(canonicalStudIPID)
        semClassID = relSemClass.map(canonicalStudIPID)
        semTypeID = relSemType.map(canonicalStudIPID)
        courseTypeID = semTypeID ?? semClassID
    }

    nonisolated func matches(semesterID: String) -> Bool {
        if self.semesterID == semesterID {
            return true
        }
        if let startSemesterRef, startSemesterRef.contains(semesterID) {
            return true
        }
        if let endSemesterRef, endSemesterRef.contains(semesterID) {
            return true
        }
        return false
    }
}

struct CourseChatThreadDTO: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let contextType: String?
    let contextInfoHTML: String?
    let content: String?
    let isCommentable: Bool?
    let isReadable: Bool?
    let isWritable: Bool?
    let isFollowed: Bool?
    let latestActivity: String?
    let visitedAt: String?
    let mkdate: String?
    let chdate: String?
    let authorID: String?
    let unseenComments: Int?
    let avatarURLPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
        case relationships
        case meta
        case links
    }

    enum AttributesCodingKeys: String, CodingKey {
        case name
        case contextType = "context-type"
        case contextInfoHTML = "context-info"
        case content
        case isCommentable = "is-commentable"
        case isReadable = "is-readable"
        case isWritable = "is-writable"
        case isFollowed = "is-followed"
        case latestActivity = "latest-activity"
        case visitedAt = "visited-at"
        case mkdate
        case chdate
    }

    enum RelationshipsCodingKeys: String, CodingKey {
        case author
        case comments
    }

    enum CommentsCodingKeys: String, CodingKey {
        case links
    }

    enum CommentsLinksCodingKeys: String, CodingKey {
        case related
    }

    enum RelatedCodingKeys: String, CodingKey {
        case meta
    }

    enum RelatedMetaCodingKeys: String, CodingKey {
        case unseenComments = "unseen-comments"
    }

    enum MetaCodingKeys: String, CodingKey {
        case avatar
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        let relationships = try? container.nestedContainer(keyedBy: RelationshipsCodingKeys.self, forKey: .relationships)
        let topMeta = try? container.nestedContainer(keyedBy: MetaCodingKeys.self, forKey: .meta)
        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)

        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id) ?? idFromLinks
        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing blubber-thread id")
            )
        }
        id = canonicalStudIPID(decodedID)

        name = attributes?.decodeNonEmptyString(forKey: .name)
        contextType = attributes?.decodeNonEmptyString(forKey: .contextType)
        contextInfoHTML = attributes?.decodeNonEmptyString(forKey: .contextInfoHTML)
        content = attributes?.decodeNonEmptyString(forKey: .content)
        isCommentable = attributes?.decodeBoolLossy(forKey: .isCommentable)
        isReadable = attributes?.decodeBoolLossy(forKey: .isReadable)
        isWritable = attributes?.decodeBoolLossy(forKey: .isWritable)
        isFollowed = attributes?.decodeBoolLossy(forKey: .isFollowed)
        latestActivity = attributes?.decodeNonEmptyString(forKey: .latestActivity)
        visitedAt = attributes?.decodeNonEmptyString(forKey: .visitedAt)
        mkdate = attributes?.decodeNonEmptyString(forKey: .mkdate)
        chdate = attributes?.decodeNonEmptyString(forKey: .chdate)

        if let relationships {
            authorID = try relationships
                .decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .author)?
                .data?.id
        } else {
            authorID = nil
        }

        if let relationships,
           let comments = try? relationships.nestedContainer(keyedBy: CommentsCodingKeys.self, forKey: .comments),
           let commentsLinks = try? comments.nestedContainer(keyedBy: CommentsLinksCodingKeys.self, forKey: .links),
           let related = try? commentsLinks.nestedContainer(keyedBy: RelatedCodingKeys.self, forKey: .related),
           let relatedMeta = try? related.nestedContainer(keyedBy: RelatedMetaCodingKeys.self, forKey: .meta) {
            unseenComments = relatedMeta.decodeIntLossy(forKey: .unseenComments)
        } else {
            unseenComments = nil
        }

        avatarURLPath = topMeta?.decodeNonEmptyString(forKey: .avatar)
    }
}

struct CourseWikiPageDTO: Decodable, Hashable, Identifiable {
    let id: String
    let keyword: String?
    let content: String?
    let chdate: String?
    let version: Int?
    let authorID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
        case relationships
        case links
    }

    enum AttributesCodingKeys: String, CodingKey {
        case keyword
        case content
        case chdate
        case version
    }

    enum RelationshipsCodingKeys: String, CodingKey {
        case author
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        let relationships = try? container.nestedContainer(keyedBy: RelationshipsCodingKeys.self, forKey: .relationships)
        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)

        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id) ?? idFromLinks
        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing wiki-page id")
            )
        }
        id = canonicalStudIPID(decodedID)

        keyword = attributes?.decodeNonEmptyString(forKey: .keyword)
        content = attributes?.decodeNonEmptyString(forKey: .content)
        chdate = attributes?.decodeNonEmptyString(forKey: .chdate)
        version = attributes?.decodeIntLossy(forKey: .version)

        if let relationships {
            authorID = try relationships
                .decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .author)?
                .data?.id
        } else {
            authorID = nil
        }
    }
}

struct CourseFileRefDTO: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let description: String?
    let mkdate: String?
    let chdate: String?
    let downloads: Int?
    let fileSize: Int?
    let mimeType: String?
    let isReadable: Bool?
    let isDownloadable: Bool?
    let ownerName: String?
    let downloadURLPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case attributes
        case relationships
        case meta
        case links
    }

    enum AttributesCodingKeys: String, CodingKey {
        case name
        case description
        case mkdate
        case chdate
        case downloads
        case fileSize = "filesize"
        case mimeType = "mime-type"
        case isReadable = "is-readable"
        case isDownloadable = "is-downloadable"
    }

    enum RelationshipsCodingKeys: String, CodingKey {
        case owner
    }

    enum OwnerCodingKeys: String, CodingKey {
        case meta
    }

    enum OwnerMetaCodingKeys: String, CodingKey {
        case name
    }

    enum MetaCodingKeys: String, CodingKey {
        case downloadURL = "download-url"
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        let relationships = try? container.nestedContainer(keyedBy: RelationshipsCodingKeys.self, forKey: .relationships)
        let topMeta = try? container.nestedContainer(keyedBy: MetaCodingKeys.self, forKey: .meta)
        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)

        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id) ?? idFromLinks
        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing file-ref id")
            )
        }
        id = canonicalStudIPID(decodedID)

        name = attributes?.decodeNonEmptyString(forKey: .name)
        description = attributes?.decodeNonEmptyString(forKey: .description)
        mkdate = attributes?.decodeNonEmptyString(forKey: .mkdate)
        chdate = attributes?.decodeNonEmptyString(forKey: .chdate)
        downloads = attributes?.decodeIntLossy(forKey: .downloads)
        fileSize = attributes?.decodeIntLossy(forKey: .fileSize)
        mimeType = attributes?.decodeNonEmptyString(forKey: .mimeType)
        isReadable = attributes?.decodeBoolLossy(forKey: .isReadable)
        isDownloadable = attributes?.decodeBoolLossy(forKey: .isDownloadable)

        if let relationships,
           let owner = try? relationships.nestedContainer(keyedBy: OwnerCodingKeys.self, forKey: .owner),
           let ownerMeta = try? owner.nestedContainer(keyedBy: OwnerMetaCodingKeys.self, forKey: .meta) {
            ownerName = ownerMeta.decodeNonEmptyString(forKey: .name)
        } else {
            ownerName = nil
        }

        downloadURLPath = topMeta?.decodeNonEmptyString(forKey: .downloadURL)
    }
}

struct CourseMembershipDTO: Decodable, Hashable, Identifiable {
    let id: String
    let userID: String
    let permission: String?
    let position: Int?
    let group: Int?
    let label: String?
    let mkdate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case membershipID = "membership_id"
        case userID = "user_id"
        case attributes
        case relationships
        case links
    }

    enum AttributesCodingKeys: String, CodingKey {
        case permission
        case position
        case group
        case label
        case mkdate
        case userID = "user_id"
    }

    enum RelationshipsCodingKeys: String, CodingKey {
        case user
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        let relationships = try? container.nestedContainer(keyedBy: RelationshipsCodingKeys.self, forKey: .relationships)
        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)

        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id)
            ?? container.decodeStringLossy(forKey: .membershipID)
            ?? idFromLinks

        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing membership id")
            )
        }
        id = canonicalStudIPID(decodedID)

        let relationshipUserID = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .user)?.data?.id
        let decodedUserID = relationshipUserID
            ?? container.decodeStringLossy(forKey: .userID)
            ?? attributes?.decodeStringLossy(forKey: .userID)

        guard let decodedUserID, !decodedUserID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing membership user id")
            )
        }
        userID = canonicalStudIPID(decodedUserID)

        permission = attributes?.decodeNonEmptyString(forKey: .permission)
        position = attributes?.decodeIntLossy(forKey: .position)
        group = attributes?.decodeIntLossy(forKey: .group)
        label = attributes?.decodeNonEmptyString(forKey: .label)
        mkdate = attributes?.decodeNonEmptyString(forKey: .mkdate)
    }
}

struct UserDTO: Decodable, Hashable, Identifiable {
    let id: String
    let username: String?
    let displayName: String?
    let fullName: String?
    let givenName: String?
    let familyName: String?
    let namePrefix: String?
    let nameSuffix: String?
    let permission: String?
    let email: String?
    let authPlugin: String?
    let locked: Bool?
    let lockComment: String?
    let visible: Bool?
    let matriculationNumber: String?
    let gender: String?
    let preferredLanguage: String?
    let mkdate: String?
    let chdate: String?
    let phone: String?
    let cellphone: String?
    let address: String?
    let homepage: String?
    let hobby: String?
    let cv: String?
    let publication: String?
    let focus: String?
    let motto: String?
    let avatarURL: String?
    let avatarSmallURL: String?
    let avatarMediumURL: String?
    let avatarNormalURL: String?
    let avatarOriginalURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case username
        case name
        case displayName
        case displayNameDashed = "display-name"
        case fullName
        case formattedName = "formatted-name"
        case givenName
        case familyName
        case givenNameDashed = "given-name"
        case familyNameDashed = "family-name"
        case namePrefix
        case nameSuffix
        case namePrefixDashed = "name-prefix"
        case nameSuffixDashed = "name-suffix"
        case permission
        case email
        case mail
        case authPlugin = "auth-plugin"
        case locked
        case lockComment = "lock-comment"
        case visible
        case matriculationNumber = "matriculation-number"
        case gender
        case preferredLanguage = "preferred-language"
        case mkdate
        case chdate
        case phone
        case telephone
        case cellphone
        case address
        case homepage
        case hobby
        case cv
        case publication
        case focus
        case motto
        case avatar
        case avatarSmall = "avatar-small"
        case avatarMedium = "avatar-medium"
        case avatarNormal = "avatar-normal"
        case avatarOriginal = "avatar-original"
        case picture
        case attributes
        case links
    }

    enum AttributesCodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case username
        case name
        case displayName
        case displayNameDashed = "display-name"
        case fullName
        case formattedName = "formatted-name"
        case givenName
        case familyName
        case givenNameDashed = "given-name"
        case familyNameDashed = "family-name"
        case namePrefix
        case nameSuffix
        case namePrefixDashed = "name-prefix"
        case nameSuffixDashed = "name-suffix"
        case permission
        case email
        case mail
        case authPlugin = "auth-plugin"
        case locked
        case lockComment = "lock-comment"
        case visible
        case matriculationNumber = "matriculation-number"
        case gender
        case preferredLanguage = "preferred-language"
        case mkdate
        case chdate
        case phone
        case telephone
        case cellphone
        case address
        case homepage
        case hobby
        case cv
        case publication
        case focus
        case motto
        case avatar
        case avatarSmall = "avatar-small"
        case avatarMedium = "avatar-medium"
        case avatarNormal = "avatar-normal"
        case avatarOriginal = "avatar-original"
        case picture
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)

        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id)
            ?? container.decodeStringLossy(forKey: .userID)
            ?? attributes?.decodeStringLossy(forKey: .id)
            ?? attributes?.decodeStringLossy(forKey: .userID)
            ?? idFromLinks

        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing user id")
            )
        }

        id = canonicalStudIPID(decodedID)

        username = container.decodeNonEmptyString(forKey: .username)
            ?? attributes?.decodeNonEmptyString(forKey: .username)

        let containerDisplayName = container.decodeNonEmptyString(forKey: .displayName)
            ?? container.decodeNonEmptyString(forKey: .displayNameDashed)
            ?? container.decodeNonEmptyString(forKey: .formattedName)
            ?? container.decodeNonEmptyString(forKey: .name)
        let attributesDisplayName = attributes?.decodeNonEmptyString(forKey: .displayName)
            ?? attributes?.decodeNonEmptyString(forKey: .displayNameDashed)
            ?? attributes?.decodeNonEmptyString(forKey: .formattedName)
            ?? attributes?.decodeNonEmptyString(forKey: .name)
        displayName = containerDisplayName ?? attributesDisplayName

        fullName = container.decodeNonEmptyString(forKey: .fullName)
            ?? container.decodeNonEmptyString(forKey: .name)
            ?? attributes?.decodeNonEmptyString(forKey: .fullName)
            ?? attributes?.decodeNonEmptyString(forKey: .name)

        givenName = container.decodeNonEmptyString(forKey: .givenName)
            ?? container.decodeNonEmptyString(forKey: .givenNameDashed)
            ?? attributes?.decodeNonEmptyString(forKey: .givenName)
            ?? attributes?.decodeNonEmptyString(forKey: .givenNameDashed)

        familyName = container.decodeNonEmptyString(forKey: .familyName)
            ?? container.decodeNonEmptyString(forKey: .familyNameDashed)
            ?? attributes?.decodeNonEmptyString(forKey: .familyName)
            ?? attributes?.decodeNonEmptyString(forKey: .familyNameDashed)

        namePrefix = container.decodeNonEmptyString(forKey: .namePrefix)
            ?? container.decodeNonEmptyString(forKey: .namePrefixDashed)
            ?? attributes?.decodeNonEmptyString(forKey: .namePrefix)
            ?? attributes?.decodeNonEmptyString(forKey: .namePrefixDashed)

        nameSuffix = container.decodeNonEmptyString(forKey: .nameSuffix)
            ?? container.decodeNonEmptyString(forKey: .nameSuffixDashed)
            ?? attributes?.decodeNonEmptyString(forKey: .nameSuffix)
            ?? attributes?.decodeNonEmptyString(forKey: .nameSuffixDashed)

        permission = container.decodeNonEmptyString(forKey: .permission)
            ?? attributes?.decodeNonEmptyString(forKey: .permission)

        email = container.decodeNonEmptyString(forKey: .email)
            ?? container.decodeNonEmptyString(forKey: .mail)
            ?? attributes?.decodeNonEmptyString(forKey: .email)
            ?? attributes?.decodeNonEmptyString(forKey: .mail)

        authPlugin = container.decodeNonEmptyString(forKey: .authPlugin)
            ?? attributes?.decodeNonEmptyString(forKey: .authPlugin)

        locked = container.decodeBoolLossy(forKey: .locked)
            ?? attributes?.decodeBoolLossy(forKey: .locked)

        lockComment = container.decodeNonEmptyString(forKey: .lockComment)
            ?? attributes?.decodeNonEmptyString(forKey: .lockComment)

        visible = container.decodeBoolLossy(forKey: .visible)
            ?? attributes?.decodeBoolLossy(forKey: .visible)

        matriculationNumber = container.decodeNonEmptyString(forKey: .matriculationNumber)
            ?? attributes?.decodeNonEmptyString(forKey: .matriculationNumber)

        gender = container.decodeNonEmptyString(forKey: .gender)
            ?? attributes?.decodeNonEmptyString(forKey: .gender)

        preferredLanguage = container.decodeNonEmptyString(forKey: .preferredLanguage)
            ?? attributes?.decodeNonEmptyString(forKey: .preferredLanguage)

        mkdate = container.decodeNonEmptyString(forKey: .mkdate)
            ?? attributes?.decodeNonEmptyString(forKey: .mkdate)

        chdate = container.decodeNonEmptyString(forKey: .chdate)
            ?? attributes?.decodeNonEmptyString(forKey: .chdate)

        phone = container.decodeNonEmptyString(forKey: .phone)
            ?? container.decodeNonEmptyString(forKey: .telephone)
            ?? attributes?.decodeNonEmptyString(forKey: .phone)
            ?? attributes?.decodeNonEmptyString(forKey: .telephone)

        cellphone = container.decodeNonEmptyString(forKey: .cellphone)
            ?? attributes?.decodeNonEmptyString(forKey: .cellphone)

        address = container.decodeNonEmptyString(forKey: .address)
            ?? attributes?.decodeNonEmptyString(forKey: .address)

        homepage = container.decodeNonEmptyString(forKey: .homepage)
            ?? attributes?.decodeNonEmptyString(forKey: .homepage)

        hobby = container.decodeNonEmptyString(forKey: .hobby)
            ?? attributes?.decodeNonEmptyString(forKey: .hobby)

        cv = container.decodeNonEmptyString(forKey: .cv)
            ?? attributes?.decodeNonEmptyString(forKey: .cv)

        publication = container.decodeNonEmptyString(forKey: .publication)
            ?? attributes?.decodeNonEmptyString(forKey: .publication)

        focus = container.decodeNonEmptyString(forKey: .focus)
            ?? attributes?.decodeNonEmptyString(forKey: .focus)

        motto = container.decodeNonEmptyString(forKey: .motto)
            ?? attributes?.decodeNonEmptyString(forKey: .motto)

        avatarURL = container.decodeNonEmptyString(forKey: .avatar)
            ?? container.decodeNonEmptyString(forKey: .picture)
            ?? attributes?.decodeNonEmptyString(forKey: .avatar)
            ?? attributes?.decodeNonEmptyString(forKey: .picture)
        avatarSmallURL = container.decodeNonEmptyString(forKey: .avatarSmall)
            ?? attributes?.decodeNonEmptyString(forKey: .avatarSmall)
        avatarMediumURL = container.decodeNonEmptyString(forKey: .avatarMedium)
            ?? attributes?.decodeNonEmptyString(forKey: .avatarMedium)
        avatarNormalURL = container.decodeNonEmptyString(forKey: .avatarNormal)
            ?? attributes?.decodeNonEmptyString(forKey: .avatarNormal)
        avatarOriginalURL = container.decodeNonEmptyString(forKey: .avatarOriginal)
            ?? attributes?.decodeNonEmptyString(forKey: .avatarOriginal)
    }

    var preferredDisplayName: String? {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if let fullName, !fullName.isEmpty {
            return fullName
        }

        let composedName = [namePrefix, givenName, familyName, nameSuffix]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !composedName.isEmpty {
            return composedName
        }

        return username
    }

    var preferredAvatarPath: String? {
        avatarNormalURL
            ?? avatarMediumURL
            ?? avatarSmallURL
            ?? avatarURL
            ?? avatarOriginalURL
    }
}

struct InstituteDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let name: String?
    let shortName: String?
    let description: String?
    let email: String?
    let phone: String?
    let address: String?
    let homepage: String?
    let mkdate: String?
    let chdate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case instituteID = "institute_id"
        case title
        case name
        case shortName = "short-name"
        case description
        case email
        case phone
        case address
        case homepage
        case mkdate
        case chdate
        case attributes
        case links
    }

    enum AttributesCodingKeys: String, CodingKey {
        case id
        case instituteID = "institute_id"
        case title
        case name
        case shortName = "short-name"
        case description
        case email
        case phone
        case address
        case homepage
        case mkdate
        case chdate
    }

    enum LinksCodingKeys: String, CodingKey {
        case selfLink = "self"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let attributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)
        let links = try? container.nestedContainer(keyedBy: LinksCodingKeys.self, forKey: .links)

        let idFromLinks = try links?.decodeIfPresent(String.self, forKey: .selfLink).map(canonicalStudIPID)
        let decodedID = container.decodeStringLossy(forKey: .id)
            ?? container.decodeStringLossy(forKey: .instituteID)
            ?? attributes?.decodeStringLossy(forKey: .id)
            ?? attributes?.decodeStringLossy(forKey: .instituteID)
            ?? idFromLinks

        guard let decodedID, !decodedID.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing institute id")
            )
        }

        id = canonicalStudIPID(decodedID)
        title = container.decodeNonEmptyString(forKey: .title)
            ?? attributes?.decodeNonEmptyString(forKey: .title)
        name = container.decodeNonEmptyString(forKey: .name)
            ?? attributes?.decodeNonEmptyString(forKey: .name)
        shortName = container.decodeNonEmptyString(forKey: .shortName)
            ?? attributes?.decodeNonEmptyString(forKey: .shortName)
        description = container.decodeNonEmptyString(forKey: .description)
            ?? attributes?.decodeNonEmptyString(forKey: .description)
        email = container.decodeNonEmptyString(forKey: .email)
            ?? attributes?.decodeNonEmptyString(forKey: .email)
        phone = container.decodeNonEmptyString(forKey: .phone)
            ?? attributes?.decodeNonEmptyString(forKey: .phone)
        address = container.decodeNonEmptyString(forKey: .address)
            ?? attributes?.decodeNonEmptyString(forKey: .address)
        homepage = container.decodeNonEmptyString(forKey: .homepage)
            ?? attributes?.decodeNonEmptyString(forKey: .homepage)
        mkdate = container.decodeNonEmptyString(forKey: .mkdate)
            ?? attributes?.decodeNonEmptyString(forKey: .mkdate)
        chdate = container.decodeNonEmptyString(forKey: .chdate)
            ?? attributes?.decodeNonEmptyString(forKey: .chdate)
    }

    var displayName: String {
        title ?? name ?? shortName ?? "Einrichtung \(id)"
    }
}

struct JSONAPIListResponse<Resource: Decodable>: Decodable {
    let data: [Resource]
}

struct JSONAPISingleResponse<Resource: Decodable>: Decodable {
    let data: Resource
}

struct JSONAPIRelationshipIdentifier: Decodable {
    struct Linkage: Decodable {
        let id: String

        enum CodingKeys: String, CodingKey {
            case id
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let decoded = container.decodeStringLossy(forKey: .id) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Missing relationship id")
                )
            }
            id = canonicalStudIPID(decoded)
        }
    }

    let data: Linkage?
}
extension KeyedDecodingContainer {
    func decodeNonEmptyString(forKey key: Key) -> String? {
        guard let value = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func decodeStringLossy(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeBoolLossy(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "y"].contains(normalized) {
                return true
            }
            if ["false", "0", "no", "n"].contains(normalized) {
                return false
            }
        }
        return nil
    }

    func decodeIntLossy(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

func canonicalStudIPID(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return raw
    }

    if let url = URL(string: trimmed),
       let scheme = url.scheme,
       !scheme.isEmpty {
        let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let last = pathComponents.last {
            return normalizedStudIPID(last)
        }
    }

    let withoutQuery = trimmed.split(separator: "?", maxSplits: 1).first.map(String.init) ?? trimmed
    let withoutFragment = withoutQuery.split(separator: "#", maxSplits: 1).first.map(String.init) ?? withoutQuery
    let components = withoutFragment.split(separator: "/").map(String.init).filter { !$0.isEmpty }

    if components.count >= 2 {
        let previous = components[components.count - 2].lowercased()
        if ["semester", "semesters", "course", "courses", "user", "users"].contains(previous) {
            return normalizedStudIPID(components[components.count - 1])
        }
    }

    if components.count > 1, let last = components.last {
        return normalizedStudIPID(last)
    }

    return normalizedStudIPID(withoutFragment)
}

func normalizedStudIPID(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let uuidLikePattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"

    if trimmed.range(of: uuidLikePattern, options: .regularExpression) != nil {
        return trimmed.replacingOccurrences(of: "-", with: "").lowercased()
    }

    return trimmed
}
