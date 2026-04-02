import Foundation

actor StudIPResourceRepository {
    private let defaultSemesterOffset = 0
    private let defaultSemesterLimit = 100
    private let defaultCourseOffset = 0
    private let defaultCourseLimit = 100

    private enum DebugQueryContext {
        case semesters
        case courses(semesterID: String)
        case courseDetail(courseID: String)
    }

    enum SemesterDataSource: String {
        case cache
        case remote
    }

    enum RepositoryError: LocalizedError {
        case invalidPayloadPreview(String)
        case noCoursesForSemester(String)

        var errorDescription: String? {
            switch self {
            case .invalidPayloadPreview(let preview):
                return "Unbekanntes Antwortformat. Preview: \(preview)"
            case .noCoursesForSemester(let semesterID):
                return "Keine Kurse fuer Semester \(semesterID) gefunden."
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
            if hasLikelyPlaceholderSemesterTitles(cached.semesters) {
                do {
                    let remoteSemesters = try await fetchRemoteSemesters()
                    try await metadataCache.save(semesters: remoteSemesters, baseURL: baseURL)
                    return SemesterLoadResult(semesters: remoteSemesters, source: .remote)
                } catch {
                    AppLogger.error("Placeholder cache refresh failed, using cache: \(error.localizedDescription)")
                    return SemesterLoadResult(semesters: cached.semesters, source: .cache)
                }
            } else {
                Task {
                    await refreshSemesters(baseURL: baseURL, onRefresh: onRefresh)
                }
                return SemesterLoadResult(semesters: cached.semesters, source: .cache)
            }
        }

        let remoteSemesters = try await fetchRemoteSemesters()
        try await metadataCache.save(semesters: remoteSemesters, baseURL: baseURL)
        return SemesterLoadResult(semesters: remoteSemesters, source: .remote)
    }

    func fetchSemesters(offset: Int? = nil, limit: Int? = nil) async throws -> [SemesterDTO] {
        let queryOffset = offset ?? defaultSemesterOffset
        let queryLimit = limit ?? defaultSemesterLimit
        let query = StudIPQuery<SemesterResource>()
            .paginate(offset: queryOffset, limit: queryLimit)
        return try await fetchCollection(query)
    }

    func fetchSemester(id: String) async throws -> SemesterDTO {
        try await fetchOne(StudIPQuery<SemesterResource>().byID(canonicalStudIPID(id)))
    }

    func fetchCourses(for semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [CourseDTO] {
        let normalizedSemesterID = canonicalStudIPID(semesterID)
        let queryOffset = offset ?? defaultCourseOffset
        let queryLimit = limit ?? defaultCourseLimit
        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: normalizedSemesterID)
            .paginate(offset: queryOffset, limit: queryLimit)

        let filtered: [CourseDTO]
        do {
            filtered = try await fetchCollection(query)
        } catch let apiError as StudIPAPIClient.APIClientError where isFallbackCandidateForSemesterCourses(apiError) {
            let fallbackCourses = try await fetchCoursesViaNestedSemesterRoutes(
                semesterID: normalizedSemesterID,
                offset: queryOffset,
                limit: queryLimit
            )
            if fallbackCourses.isEmpty {
                throw RepositoryError.noCoursesForSemester(normalizedSemesterID)
            }
            return fallbackCourses
        }

        if filtered.isEmpty {
            throw RepositoryError.noCoursesForSemester(normalizedSemesterID)
        }

        return filtered
    }

    func fetchCourse(id: String) async throws -> CourseDTO {
        try await fetchOne(StudIPQuery<CourseResource>().byID(canonicalStudIPID(id)))
    }

    func debugCurlCommands(for semesterID: String?, courseID: String?) async throws -> [String] {
        let context = debugQueryContext(semesterID: semesterID, courseID: courseID)
        let query: (path: String, queryItems: [URLQueryItem])

        switch context {
        case .semesters:
            let q = StudIPQuery<SemesterResource>()
                .paginate(offset: defaultSemesterOffset, limit: defaultSemesterLimit)
            query = (q.path, q.queryItems)
        case .courses(let semesterID):
            let q = StudIPQuery<CourseResource>()
                .whereFilter("semester", equals: canonicalStudIPID(semesterID))
                .paginate(offset: defaultCourseOffset, limit: defaultCourseLimit)
            query = (q.path, q.queryItems)
        case .courseDetail(let courseID):
            let q = StudIPQuery<CourseResource>().byID(canonicalStudIPID(courseID))
            query = (q.path, q.queryItems)
        }

        guard let command = try? await apiClient.makeCURL(path: query.path, queryItems: query.queryItems) else {
            throw RepositoryError.invalidPayloadPreview("Konnte kein cURL-Kommando erzeugen")
        }

        return [command]
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
        try await fetchSemesters()
    }

    private func fetchCoursesViaNestedSemesterRoutes(semesterID: String, offset: Int, limit: Int) async throws -> [CourseDTO] {
        let escapedID = semesterID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? semesterID
        let fallbackPaths = [
            "/v1/semesters/\(escapedID)/courses",
            "/v1/semester/\(escapedID)/courses"
        ]
        let queryItems = [
            URLQueryItem(name: "page[offset]", value: String(offset)),
            URLQueryItem(name: "page[limit]", value: String(limit))
        ]

        for path in fallbackPaths {
            do {
                let data = try await apiClient.performRequest(path: path, queryItems: queryItems)
                let courses: [CourseDTO] = try await parseCollection(
                    from: data,
                    fallbackCollectionKeys: CourseResource.fallbackCollectionKeys
                )
                return courses
            } catch let apiError as StudIPAPIClient.APIClientError where isFallbackCandidateForSemesterCourses(apiError) {
                continue
            } catch let repositoryError as RepositoryError {
                switch repositoryError {
                case .invalidPayloadPreview:
                    continue
                case .noCoursesForSemester:
                    continue
                }
            }
        }

        return []
    }

    private func isFallbackCandidateForSemesterCourses(_ error: StudIPAPIClient.APIClientError) -> Bool {
        guard case .httpStatus(let code, _) = error else {
            return false
        }
        return code == 400 || code == 404
    }

    private func debugQueryContext(semesterID: String?, courseID: String?) -> DebugQueryContext {
        if let courseID, !courseID.isEmpty {
            return .courseDetail(courseID: canonicalStudIPID(courseID))
        }
        if let semesterID, !semesterID.isEmpty {
            return .courses(semesterID: canonicalStudIPID(semesterID))
        }
        return .semesters
    }

    private func hasLikelyPlaceholderSemesterTitles(_ semesters: [SemesterDTO]) -> Bool {
        semesters.contains { semester in
            semester.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .hasPrefix("semester ")
        }
    }

    private func fetchCollection<Resource: StudIPResourceDescriptor>(_ query: StudIPQuery<Resource>) async throws -> [Resource.Model] {
        let data = try await apiClient.performRequest(path: query.path, queryItems: query.queryItems)
        return try await parseCollection(
            from: data,
            fallbackCollectionKeys: Resource.fallbackCollectionKeys
        )
    }

    private func fetchOne<Resource: StudIPResourceDescriptor>(_ query: StudIPQuery<Resource>) async throws -> Resource.Model {
        let data = try await apiClient.performRequest(path: query.path, queryItems: query.queryItems)
        return try await parseEntity(
            from: data,
            fallbackObjectKeys: Resource.fallbackCollectionKeys + ["data", "item"]
        )
    }

    private func parseCollection<Model: Decodable>(
        from data: Data,
        fallbackCollectionKeys: [String]
    ) async throws -> [Model] {
        if let wrapped: JSONAPIListResponse<Model> = await decodeIfPossible(data) {
            return wrapped.data
        }
        if let plain: [Model] = await decodeIfPossible(data) {
            return plain
        }

        if let extracted = try extractArrayFromUnknownPayload(data, candidateKeys: fallbackCollectionKeys) {
            return try await decodeArrayElements(extracted, as: Model.self)
        }

        throw RepositoryError.invalidPayloadPreview(previewString(from: data))
    }

    private func parseEntity<Model: Decodable>(
        from data: Data,
        fallbackObjectKeys: [String]
    ) async throws -> Model {
        if let wrapped: JSONAPISingleResponse<Model> = await decodeIfPossible(data) {
            return wrapped.data
        }
        if let plain: Model = await decodeIfPossible(data) {
            return plain
        }

        let json = try JSONSerialization.jsonObject(with: data)

        if let dictionary = json as? [String: Any] {
            for key in fallbackObjectKeys {
                if let nested = dictionary[key] as? [String: Any],
                   let decoded: Model = await decodeJSONObject(nested) {
                    return decoded
                }
            }
        }

        if let array = try extractArrayFromUnknownPayload(data, candidateKeys: fallbackObjectKeys),
           let first = array.first,
           let decoded: Model = await decodeJSONObject(first) {
            return decoded
        }

        throw RepositoryError.invalidPayloadPreview(previewString(from: data))
    }

    private func decodeIfPossible<T: Decodable>(_ data: Data) async -> T? {
        await MainActor.run {
            try? JSONDecoder().decode(T.self, from: data)
        }
    }

    private func decodeArrayElements<T: Decodable>(_ elements: [Any], as type: T.Type) async throws -> [T] {
        var result: [T] = []

        for element in elements {
            if let decoded: T = await decodeJSONObject(element) {
                result.append(decoded)
                continue
            }

            // Some APIs return wrapper objects where the first value is the actual payload object.
            if let dictionary = element as? [String: Any],
               let nestedObject = dictionary.values.first,
               let decodedNested: T = await decodeJSONObject(nestedObject) {
                result.append(decodedNested)
                continue
            }

            // Some APIs return each element as a JSON string.
            if let stringElement = element as? String,
               let stringData = stringElement.data(using: .utf8),
               let decodedString: T = await decodeIfPossible(stringData) {
                result.append(decodedString)
            }
        }

        if result.isEmpty {
            let samplePreview = String(describing: elements.first ?? "<leer>")
            throw RepositoryError.invalidPayloadPreview("Array vorhanden, aber Elemente nicht dekodierbar. Erstes Element: \(samplePreview.prefix(180))")
        }

        return result
    }

    private func decodeJSONObject<T: Decodable>(_ object: Any) async -> T? {
        guard JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        guard let itemData = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return await decodeIfPossible(itemData)
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
                return valuesWithInjectedIDs(from: objectMap)
            }
        }

        for value in dictionary.values {
            if let nested = value as? [String: Any] {
                for key in candidateKeys {
                    if let array = nested[key] as? [Any] {
                        return array
                    }
                    if let objectMap = nested[key] as? [String: Any] {
                        return valuesWithInjectedIDs(from: objectMap)
                    }
                }
            }
        }

        return nil
    }

    private func previewString(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<nicht-UTF8 payload>"
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        return String(compact.prefix(240))
    }

    private func valuesWithInjectedIDs(from objectMap: [String: Any]) -> [Any] {
        objectMap.map { key, value in
            guard var dictionary = value as? [String: Any] else {
                return value
            }
            if dictionary["id"] == nil {
                dictionary["id"] = key
            }
            return dictionary
        }
    }
}

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
    let semesterID: String?
    let startSemesterRef: String?
    let endSemesterRef: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
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
        case courseID = "course_id"
        case semesterID = "semester_id"
        case startSemester = "start_semester"
        case endSemester = "end_semester"
    }

    enum RelationshipsCodingKeys: String, CodingKey {
        case semester
        case startSemester = "start-semester"
        case endSemester = "end-semester"
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
        } else {
            title = container.decodeNonEmptyString(forKey: .title)
                ?? container.decodeNonEmptyString(forKey: .name)
                ?? "Course \(id)"
        }

        let topSemester = container.decodeStringLossy(forKey: .semesterID)
        let attrSemester = nestedAttributes?.decodeStringLossy(forKey: .semesterID)

        let topStart = container.decodeStringLossy(forKey: .startSemester)
        let attrStart = nestedAttributes?.decodeStringLossy(forKey: .startSemester)

        let topEnd = container.decodeStringLossy(forKey: .endSemester)
        let attrEnd = nestedAttributes?.decodeStringLossy(forKey: .endSemester)

        let relationships = try? container.nestedContainer(keyedBy: RelationshipsCodingKeys.self, forKey: .relationships)
        let relSemester = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .semester)?.data?.id
        let relStart = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .startSemester)?.data?.id
        let relEnd = try relationships?.decodeIfPresent(JSONAPIRelationshipIdentifier.self, forKey: .endSemester)?.data?.id

        semesterID = (topSemester ?? attrSemester ?? relSemester).map(canonicalStudIPID)
        startSemesterRef = (topStart ?? attrStart ?? relStart).map(canonicalStudIPID)
        endSemesterRef = (topEnd ?? attrEnd ?? relEnd).map(canonicalStudIPID)
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

private struct JSONAPIListResponse<Resource: Decodable>: Decodable {
    let data: [Resource]
}

private struct JSONAPISingleResponse<Resource: Decodable>: Decodable {
    let data: Resource
}

private struct JSONAPIRelationshipIdentifier: Decodable {
    struct Linkage: Decodable {
        let id: String
    }

    let data: Linkage?
}
private extension KeyedDecodingContainer {
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
}

private func canonicalStudIPID(_ raw: String) -> String {
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

private func normalizedStudIPID(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let uuidLikePattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"

    if trimmed.range(of: uuidLikePattern, options: .regularExpression) != nil {
        return trimmed.replacingOccurrences(of: "-", with: "").lowercased()
    }

    return trimmed
}
