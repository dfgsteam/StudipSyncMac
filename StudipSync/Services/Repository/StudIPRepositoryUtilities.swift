import Foundation

enum StudIPContainerScope {
    case course(String)
    case institute(String)
    case user(String)

    var entitySegment: String {
        switch self {
        case .course:
            return "courses"
        case .institute:
            return "institutes"
        case .user:
            return "users"
        }
    }

    var rawID: String {
        switch self {
        case .course(let id), .institute(let id), .user(let id):
            return id
        }
    }

    var pathID: String {
        let normalized = canonicalStudIPID(rawID)
        return normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalized
    }
}

struct StudIPRepositoryUtilities {
    static func escapedPathID(_ raw: String) -> String {
        let normalized = canonicalStudIPID(raw)
        return normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalized
    }

    static func pageQueryItems(offset: Int?, limit: Int?) -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let offset {
            items.append(URLQueryItem(name: "page[offset]", value: String(offset)))
        }
        if let limit {
            items.append(URLQueryItem(name: "page[limit]", value: String(limit)))
        }

        return items
    }

    static func makeScopedPath(scope: StudIPContainerScope, suffix: String) -> String {
        let trimmedSuffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/v1/\(scope.entitySegment)/\(scope.pathID)/\(trimmedSuffix)"
    }
}
