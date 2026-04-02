import Foundation

actor StudIPResourceRepository {
    enum CourseRawSection: String {
        case files
        case chat
        case wiki
        case participants
        case forum
    }

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

    struct CourseParticipant: Identifiable, Hashable {
        let id: String
        let userID: String
        let displayName: String
        let email: String?
        let permission: String?
        let position: Int?
        let group: Int?
        let label: String?
        let mkdate: String?
    }

    struct CourseFileRef: Identifiable, Hashable {
        let id: String
        let name: String
        let description: String?
        let ownerName: String?
        let mimeType: String?
        let downloads: Int?
        let fileSize: Int?
        let createdAt: Date?
        let changedAt: Date?
        let isReadable: Bool?
        let isDownloadable: Bool?
        let downloadURL: URL?
    }

    struct CourseChatThread: Identifiable, Hashable {
        let id: String
        let name: String
        let previewText: String?
        let contextType: String?
        let latestActivity: Date?
        let visitedAt: Date?
        let createdAt: Date?
        let changedAt: Date?
        let isCommentable: Bool?
        let isReadable: Bool?
        let isWritable: Bool?
        let isFollowed: Bool?
        let unseenComments: Int?
        let authorID: String?
        let avatarURL: URL?
    }

    struct CourseWikiPage: Identifiable, Hashable {
        let id: String
        let keyword: String
        let content: String?
        let changedAt: Date?
        let version: Int?
        let authorID: String?
        let authorName: String?
    }

    private let apiClient: StudIPAPIClient
    private let settingsStore: SettingsStore
    private let metadataCache: MetadataCache
    private var cachedCurrentUserID: String?
    private var cachedUsersByID: [String: UserDTO] = [:]

    init(apiClient: StudIPAPIClient, settingsStore: SettingsStore, metadataCache: MetadataCache) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.metadataCache = metadataCache
    }

    func loadSemestersStaleWhileRevalidate(onRefresh: (@MainActor ([SemesterDTO]) -> Void)? = nil) async throws -> SemesterLoadResult {
        let (baseURL, semesterStartDateFilter, semesterEndDateFilter) = await MainActor.run {
            (
                settingsStore.configuration.baseURL,
                settingsStore.configuration.semesterSearchStartDate,
                settingsStore.configuration.semesterSearchEndDate
            )
        }

        if let cached = try await metadataCache.load(baseURL: baseURL), !cached.semesters.isEmpty {
            if hasLikelyPlaceholderSemesterTitles(cached.semesters) {
                do {
                    let remoteSemesters = try await fetchRemoteSemesters()
                    try await metadataCache.save(semesters: remoteSemesters, baseURL: baseURL)
                    let filteredRemote = filterSemesters(
                        remoteSemesters,
                        startDate: semesterStartDateFilter,
                        endDate: semesterEndDateFilter
                    )
                    return SemesterLoadResult(semesters: filteredRemote, source: .remote)
                } catch {
                    AppLogger.error("Placeholder cache refresh failed, using cache: \(error.localizedDescription)")
                    let filteredCache = filterSemesters(
                        cached.semesters,
                        startDate: semesterStartDateFilter,
                        endDate: semesterEndDateFilter
                    )
                    return SemesterLoadResult(semesters: filteredCache, source: .cache)
                }
            } else {
                Task {
                    await refreshSemesters(
                        baseURL: baseURL,
                        semesterStartDateFilter: semesterStartDateFilter,
                        semesterEndDateFilter: semesterEndDateFilter,
                        onRefresh: onRefresh
                    )
                }
                let filteredCache = filterSemesters(
                    cached.semesters,
                    startDate: semesterStartDateFilter,
                    endDate: semesterEndDateFilter
                )
                return SemesterLoadResult(semesters: filteredCache, source: .cache)
            }
        }

        let remoteSemesters = try await fetchRemoteSemesters()
        try await metadataCache.save(semesters: remoteSemesters, baseURL: baseURL)
        let filteredRemote = filterSemesters(
            remoteSemesters,
            startDate: semesterStartDateFilter,
            endDate: semesterEndDateFilter
        )
        return SemesterLoadResult(semesters: filteredRemote, source: .remote)
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

    func warmupCurrentUserID() async {
        do {
            _ = try await ensureCurrentUserID()
        } catch {
            AppLogger.error("Current user warmup failed: \(error.localizedDescription)")
        }
    }

    func fetchCourses(for semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [CourseDTO] {
        let normalizedSemesterID = canonicalStudIPID(semesterID)
        let queryOffset = offset ?? defaultCourseOffset
        let queryLimit = limit ?? defaultCourseLimit
        let userID = try await ensureCurrentUserID()
        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: normalizedSemesterID)
            .paginate(offset: queryOffset, limit: queryLimit)
        let filtered = try await fetchUserCourses(userID: userID, queryItems: query.queryItems)

        if filtered.isEmpty {
            throw RepositoryError.noCoursesForSemester(normalizedSemesterID)
        }

        return filtered
    }

    func fetchCourse(id: String) async throws -> CourseDTO {
        try await fetchOne(StudIPQuery<CourseResource>().byID(canonicalStudIPID(id)))
    }

    func fetchRawCourseSectionResponse(courseID: String, section: CourseRawSection) async throws -> String {
        let path = courseSectionPath(courseID: courseID, section: section)
        let data = try await apiClient.performRequest(path: path)
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "<nicht-UTF8 payload, \(data.count) bytes>"
    }

    func fetchCourseFiles(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseFileRef] {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/file-refs",
            queryItems: [
                URLQueryItem(name: "page[offset]", value: String(offset)),
                URLQueryItem(name: "page[limit]", value: String(limit))
            ]
        )

        let fileRefs: [CourseFileRefDTO] = try await parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "file-refs", "files", "collection", "items"]
        )

        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        let mapped = fileRefs.map { fileRef in
            CourseFileRef(
                id: fileRef.id,
                name: fileRef.name ?? "Datei \(fileRef.id)",
                description: fileRef.description,
                ownerName: fileRef.ownerName,
                mimeType: fileRef.mimeType,
                downloads: fileRef.downloads,
                fileSize: fileRef.fileSize,
                createdAt: parseAPIDate(fileRef.mkdate),
                changedAt: parseAPIDate(fileRef.chdate),
                isReadable: fileRef.isReadable,
                isDownloadable: fileRef.isDownloadable,
                downloadURL: resolveRelativeURL(fileRef.downloadURLPath, baseURL: baseURL)
            )
        }

        return mapped.sorted { lhs, rhs in
            let lhsDate = lhs.changedAt ?? lhs.createdAt ?? .distantPast
            let rhsDate = rhs.changedAt ?? rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func fetchCourseChatThreads(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseChatThread] {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/blubber-threads",
            queryItems: [
                URLQueryItem(name: "page[offset]", value: String(offset)),
                URLQueryItem(name: "page[limit]", value: String(limit))
            ]
        )

        let threads: [CourseChatThreadDTO] = try await parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "blubber-threads", "threads", "collection", "items"]
        )

        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        let mapped = threads.map { thread in
            CourseChatThread(
                id: thread.id,
                name: thread.name ?? "Thread \(thread.id)",
                previewText: thread.content ?? thread.contextInfoHTML,
                contextType: thread.contextType,
                latestActivity: parseAPIDate(thread.latestActivity),
                visitedAt: parseAPIDate(thread.visitedAt),
                createdAt: parseAPIDate(thread.mkdate),
                changedAt: parseAPIDate(thread.chdate),
                isCommentable: thread.isCommentable,
                isReadable: thread.isReadable,
                isWritable: thread.isWritable,
                isFollowed: thread.isFollowed,
                unseenComments: thread.unseenComments,
                authorID: thread.authorID,
                avatarURL: resolveRelativeURL(thread.avatarURLPath, baseURL: baseURL)
            )
        }

        return mapped.sorted { lhs, rhs in
            let lhsDate = lhs.latestActivity ?? lhs.changedAt ?? lhs.createdAt ?? .distantPast
            let rhsDate = rhs.latestActivity ?? rhs.changedAt ?? rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func fetchCourseWikiPages(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseWikiPage] {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/wiki-pages",
            queryItems: [
                URLQueryItem(name: "page[offset]", value: String(offset)),
                URLQueryItem(name: "page[limit]", value: String(limit))
            ]
        )

        let pages: [CourseWikiPageDTO] = try await parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "wiki-pages", "pages", "collection", "items"]
        )

        let uniqueAuthorIDs = Array(Set(pages.compactMap(\.authorID)))
        var authorsByID: [String: UserDTO] = [:]
        authorsByID.reserveCapacity(uniqueAuthorIDs.count)
        for authorID in uniqueAuthorIDs {
            do {
                authorsByID[authorID] = try await fetchUserProfile(id: authorID)
            } catch {
                AppLogger.error("Failed to load wiki author profile \(authorID): \(error.localizedDescription)")
            }
        }

        let mapped = pages.map { page in
            CourseWikiPage(
                id: page.id,
                keyword: page.keyword ?? "Wiki \(page.id)",
                content: page.content,
                changedAt: parseAPIDate(page.chdate),
                version: page.version,
                authorID: page.authorID,
                authorName: page.authorID.flatMap { authorsByID[$0]?.preferredDisplayName }
            )
        }

        return mapped.sorted { lhs, rhs in
            let lhsDate = lhs.changedAt ?? .distantPast
            let rhsDate = rhs.changedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
        }
    }

    func fetchCourseParticipants(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseParticipant] {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/memberships",
            queryItems: [
                URLQueryItem(name: "page[offset]", value: String(offset)),
                URLQueryItem(name: "page[limit]", value: String(limit))
            ]
        )

        let memberships: [CourseMembershipDTO] = try await parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "memberships", "course-memberships", "collection", "items"]
        )

        let uniqueUserIDs = Array(Set(memberships.map(\.userID)))
        var usersByID: [String: UserDTO] = [:]
        usersByID.reserveCapacity(uniqueUserIDs.count)
        for userID in uniqueUserIDs {
            do {
                usersByID[userID] = try await fetchUserProfile(id: userID)
            } catch {
                AppLogger.error("Failed to load user profile \(userID): \(error.localizedDescription)")
            }
        }

        var participants: [CourseParticipant] = []
        participants.reserveCapacity(memberships.count)

        for membership in memberships {
            let user = usersByID[membership.userID]
            let displayName = user?.preferredDisplayName ?? "User \(membership.userID)"

            participants.append(
                CourseParticipant(
                    id: membership.id,
                    userID: membership.userID,
                    displayName: displayName,
                    email: user?.email,
                    permission: membership.permission,
                    position: membership.position,
                    group: membership.group,
                    label: membership.label,
                    mkdate: membership.mkdate
                )
            )
        }

        return participants.sorted { lhs, rhs in
            let lhsPosition = lhs.position ?? Int.max
            let rhsPosition = rhs.position ?? Int.max
            if lhsPosition != rhsPosition {
                return lhsPosition < rhsPosition
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
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
            let userID = try await ensureCurrentUserID()
            let q = StudIPQuery<CourseResource>()
                .whereFilter("semester", equals: canonicalStudIPID(semesterID))
                .paginate(offset: defaultCourseOffset, limit: defaultCourseLimit)
            query = (userCoursesPath(for: userID), q.queryItems)
        case .courseDetail(let courseID):
            let q = StudIPQuery<CourseResource>().byID(canonicalStudIPID(courseID))
            query = (q.path, q.queryItems)
        }

        guard let command = try? await apiClient.makeCURL(path: query.path, queryItems: query.queryItems) else {
            throw RepositoryError.invalidPayloadPreview("Konnte kein cURL-Kommando erzeugen")
        }

        return [command]
    }

    private func refreshSemesters(
        baseURL: URL,
        semesterStartDateFilter: Date?,
        semesterEndDateFilter: Date?,
        onRefresh: (@MainActor ([SemesterDTO]) -> Void)?
    ) async {
        do {
            let remoteSemesters = try await fetchRemoteSemesters()
            try await metadataCache.save(semesters: remoteSemesters, baseURL: baseURL)
            if let onRefresh {
                let filteredRemote = filterSemesters(
                    remoteSemesters,
                    startDate: semesterStartDateFilter,
                    endDate: semesterEndDateFilter
                )
                await onRefresh(filteredRemote)
            }
        } catch {
            AppLogger.error("Semester refresh failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemoteSemesters() async throws -> [SemesterDTO] {
        try await fetchSemesters()
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

    private func filterSemesters(_ semesters: [SemesterDTO], startDate: Date?, endDate: Date?) -> [SemesterDTO] {
        let calendar = Calendar.current
        let minDate = startDate.map { calendar.startOfDay(for: $0) }
        let maxExclusive = endDate
            .map { calendar.startOfDay(for: $0) }
            .flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }

        return semesters.filter { semester in
            guard let semesterStartDate = semester.begin ?? semester.startOfLectures ?? semester.end else {
                return true
            }

            if let minDate, semesterStartDate < minDate {
                return false
            }
            if let maxExclusive, semesterStartDate >= maxExclusive {
                return false
            }
            return true
        }
    }

    private func parseAPIDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let seconds = TimeInterval(trimmed) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let date = Self.apiISO8601WithFractionalSeconds.date(from: trimmed) ?? Self.apiISO8601.date(from: trimmed) {
            return date
        }
        return nil
    }

    private func resolveRelativeURL(_ raw: String?, baseURL: URL) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }

        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private nonisolated static let apiISO8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated static let apiISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func ensureCurrentUserID() async throws -> String {
        if let cachedCurrentUserID, !cachedCurrentUserID.isEmpty {
            return cachedCurrentUserID
        }

        let me = try await fetchUserProfile(id: "me")
        let id = canonicalStudIPID(me.id)
        cachedCurrentUserID = id
        return id
    }

    private func fetchUserProfile(id: String) async throws -> UserDTO {
        let normalizedID = canonicalStudIPID(id)
        if let cached = cachedUsersByID[normalizedID] {
            return cached
        }

        let user = try await fetchOne(StudIPQuery<UserResource>().byID(normalizedID))
        cachedUsersByID[normalizedID] = user
        return user
    }

    private func fetchUserCourses(userID: String, queryItems: [URLQueryItem]) async throws -> [CourseDTO] {
        let data = try await apiClient.performRequest(path: userCoursesPath(for: userID), queryItems: queryItems)
        return try await parseCollection(from: data, fallbackCollectionKeys: CourseResource.fallbackCollectionKeys)
    }

    private func userCoursesPath(for userID: String) -> String {
        let escapedID = canonicalStudIPID(userID).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        return "/v1/users/\(escapedID)/courses"
    }

    private func courseSectionPath(courseID: String, section: CourseRawSection) -> String {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID

        switch section {
        case .files:
            return "/v1/courses/\(escapedID)/file-refs"
        case .chat:
            return "/v1/courses/\(escapedID)/blubber-threads"
        case .wiki:
            return "/v1/courses/\(escapedID)/wiki-pages"
        case .participants:
            return "/v1/courses/\(escapedID)/memberships"
        case .forum:
            return "/v1/courses/\(escapedID)/forum-categories"
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
    let email: String?
    let phone: String?

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
        case email
        case mail
        case phone
        case telephone
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
        case email
        case mail
        case phone
        case telephone
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

        email = container.decodeNonEmptyString(forKey: .email)
            ?? container.decodeNonEmptyString(forKey: .mail)
            ?? attributes?.decodeNonEmptyString(forKey: .email)
            ?? attributes?.decodeNonEmptyString(forKey: .mail)

        phone = container.decodeNonEmptyString(forKey: .phone)
            ?? container.decodeNonEmptyString(forKey: .telephone)
            ?? attributes?.decodeNonEmptyString(forKey: .phone)
            ?? attributes?.decodeNonEmptyString(forKey: .telephone)
    }

    var preferredDisplayName: String? {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if let fullName, !fullName.isEmpty {
            return fullName
        }

        let composedName = [givenName, familyName]
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
