import Foundation

actor StudIPResourceRepository {
    typealias CourseRawSection = StudIPCourseRawSection
    typealias SemesterDataSource = StudIPSemesterDataSource
    typealias RepositoryError = StudIPRepositoryError
    typealias SemesterLoadResult = StudIPSemesterLoadResult
    typealias CourseParticipant = StudIPCourseParticipant
    typealias CourseFileRef = StudIPCourseFileRef
    typealias CourseChatThread = StudIPCourseChatThread
    typealias CourseWikiPage = StudIPCourseWikiPage
    typealias CourseForumCategory = ForumCategoryDTO

    private let defaultSemesterOffset = 0
    private let defaultSemesterLimit = 100

    private enum DebugQueryContext {
        case semesters
        case courses(semesterID: String)
        case courseDetail(courseID: String)
    }

    private let apiClient: StudIPAPIClient
    private let settingsStore: SettingsStore
    private let metadataCache: MetadataCache

    private let semesterRepository: StudIPSemesterRepository
    private let userRepository: StudIPUserRepository
    private let courseRepository: StudIPCourseRepository
    private let courseSectionRepository: StudIPCourseSectionRepository
    private let fileRepository: StudIPFileRepository
    private let plannerRepository: StudIPPlannerRepository
    private let newsRepository: StudIPNewsRepository
    private let blubberRepository: StudIPBlubberRepository
    private let forumRepository: StudIPForumRepository
    private let userDirectoryRepository: StudIPUserDirectoryRepository

    init(apiClient: StudIPAPIClient, settingsStore: SettingsStore, metadataCache: MetadataCache) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.metadataCache = metadataCache

        let responseDecoder = StudIPResponseDecoder()
        let userRepository = StudIPUserRepository(apiClient: apiClient, responseDecoder: responseDecoder)

        self.userRepository = userRepository
        self.semesterRepository = StudIPSemesterRepository(apiClient: apiClient, responseDecoder: responseDecoder)
        self.courseRepository = StudIPCourseRepository(
            apiClient: apiClient,
            userRepository: userRepository,
            responseDecoder: responseDecoder
        )
        self.courseSectionRepository = StudIPCourseSectionRepository(
            apiClient: apiClient,
            settingsStore: settingsStore,
            userRepository: userRepository,
            responseDecoder: responseDecoder
        )
        self.fileRepository = StudIPFileRepository(apiClient: apiClient, responseDecoder: responseDecoder)
        self.plannerRepository = StudIPPlannerRepository(apiClient: apiClient, responseDecoder: responseDecoder)
        self.newsRepository = StudIPNewsRepository(apiClient: apiClient, responseDecoder: responseDecoder)
        self.blubberRepository = StudIPBlubberRepository(apiClient: apiClient, responseDecoder: responseDecoder)
        self.forumRepository = StudIPForumRepository(apiClient: apiClient, responseDecoder: responseDecoder)
        self.userDirectoryRepository = StudIPUserDirectoryRepository(apiClient: apiClient, responseDecoder: responseDecoder)
    }

    func files() -> StudIPFileRepository { fileRepository }
    func planner() -> StudIPPlannerRepository { plannerRepository }
    func news() -> StudIPNewsRepository { newsRepository }
    func blubber() -> StudIPBlubberRepository { blubberRepository }
    func forum() -> StudIPForumRepository { forumRepository }
    func users() -> StudIPUserDirectoryRepository { userDirectoryRepository }
    func coursesAPI() -> StudIPCourseRepository { courseRepository }

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
        return try await semesterRepository.fetchSemesters(offset: queryOffset, limit: queryLimit)
    }

    func fetchSemester(id: String) async throws -> SemesterDTO {
        try await semesterRepository.fetchSemester(id: id)
    }

    func warmupCurrentUserID() async {
        await userRepository.warmupCurrentUserID()
    }

    func fetchCourses(for semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [CourseDTO] {
        try await courseRepository.fetchCourses(for: semesterID, offset: offset, limit: limit)
    }

    func fetchCourse(id: String) async throws -> CourseDTO {
        try await courseRepository.fetchCourse(id: id)
    }

    func fetchRawCourseSectionResponse(courseID: String, section: CourseRawSection) async throws -> String {
        try await courseSectionRepository.fetchRawCourseSectionResponse(courseID: courseID, section: section)
    }

    func fetchCourseFiles(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseFileRef] {
        try await courseSectionRepository.fetchCourseFiles(courseID: courseID, offset: offset, limit: limit)
    }

    func fetchCourseChatThreads(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseChatThread] {
        try await courseSectionRepository.fetchCourseChatThreads(courseID: courseID, offset: offset, limit: limit)
    }

    func fetchCourseWikiPages(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseWikiPage] {
        try await courseSectionRepository.fetchCourseWikiPages(courseID: courseID, offset: offset, limit: limit)
    }

    func fetchCourseParticipants(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseParticipant] {
        try await courseSectionRepository.fetchCourseParticipants(courseID: courseID, offset: offset, limit: limit)
    }

    func fetchUsersByIDs(_ userIDs: [String]) async -> [String: UserDTO] {
        let normalizedIDs = Array<Any>(
            Set(
                userIDs.compactMap { rawID in
                    let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return canonicalStudIPID(trimmed)
                }
            )
        )
        guard !normalizedIDs.isEmpty else { return [:] }
        return await userRepository.fetchUsers(userIDs: normalizedIDs)
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
            query = try await courseRepository.debugUserCoursesQuery(for: semesterID)
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
        try await semesterRepository.fetchSemesters(offset: defaultSemesterOffset, limit: defaultSemesterLimit)
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
}
