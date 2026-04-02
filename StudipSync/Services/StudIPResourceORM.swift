import Foundation

protocol StudIPResourceDescriptor {
    associatedtype Model: Decodable
    static var collectionPath: String { get }
    static var fallbackCollectionKeys: [String] { get }
}

struct StudIPQuery<Resource: StudIPResourceDescriptor> {
    private(set) var id: String?
    private(set) var filters: [String: String] = [:]
    private(set) var offset: Int?
    private(set) var limit: Int?

    init() {}

    func byID(_ id: String) -> Self {
        var copy = self
        copy.id = id
        return copy
    }

    func whereFilter(_ key: String, equals value: String?) -> Self {
        guard let value, !value.isEmpty else {
            return self
        }

        var copy = self
        copy.filters[key] = value
        return copy
    }

    func paginate(offset: Int? = nil, limit: Int? = nil) -> Self {
        var copy = self
        copy.offset = offset
        copy.limit = limit
        return copy
    }

    var path: String {
        guard let id else {
            return Resource.collectionPath
        }

        let trimmedID = id.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedID.isEmpty else {
            return Resource.collectionPath
        }

        return "\(Resource.collectionPath)/\(trimmedID)"
    }

    var queryItems: [URLQueryItem] {
        var items = filters
            .sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: "filter[\($0.key)]", value: $0.value) }

        if let offset {
            items.append(URLQueryItem(name: "page[offset]", value: String(offset)))
        }

        if let limit {
            items.append(URLQueryItem(name: "page[limit]", value: String(limit)))
        }

        return items
    }
}

enum SemesterResource: StudIPResourceDescriptor {
    typealias Model = SemesterDTO
    static let collectionPath = "/v1/semesters"
    static let fallbackCollectionKeys = ["semesters", "data", "collection", "items"]
}

enum CourseResource: StudIPResourceDescriptor {
    typealias Model = CourseDTO
    static let collectionPath = "/v1/courses"
    static let fallbackCollectionKeys = ["courses", "data", "collection", "items"]
}
