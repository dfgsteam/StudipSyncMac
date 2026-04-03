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
        search: String? = nil,
        searchFields: String? = nil,
        offset: Int? = nil,
        limit: Int? = nil
    ) async throws -> [CourseDTO] {
        let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSearch = normalizedCourseSearchQuery(from: trimmedSearch)
        let normalizedSemesterID = semesterID.map(canonicalStudIPID)
        let normalizedFields = normalizedCourseSearchFields(from: searchFields)
        let queryOffset = offset ?? defaultCourseOffset
        let queryLimit = limit ?? defaultCourseLimit

        // /courses supports filter[q], filter[fields], filter[semester] (see api.md)
        // /users/{id}/courses is user-scoped and must not use filter[user].
        if let userID {
            let normalizedUserID = canonicalStudIPID(userID)
            let userScopedQuery = StudIPQuery<CourseResource>()
                .whereFilter("semester", equals: normalizedSemesterID)
                .paginate(offset: queryOffset, limit: queryLimit)

            let data = try await apiClient.performRequest(
                path: userCoursesPath(for: normalizedUserID),
                queryItems: userScopedQuery.queryItems
            )
            let courses = try responseDecoder.parseCollection(
                from: data,
                fallbackCollectionKeys: CourseResource.fallbackCollectionKeys
            ) as [CourseDTO]

            guard let normalizedSearch else {
                return courses
            }

            return filterCoursesLocally(
                courses,
                search: normalizedSearch,
                fields: normalizedFields
            )
        } else {
            let collectionQuery = StudIPQuery<CourseResource>()
                .whereFilter("semester", equals: normalizedSemesterID)
                .whereFilter("q", equals: normalizedSearch)
                .whereFilter("fields", equals: normalizedFields)
                .paginate(offset: queryOffset, limit: queryLimit)

            let data = try await apiClient.performRequest(path: collectionQuery.path, queryItems: collectionQuery.queryItems)
            return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: CourseResource.fallbackCollectionKeys)
        }
    }

    func fetchCourses(for semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [CourseDTO] {
        let normalizedSemesterID = canonicalStudIPID(semesterID)
        let queryOffset = offset ?? defaultCourseOffset
        let queryLimit = limit ?? defaultCourseLimit
        let userID = try await userRepository.ensureCurrentUserID()

        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: normalizedSemesterID)
            .paginate(offset: queryOffset, limit: queryLimit)

        let serverResult: [CourseDTO]
        do {
            serverResult = try await fetchUserCourses(userID: userID, queryItems: query.queryItems)
        } catch {
            // Some installations expose /users/{id}/courses without semester filter support.
            let fallbackQuery = StudIPQuery<CourseResource>()
                .paginate(offset: queryOffset, limit: queryLimit)
            let allUserCourses = try await fetchUserCourses(userID: userID, queryItems: fallbackQuery.queryItems)
            serverResult = allUserCourses
        }

        let filtered = serverResult.filter { $0.matches(semesterID: normalizedSemesterID) }
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
        let normalizedSemesterID = semesterID.map(canonicalStudIPID)
        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: normalizedSemesterID)
            .paginate(offset: offset ?? defaultCourseOffset, limit: limit ?? defaultCourseLimit)

        do {
            let courses = try await fetchUserCourses(userID: normalizedUserID, queryItems: query.queryItems)
            guard let normalizedSemesterID else { return courses }
            return courses.filter { $0.matches(semesterID: normalizedSemesterID) }
        } catch {
            guard let normalizedSemesterID else { throw error }
            let fallbackQuery = StudIPQuery<CourseResource>()
                .paginate(offset: offset ?? defaultCourseOffset, limit: limit ?? defaultCourseLimit)
            let courses = try await fetchUserCourses(userID: normalizedUserID, queryItems: fallbackQuery.queryItems)
            return courses.filter { $0.matches(semesterID: normalizedSemesterID) }
        }
    }

    func fetchCourse(id: String) async throws -> CourseDTO {
        try await fetchOne(StudIPQuery<CourseResource>().byID(canonicalStudIPID(id)))
    }

    func enrollCurrentUser(courseID: String) async throws {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedCourseID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID
        let userID = try await userRepository.ensureCurrentUserID()

        let userLinkage = JSONAPIToManyRelationshipWriteDTO(
            data: [JSONAPIResourceIdentifierDTO(type: "users", id: userID)]
        )
        do {
            _ = try await apiClient.performRequest(
                path: "/v1/courses/\(escapedCourseID)/relationships/memberships",
                method: .post,
                body: userLinkage
            )
            return
        } catch {
            let membershipID = "\(normalizedCourseID)_\(canonicalStudIPID(userID))"
            let membershipLinkage = JSONAPIToManyRelationshipWriteDTO(
                data: [JSONAPIResourceIdentifierDTO(type: "course-memberships", id: membershipID)]
            )
            _ = try await apiClient.performRequest(
                path: "/v1/courses/\(escapedCourseID)/relationships/memberships",
                method: .post,
                body: membershipLinkage
            )
        }
    }

    func debugUserCoursesQuery(for semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> (path: String, queryItems: [URLQueryItem]) {
        let userID = try await userRepository.ensureCurrentUserID()

        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: canonicalStudIPID(semesterID))
            .paginate(offset: offset ?? defaultCourseOffset, limit: limit ?? defaultCourseLimit)

        return (userCoursesPath(for: userID), query.queryItems)
    }

    private func normalizedCourseSearchQuery(from search: String?) -> String? {
        guard let search, !search.isEmpty else { return nil }
        guard search.count >= 3 else { return nil }
        return search
    }

    private func normalizedCourseSearchFields(from fields: String?) -> String? {
        guard let fields else { return nil }
        let trimmed = fields.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        let allowed: Set<String> = [
            "all",
            "title_lecturer_number",
            "title",
            "sub_title",
            "lecturer",
            "number",
            "comment",
            "scope"
        ]

        if allowed.contains(normalized) {
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
            if tokenSet.count == 1, let single = tokenSet.first, allowed.contains(single) {
                return single
            }
        }

        // Unknown token: omit fields filter to avoid server-side 400 errors.
        return nil
    }

    private func filterCoursesLocally(_ courses: [CourseDTO], search: String, fields: String?) -> [CourseDTO] {
        let normalizedSearch = search.lowercased()

        let requestedFields: [String]
        if let fields {
            let normalizedFields = fields.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalizedFields {
            case "title_lecturer_number":
                requestedFields = ["title", "lecturer", "number"]
            case "sub_title":
                requestedFields = ["subtitle"]
            case "all":
                requestedFields = ["title", "lecturer", "number", "id", "subtitle", "description", "location", "comment", "scope"]
            default:
                requestedFields = normalizedFields
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            }
        } else {
            requestedFields = ["title", "lecturer", "number", "id", "subtitle", "description", "location"]
        }

        return courses.filter { course in
            var haystacks: [String] = []
            for field in requestedFields {
                switch field {
                case "title":
                    haystacks.append(course.title)
                case "number", "course-number":
                    if let value = course.courseNumber { haystacks.append(value) }
                case "lecturer":
                    if let value = course.description { haystacks.append(value) } // fallback: no dedicated lecturer field in DTO
                case "subtitle":
                    if let value = course.subtitle { haystacks.append(value) }
                case "description":
                    if let value = course.description { haystacks.append(value) }
                case "location":
                    if let value = course.location { haystacks.append(value) }
                case "id":
                    haystacks.append(course.id)
                default:
                    // Unknown server field token: include common text fields as fallback.
                    haystacks.append(course.title)
                    if let value = course.courseNumber { haystacks.append(value) }
                    if let value = course.subtitle { haystacks.append(value) }
                    if let value = course.description { haystacks.append(value) }
                    if let value = course.location { haystacks.append(value) }
                    haystacks.append(course.id)
                }
            }

            let joined = haystacks.joined(separator: " ").lowercased()
            return joined.contains(normalizedSearch)
        }
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
