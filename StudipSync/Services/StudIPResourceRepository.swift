import Foundation

actor StudIPResourceRepository {
    enum SemesterDataSource: String {
        case cache
        case remote
    }

    enum RepositoryError: LocalizedError {
        case invalidPayloadPreview(String)

        var errorDescription: String? {
            switch self {
            case .invalidPayloadPreview(let preview):
                return "Unbekanntes Antwortformat. Preview: \(preview)"
            }
        }
    }

    struct SemesterLoadResult {
        let semesters: [SemesterDTO]
        let source: SemesterDataSource
    }

    private let apiClient: StudIPAPIClient
    private let settingsStore: SettingsStore
    private let metadataCache: MetadataCache

    init(apiClient: StudIPAPIClient, settingsStore: SettingsStore, metadataCache: MetadataCache) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.metadataCache = metadataCache
    }

    func loadSemestersStaleWhileRevalidate(onRefresh: (@MainActor ([SemesterDTO]) -> Void)? = nil) async throws -> SemesterLoadResult {
        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }

        if let cached = try await metadataCache.load(baseURL: baseURL), !cached.semesters.isEmpty {
            Task {
                await refreshSemesters(baseURL: baseURL, onRefresh: onRefresh)
            }
            return SemesterLoadResult(semesters: cached.semesters, source: .cache)
        }

        let remoteSemesters = try await fetchRemoteSemesters()
        try await metadataCache.save(semesters: remoteSemesters, baseURL: baseURL)
        return SemesterLoadResult(semesters: remoteSemesters, source: .remote)
    }

    func fetchCourses(for semesterID: String) async throws -> [CourseDTO] {
        let data = try await requestWithPathFallbacks([
            "/api.php/courses/semester/\(semesterID)",
            "/api/courses/semester/\(semesterID)",
            "/api.php/courses",
            "/api/courses"
        ], queryItems: [URLQueryItem(name: "filter[semester]", value: semesterID)])

        return try await parseCourses(from: data)
    }

    private func refreshSemesters(baseURL: URL, onRefresh: (@MainActor ([SemesterDTO]) -> Void)?) async {
        do {
            let remoteSemesters = try await fetchRemoteSemesters()
            try await metadataCache.save(semesters: remoteSemesters, baseURL: baseURL)
            if let onRefresh {
                await onRefresh(remoteSemesters)
            }
        } catch {
            AppLogger.error("Semester refresh failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemoteSemesters() async throws -> [SemesterDTO] {
        let data = try await requestWithPathFallbacks([
            "/api.php/semesters",
            "/api/semesters"
        ])

        return try await parseSemesters(from: data)
    }

    private func parseSemesters(from data: Data) async throws -> [SemesterDTO] {
        if let wrapped: JSONAPIListResponse<SemesterDTO> = await decodeIfPossible(data) {
            return wrapped.data
        }
        if let wrapped: SemestersEnvelope = await decodeIfPossible(data) {
            return wrapped.semesters
        }
        if let plain: [SemesterDTO] = await decodeIfPossible(data) {
            return plain
        }

        if let extracted = try extractArrayFromUnknownPayload(data, candidateKeys: ["semesters", "data", "collection", "items"]) {
            return try await decodeArrayElements(extracted, as: SemesterDTO.self)
        }

        throw RepositoryError.invalidPayloadPreview(previewString(from: data))
    }

    private func parseCourses(from data: Data) async throws -> [CourseDTO] {
        if let wrapped: JSONAPIListResponse<CourseDTO> = await decodeIfPossible(data) {
            return wrapped.data
        }
        if let wrapped: CoursesEnvelope = await decodeIfPossible(data) {
            return wrapped.courses
        }
        if let plain: [CourseDTO] = await decodeIfPossible(data) {
            return plain
        }

        if let extracted = try extractArrayFromUnknownPayload(data, candidateKeys: ["courses", "data", "collection", "items"]) {
            return try await decodeArrayElements(extracted, as: CourseDTO.self)
        }

        throw RepositoryError.invalidPayloadPreview(previewString(from: data))
    }

    private func requestWithPathFallbacks(_ paths: [String], queryItems: [URLQueryItem] = []) async throws -> Data {
        var lastError: Error?

        for path in paths {
            do {
                return try await apiClient.performRequest(path: path, queryItems: queryItems)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? StudIPAPIClient.APIClientError.invalidPath
    }

    private func decodeIfPossible<T: Decodable>(_ data: Data) async -> T? {
        await MainActor.run {
            try? JSONDecoder().decode(T.self, from: data)
        }
    }

    private func decodeArrayElements<T: Decodable>(_ elements: [Any], as type: T.Type) async throws -> [T] {
        var result: [T] = []

        for element in elements {
            guard JSONSerialization.isValidJSONObject(element) else { continue }
            let itemData = try JSONSerialization.data(withJSONObject: element)
            if let decoded: T = await decodeIfPossible(itemData) {
                result.append(decoded)
            }
        }

        if result.isEmpty {
            throw RepositoryError.invalidPayloadPreview("Array vorhanden, aber Elemente nicht dekodierbar")
        }

        return result
    }

    private func extractArrayFromUnknownPayload(_ data: Data, candidateKeys: [String]) throws -> [Any]? {
        let json = try JSONSerialization.jsonObject(with: data)

        if let array = json as? [Any] {
            return array
        }

        guard let dictionary = json as? [String: Any] else {
            return nil
        }

        for key in candidateKeys {
            if let array = dictionary[key] as? [Any] {
                return array
            }
            if let objectMap = dictionary[key] as? [String: Any] {
                return Array(objectMap.values)
            }
        }

        for (_, value) in dictionary {
            if let nested = value as? [String: Any] {
                for key in candidateKeys {
                    if let array = nested[key] as? [Any] {
                        return array
                    }
                    if let objectMap = nested[key] as? [String: Any] {
                        return Array(objectMap.values)
                    }
                }

                // Some Stud.IP variants return collection as a dictionary of endpoint -> object.
                // In that case, use all dictionary values as element candidates.
                if nested.values.allSatisfy({ $0 is [String: Any] }) {
                    return Array(nested.values)
                }
            }
        }

        // Fallback: top-level dictionary with many object values.
        if dictionary.values.allSatisfy({ $0 is [String: Any] }) {
            return Array(dictionary.values)
        }

        return nil
    }

    private func previewString(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<nicht-UTF8 payload>"
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        return String(compact.prefix(240))
    }
}

struct SemesterDTO: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let begin: Date?
    let end: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case begin
        case end
        case attributes
        case name
        case start
        case semesterID = "semester_id"
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case name
        case begin
        case end
        case start
        case semesterID = "semester_id"
    }

    init(id: String, title: String, begin: Date? = nil, end: Date? = nil) {
        self.id = id
        self.title = title
        self.begin = begin
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedAttributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)

        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? nestedAttributes?.decodeIfPresent(String.self, forKey: .semesterID)
            ?? container.decodeIfPresent(String.self, forKey: .semesterID)
            ?? UUID().uuidString

        if let attributes = nestedAttributes {
            title = try attributes.decodeIfPresent(String.self, forKey: .title)
                ?? attributes.decodeIfPresent(String.self, forKey: .name)
                ?? "Semester \(id)"
            begin = try SemesterDTO.decodeDate(from: attributes, primary: .begin, fallback: .start)
            end = try SemesterDTO.decodeDate(from: attributes, primary: .end, fallback: nil)
            return
        }

        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? "Semester \(id)"
        begin = try SemesterDTO.decodeDate(from: container, primary: .begin, fallback: .start)
        end = try SemesterDTO.decodeDate(from: container, primary: .end, fallback: nil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(begin?.timeIntervalSince1970, forKey: .begin)
        try container.encodeIfPresent(end?.timeIntervalSince1970, forKey: .end)
    }

    private static func decodeDate<K: CodingKey>(from container: KeyedDecodingContainer<K>, primary: K, fallback: K?) throws -> Date? {
        if let value = try container.decodeIfPresent(Double.self, forKey: primary) {
            return Date(timeIntervalSince1970: value)
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: primary) {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        if let value = try container.decodeIfPresent(String.self, forKey: primary), let intValue = TimeInterval(value) {
            return Date(timeIntervalSince1970: intValue)
        }

        if let fallback,
           let value = try container.decodeIfPresent(Double.self, forKey: fallback) {
            return Date(timeIntervalSince1970: value)
        }
        if let fallback,
           let value = try container.decodeIfPresent(Int.self, forKey: fallback) {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        if let fallback,
           let value = try container.decodeIfPresent(String.self, forKey: fallback),
           let intValue = TimeInterval(value) {
            return Date(timeIntervalSince1970: intValue)
        }

        return nil
    }
}

struct CourseDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case attributes
        case name
        case courseID = "course_id"
    }

    enum AttributesCodingKeys: String, CodingKey {
        case title
        case name
        case courseID = "course_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedAttributes = try? container.nestedContainer(keyedBy: AttributesCodingKeys.self, forKey: .attributes)

        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? nestedAttributes?.decodeIfPresent(String.self, forKey: .courseID)
            ?? container.decodeIfPresent(String.self, forKey: .courseID)
            ?? UUID().uuidString

        if let attributes = nestedAttributes {
            title = try attributes.decodeIfPresent(String.self, forKey: .title)
                ?? attributes.decodeIfPresent(String.self, forKey: .name)
                ?? "Course \(id)"
        } else {
            title = try container.decodeIfPresent(String.self, forKey: .title)
                ?? container.decodeIfPresent(String.self, forKey: .name)
                ?? "Course \(id)"
        }
    }
}

private struct JSONAPIListResponse<Resource: Decodable>: Decodable {
    let data: [Resource]
}

private struct SemestersEnvelope: Decodable {
    let semesters: [SemesterDTO]
}

private struct CoursesEnvelope: Decodable {
    let courses: [CourseDTO]
}

