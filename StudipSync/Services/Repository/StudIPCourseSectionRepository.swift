import Foundation

actor StudIPCourseSectionRepository {
    private let apiClient: StudIPAPIClient
    private let settingsStore: SettingsStore
    private let userRepository: StudIPUserRepository
    private let responseDecoder: StudIPResponseDecoder

    init(
        apiClient: StudIPAPIClient,
        settingsStore: SettingsStore,
        userRepository: StudIPUserRepository,
        responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()
    ) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.userRepository = userRepository
        self.responseDecoder = responseDecoder
    }

    func fetchRawCourseSectionResponse(courseID: String, section: StudIPCourseRawSection) async throws -> String {
        let path = courseSectionPath(courseID: courseID, section: section)
        let data = try await apiClient.performRequest(path: path)
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "<nicht-UTF8 payload, \(data.count) bytes>"
    }

    func fetchCourseFiles(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [StudIPCourseFileRef] {
        let data = try await fetchCourseSectionCollection(
            courseID: courseID,
            suffix: "file-refs",
            offset: offset,
            limit: limit
        )

        let fileRefs: [CourseFileRefDTO] = try responseDecoder.parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "file-refs", "files", "collection", "items"]
        )

        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        let mapped = fileRefs.map { fileRef in
            StudIPCourseFileRef(
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

    func fetchCourseChatThreads(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [StudIPCourseChatThread] {
        let data = try await fetchCourseSectionCollection(
            courseID: courseID,
            suffix: "blubber-threads",
            offset: offset,
            limit: limit
        )

        let threads: [CourseChatThreadDTO] = try responseDecoder.parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "blubber-threads", "threads", "collection", "items"]
        )

        let baseURL = await MainActor.run { settingsStore.configuration.baseURL }
        let mapped = threads.map { thread in
            StudIPCourseChatThread(
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

    func fetchCourseWikiPages(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [StudIPCourseWikiPage] {
        let data = try await fetchCourseSectionCollection(
            courseID: courseID,
            suffix: "wiki-pages",
            offset: offset,
            limit: limit
        )

        let pages: [CourseWikiPageDTO] = try responseDecoder.parseCollection(
            from: data,
            fallbackCollectionKeys: ["data", "wiki-pages", "pages", "collection", "items"]
        )

        let uniqueAuthorIDs = Array(Set(pages.compactMap(\.authorID)))
        let authorsByID = await userRepository.fetchUsers(userIDs: uniqueAuthorIDs)

        let mapped = pages.map { page in
            StudIPCourseWikiPage(
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

    func fetchCourseParticipants(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [StudIPCourseParticipant] {
        let memberships = try await fetchCourseMemberships(
            courseID: courseID,
            offset: offset,
            limit: limit
        )

        let uniqueUserIDs = Array(Set(memberships.map(\.userID)))
        let usersByID = await userRepository.fetchUsers(userIDs: uniqueUserIDs)

        var participants: [StudIPCourseParticipant] = []
        participants.reserveCapacity(memberships.count)

        for membership in memberships {
            let user = usersByID[membership.userID]
            let displayName = user?.preferredDisplayName ?? "User \(membership.userID)"

            participants.append(
                StudIPCourseParticipant(
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

    func fetchCourseMemberships(courseID: String, offset: Int = 0, limit: Int = 1000) async throws -> [CourseMembershipDTO] {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/memberships",
            queryItems: [
                URLQueryItem(name: "page[offset]", value: String(offset)),
                URLQueryItem(name: "page[limit]", value: String(limit))
            ]
        )

        return try responseDecoder.parseCollection(
            from: data,
            fallbackCollectionKeys: CourseMembershipResource.fallbackCollectionKeys
        )
    }

    func fetchCourseMembership(id: String) async throws -> CourseMembershipDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/course-memberships/\(escapedID)")
        return try responseDecoder.parseEntity(
            from: data,
            fallbackObjectKeys: CourseMembershipResource.fallbackCollectionKeys + ["data", "item"]
        )
    }

    private func fetchCourseSectionCollection(courseID: String, suffix: String, offset: Int, limit: Int) async throws -> Data {
        let normalizedCourseID = canonicalStudIPID(courseID)
        let escapedID = normalizedCourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedCourseID

        return try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/\(suffix)",
            queryItems: [
                URLQueryItem(name: "page[offset]", value: String(offset)),
                URLQueryItem(name: "page[limit]", value: String(limit))
            ]
        )
    }

    private func courseSectionPath(courseID: String, section: StudIPCourseRawSection) -> String {
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

    private static let apiISO8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let apiISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
