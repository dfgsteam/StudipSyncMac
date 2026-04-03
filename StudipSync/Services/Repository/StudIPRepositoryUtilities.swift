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
    static let allowedCourseSearchFieldValues: Set<String> = [
        "all",
        "title_lecturer_number",
        "title",
        "sub_title",
        "lecturer",
        "number",
        "comment",
        "scope"
    ]

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

    static func normalizeCourseSearchFieldsFilter(_ fields: String?) -> String? {
        guard let fields else { return nil }
        let trimmed = fields.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        if allowedCourseSearchFieldValues.contains(normalized) {
            return normalized
        }

        let csvTokens = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !csvTokens.isEmpty {
            let tokenSet = Set(csvTokens)
            if tokenSet == Set(["title", "lecturer", "number"]) {
                return "title_lecturer_number"
            }
            if tokenSet.count == 1, let single = tokenSet.first, allowedCourseSearchFieldValues.contains(single) {
                return single
            }
        }

        // Unknown token: omit fields filter to avoid server-side 400 errors.
        return nil
    }

    static func localCourseSearchFieldTokens(from normalizedFields: String?) -> [String] {
        guard let normalizedFields else {
            return ["title", "lecturer", "number", "id", "subtitle", "description", "location"]
        }

        switch normalizedFields {
        case "title_lecturer_number":
            return ["title", "lecturer", "number"]
        case "sub_title":
            return ["subtitle"]
        case "all":
            return ["title", "lecturer", "number", "id", "subtitle", "description", "location", "comment", "scope"]
        default:
            let tokens = normalizedFields
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            return tokens.isEmpty ? ["title", "lecturer", "number", "id", "subtitle", "description", "location"] : tokens
        }
    }
}
