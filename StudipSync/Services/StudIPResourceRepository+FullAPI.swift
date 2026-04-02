import Foundation

extension StudIPResourceRepository {
    // MARK: - Courses

    func fetchCoursesCollection(
        semesterID: String? = nil,
        userID: String? = nil,
        search: String? = nil,
        offset: Int? = nil,
        limit: Int? = nil
    ) async throws -> [CourseDTO] {
        try await coursesAPI().fetchCoursesCollection(
            semesterID: semesterID,
            userID: userID,
            search: search,
            offset: offset,
            limit: limit
        )
    }

    func fetchCoursesForUser(
        userID: String,
        semesterID: String? = nil,
        offset: Int? = nil,
        limit: Int? = nil
    ) async throws -> [CourseDTO] {
        try await coursesAPI().fetchCoursesForUser(
            userID: userID,
            semesterID: semesterID,
            offset: offset,
            limit: limit
        )
    }

    func enrollCurrentUser(courseID: String) async throws {
        try await coursesAPI().enrollCurrentUser(courseID: courseID)
    }

    // MARK: - Files

    func fetchTermsOfUse() async throws -> [TermsOfUseDTO] {
        try await files().fetchTermsOfUse()
    }

    func fetchTermsOfUse(id: String) async throws -> TermsOfUseDTO {
        try await files().fetchTermsOfUse(id: id)
    }

    func fetchFileRefs(scope: StudIPContainerScope, offset: Int = 0, limit: Int = 30) async throws -> [CourseFileRefDTO] {
        try await files().fetchFileRefs(scope: scope, offset: offset, limit: limit)
    }

    func fetchFolders(scope: StudIPContainerScope, offset: Int = 0, limit: Int = 30) async throws -> [FolderDTO] {
        try await files().fetchFolders(scope: scope, offset: offset, limit: limit)
    }

    func fetchFileRef(id: String) async throws -> CourseFileRefDTO {
        try await files().fetchFileRef(id: id)
    }

    func updateFileRef(id: String, attributes: FileRefPatchAttributesDTO) async throws -> CourseFileRefDTO {
        try await files().updateFileRef(id: id, attributes: attributes)
    }

    func deleteFileRef(id: String) async throws {
        try await files().deleteFileRef(id: id)
    }

    func fetchFolder(id: String) async throws -> FolderDTO {
        try await files().fetchFolder(id: id)
    }

    func updateFolder(id: String, attributes: FolderPatchAttributesDTO) async throws -> FolderDTO {
        try await files().updateFolder(id: id, attributes: attributes)
    }

    func deleteFolder(id: String) async throws {
        try await files().deleteFolder(id: id)
    }

    func fetchFolderFileRefs(folderID: String, offset: Int = 0, limit: Int = 30) async throws -> [CourseFileRefDTO] {
        try await files().fetchFolderFileRefs(folderID: folderID, offset: offset, limit: limit)
    }

    func fetchFolderFolders(folderID: String, offset: Int = 0, limit: Int = 30) async throws -> [FolderDTO] {
        try await files().fetchFolderFolders(folderID: folderID, offset: offset, limit: limit)
    }

    func fetchFileContent(fileRefID: String) async throws -> Data {
        try await files().fetchFileContent(fileRefID: fileRefID)
    }

    func headFileContent(fileRefID: String) async throws -> StudIPHTTPResponse {
        try await files().headFileContent(fileRefID: fileRefID)
    }

    // MARK: - Planner

    func fetchUserEvents(userID: String, timestamp: Int? = nil) async throws -> [EventDTO] {
        try await planner().fetchUserEvents(userID: userID, timestamp: timestamp)
    }

    func fetchUserEventsICS(userID: String) async throws -> String {
        try await planner().fetchUserEventsICS(userID: userID)
    }

    func fetchCourseEvents(courseID: String, offset: Int = 0, limit: Int = 30) async throws -> [EventDTO] {
        try await planner().fetchCourseEvents(courseID: courseID, offset: offset, limit: limit)
    }

    func fetchUserSchedule(userID: String, timestamp: Int? = nil) async throws -> [ScheduleEntryDTO] {
        try await planner().fetchUserSchedule(userID: userID, timestamp: timestamp)
    }

    func fetchScheduleEntry(id: String) async throws -> ScheduleEntryDTO {
        try await planner().fetchScheduleEntry(id: id)
    }

    func fetchSeminarCycleDate(id: String) async throws -> SeminarCycleDateDTO {
        try await planner().fetchSeminarCycleDate(id: id)
    }

