import Foundation

actor StudIPCourseRepository {
    private let defaultCourseOffset = 0
    private let defaultCourseLimit = 100

    private let apiClient: StudIPAPIClient
    private let userRepository: StudIPUserRepository
    private let responseDecoder: StudIPResponseDecoder

    init(
        apiClient: StudIPAPIClient,
        userRepository: StudIPUserRepository,
        responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()
    ) {
        self.apiClient = apiClient
        self.userRepository = userRepository
        self.responseDecoder = responseDecoder
    }

    func fetchCoursesCollection(
        semesterID: String? = nil,
        userID: String? = nil,
        offset: Int? = nil,
        limit: Int? = nil
    ) async throws -> [CourseDTO] {
        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: semesterID.map(canonicalStudIPID))
            .whereFilter("user", equals: userID.map(canonicalStudIPID))
            .paginate(offset: offset ?? defaultCourseOffset, limit: limit ?? defaultCourseLimit)

        let data = try await apiClient.performRequest(path: query.path, queryItems: query.queryItems)
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: CourseResource.fallbackCollectionKeys)
    }

    func fetchCourses(for semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [CourseDTO] {
        let normalizedSemesterID = canonicalStudIPID(semesterID)
        let queryOffset = offset ?? defaultCourseOffset
        let queryLimit = limit ?? defaultCourseLimit
        let userID = try await userRepository.ensureCurrentUserID()

        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: normalizedSemesterID)
            .paginate(offset: queryOffset, limit: queryLimit)

        let filtered = try await fetchUserCourses(userID: userID, queryItems: query.queryItems)
        if filtered.isEmpty {
            throw StudIPRepositoryError.noCoursesForSemester(normalizedSemesterID)
        }

        return filtered
    }

    func fetchCoursesForUser(
        userID: String,
        semesterID: String? = nil,
        offset: Int? = nil,
        limit: Int? = nil
    ) async throws -> [CourseDTO] {
        let normalizedUserID = canonicalStudIPID(userID)
        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: semesterID.map(canonicalStudIPID))
            .paginate(offset: offset ?? defaultCourseOffset, limit: limit ?? defaultCourseLimit)

        return try await fetchUserCourses(userID: normalizedUserID, queryItems: query.queryItems)
    }

    func fetchCourse(id: String) async throws -> CourseDTO {
        try await fetchOne(StudIPQuery<CourseResource>().byID(canonicalStudIPID(id)))
    }

    func debugUserCoursesQuery(for semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> (path: String, queryItems: [URLQueryItem]) {
        let userID = try await userRepository.ensureCurrentUserID()

        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: canonicalStudIPID(semesterID))
            .paginate(offset: offset ?? defaultCourseOffset, limit: limit ?? defaultCourseLimit)

        return (userCoursesPath(for: userID), query.queryItems)
    }

    private func fetchUserCourses(userID: String, queryItems: [URLQueryItem]) async throws -> [CourseDTO] {
        let data = try await apiClient.performRequest(path: userCoursesPath(for: userID), queryItems: queryItems)
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: CourseResource.fallbackCollectionKeys)
    }

    private func fetchOne<Resource: StudIPResourceDescriptor>(_ query: StudIPQuery<Resource>) async throws -> Resource.Model {
        let data = try await apiClient.performRequest(path: query.path, queryItems: query.queryItems)
        return try responseDecoder.parseEntity(
            from: data,
            fallbackObjectKeys: Resource.fallbackCollectionKeys + ["data", "item"]
        )
    }

    private func userCoursesPath(for userID: String) -> String {
        let normalizedID = canonicalStudIPID(userID)
        let escapedID = normalizedID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedID
        return "/v1/users/\(escapedID)/courses"
    }
}