    // MARK: - News

    func createNews(attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        try await news().createNews(attributes: attributes)
    }

    func createCourseNews(courseID: String, attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        try await news().createCourseNews(courseID: courseID, attributes: attributes)
    }

    func createUserNews(userID: String, attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        try await news().createUserNews(userID: userID, attributes: attributes)
    }

    func createNewsComment(newsID: String, content: String) async throws -> NewsCommentDTO {
        try await news().createNewsComment(newsID: newsID, content: content)
    }

    func updateNews(newsID: String, attributes: NewsWriteAttributesDTO) async throws -> NewsDTO {
        try await news().updateNews(newsID: newsID, attributes: attributes)
    }

    func fetchNews(id: String) async throws -> NewsDTO {
        try await news().fetchNews(id: id)
    }

    func fetchCourseNews(courseID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        try await news().fetchCourseNews(courseID: courseID, offset: offset, limit: limit)
    }

    func fetchUserNews(userID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        try await news().fetchUserNews(userID: userID, offset: offset, limit: limit)
    }

    func fetchNewsComments(newsID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [NewsCommentDTO] {
        try await news().fetchNewsComments(newsID: newsID, offset: offset, limit: limit)
    }

    func fetchStudipNews(offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        try await news().fetchStudipNews(offset: offset, limit: limit)
    }

    func fetchAllNews(offset: Int? = nil, limit: Int? = nil) async throws -> [NewsDTO] {
        try await news().fetchAllNews(offset: offset, limit: limit)
    }

    func deleteNews(id: String) async throws {
        try await news().deleteNews(id: id)
    }

    func deleteComment(id: String) async throws {
        try await news().deleteComment(id: id)
    }

    func fetchNewsRanges(newsID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await news().fetchNewsRanges(newsID: newsID)
    }

    func patchNewsRanges(newsID: String, ranges: [JSONAPIResourceIdentifierDTO]) async throws {
        try await news().patchNewsRanges(newsID: newsID, ranges: ranges)
    }

    func postNewsRanges(newsID: String, ranges: [JSONAPIResourceIdentifierDTO]) async throws {
        try await news().postNewsRanges(newsID: newsID, ranges: ranges)
    }

    func deleteNewsRanges(newsID: String, ranges: [JSONAPIResourceIdentifierDTO]? = nil) async throws {
        try await news().deleteNewsRanges(newsID: newsID, ranges: ranges)
    }

    // MARK: - Blubber

    func fetchBlubberPostings(query: BlubberPostingListQuery = .init()) async throws -> [BlubberPostingDTO] {
        try await blubber().fetchPostings(query: query)
    }

    func fetchBlubberPosting(id: String) async throws -> BlubberPostingDTO {
        try await blubber().fetchPosting(id: id)
    }

    func createBlubberPosting(attributes: BlubberPostingWriteAttributesDTO, context: JSONAPIResourceIdentifierDTO? = nil) async throws -> BlubberPostingDTO {
        try await blubber().createPosting(attributes: attributes, context: context)
    }

    func updateBlubberPosting(id: String, attributes: BlubberPostingWriteAttributesDTO) async throws -> BlubberPostingDTO {
        try await blubber().updatePosting(id: id, attributes: attributes)
    }

    func deleteBlubberPosting(id: String) async throws {
        try await blubber().deletePosting(id: id)
    }

    func fetchBlubberPostingComments(postingID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [BlubberPostingDTO] {
        try await blubber().fetchPostingComments(postingID: postingID, offset: offset, limit: limit)
    }

    func createBlubberPostingComment(postingID: String, content: String) async throws -> BlubberPostingDTO {
        try await blubber().createPostingComment(postingID: postingID, content: content)
    }

    func fetchBlubberPostingAuthorRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await blubber().fetchPostingAuthorRelationship(postingID: postingID)
    }

    func fetchBlubberPostingCommentsRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await blubber().fetchPostingCommentsRelationship(postingID: postingID)
    }

    func fetchBlubberPostingContextRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await blubber().fetchPostingContextRelationship(postingID: postingID)
    }

    func fetchBlubberPostingMentions(postingID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [StudIPGenericResourceDTO] {
        try await blubber().fetchPostingMentions(postingID: postingID, offset: offset, limit: limit)
    }

    func fetchBlubberPostingMentionsRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await blubber().fetchPostingMentionsRelationship(postingID: postingID)
    }

    func fetchBlubberPostingResharersRelationship(postingID: String) async throws -> [JSONAPIResourceIdentifierDTO] {
        try await blubber().fetchPostingResharersRelationship(postingID: postingID)
    }

    func fetchBlubberStream(id: String) async throws -> BlubberStreamDTO {
        try await blubber().fetchStream(id: id)
    }

    func fetchBlubberThreadComments(threadID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [BlubberPostingDTO] {
        try await blubber().fetchThreadComments(threadID: threadID, offset: offset, limit: limit)
    }

    // MARK: - Forum

    func fetchCourseForumCategories(courseID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [ForumCategoryDTO] {
        try await forum().fetchCourseForumCategories(courseID: courseID, offset: offset, limit: limit)
    }

    func fetchForumCategory(id: String) async throws -> ForumCategoryDTO {
        try await forum().fetchForumCategory(id: id)
    }

    func fetchForumCategoryEntries(categoryID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [ForumEntryDTO] {
        try await forum().fetchForumCategoryEntries(categoryID: categoryID, offset: offset, limit: limit)
    }

    func createCourseForumCategory(courseID: String, attributes: ForumCategoryWriteAttributesDTO) async throws -> ForumCategoryDTO {
        try await forum().createCourseForumCategory(courseID: courseID, attributes: attributes)
    }

    func updateForumCategory(id: String, attributes: ForumCategoryWriteAttributesDTO) async throws -> ForumCategoryDTO {
        try await forum().updateForumCategory(id: id, attributes: attributes)
    }

    func deleteForumCategory(id: String) async throws {
        try await forum().deleteForumCategory(id: id)
    }

    func fetchForumEntry(id: String) async throws -> ForumEntryDTO {
        try await forum().fetchForumEntry(id: id)
    }

    func fetchForumEntryEntries(entryID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [ForumEntryDTO] {
        try await forum().fetchForumEntryEntries(entryID: entryID, offset: offset, limit: limit)
    }

    func createForumEntryInCategory(categoryID: String, attributes: ForumEntryWriteAttributesDTO) async throws -> ForumEntryDTO {
        try await forum().createForumEntryInCategory(categoryID: categoryID, attributes: attributes)
    }

    func createForumEntryReply(entryID: String, attributes: ForumEntryWriteAttributesDTO) async throws -> ForumEntryDTO {
        try await forum().createForumEntryReply(entryID: entryID, attributes: attributes)
    }

    func updateForumEntry(id: String, attributes: ForumEntryWriteAttributesDTO) async throws -> ForumEntryDTO {
        try await forum().updateForumEntry(id: id, attributes: attributes)
    }

    func deleteForumEntry(id: String) async throws {
        try await forum().deleteForumEntry(id: id)
    }

    // MARK: - User Directory

    func fetchUsers(offset: Int = 0, limit: Int = 30, search: String? = nil) async throws -> [UserDTO] {
        try await users().fetchUsers(offset: offset, limit: limit, search: search)
    }

    func fetchMe() async throws -> UserDTO {
        try await users().fetchMe()
    }

    func fetchMeRawJSON() async throws -> String {
        try await users().fetchMeRawJSON()
    }

    func fetchUser(id: String) async throws -> UserDTO {
        try await users().fetchUser(id: id)
    }

    func deleteUser(id: String) async throws {
        try await users().deleteUser(id: id)
    }

    func fetchInstituteMemberships(userID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [InstituteMembershipDTO] {
        try await users().fetchInstituteMemberships(userID: userID, offset: offset, limit: limit)
    }

    // MARK: - Institutes

    func fetchInstitutes(offset: Int = 0, limit: Int = 200, search: String? = nil) async throws -> [InstituteDTO] {
        try await institutes().fetchInstitutes(offset: offset, limit: limit, search: search)
    }

    func fetchInstitute(id: String) async throws -> InstituteDTO {
        try await institutes().fetchInstitute(id: id)
    }

    func fetchInstituteCourses(instituteID: String, semesterID: String, offset: Int? = nil, limit: Int? = nil) async throws -> [CourseDTO] {
        let normalizedInstituteID = canonicalStudIPID(instituteID)
        let semesterCourses = try await fetchCoursesCollection(
            semesterID: semesterID,
            userID: nil,
            offset: offset,
            limit: limit
        )

        return semesterCourses.filter { course in
            guard let instituteID = course.instituteID else { return false }
            return canonicalStudIPID(instituteID) == normalizedInstituteID
        }
    }
}
