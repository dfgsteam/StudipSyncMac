import Foundation

extension ContentView {
    func loadNewsForSelectedCourse(force: Bool = false) async {
        guard let selectedCourseID else {
            return
        }
        if !force, courseNewsByCourseID[selectedCourseID] != nil {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingCourseNews = true
        courseNewsErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingCourseNews = false
            }
        }

        do {
            let newsItems = try await repository.fetchCourseNews(
                courseID: requestCourseID,
                offset: 0,
                limit: 100
            )

            let sorted = newsItems.sorted { lhs, rhs in
                let lhsDate = parseAPIDate(lhs.chdate) ?? parseAPIDate(lhs.mkdate) ?? .distantPast
                let rhsDate = parseAPIDate(rhs.chdate) ?? parseAPIDate(rhs.mkdate) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }

            if selectedCourseID == requestCourseID {
                courseNewsByCourseID[requestCourseID] = sorted
                if let selectedID = selectedNewsIDByCourseID[requestCourseID],
                   sorted.contains(where: { $0.id == selectedID }) {
                    selectedNewsIDByCourseID[requestCourseID] = selectedID
                } else {
                    selectedNewsIDByCourseID[requestCourseID] = sorted.first?.id
                }
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: "news")
            }
        } catch {
            if selectedCourseID == requestCourseID {
                courseNewsErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Veranstaltungsnews: \(error.localizedDescription)"
            }
        }
    }

    func loadNewsCommentsForSelectedNews(force: Bool = false) async {
        guard let selectedCourseID else {
            return
        }
        guard let selectedNewsID = selectedNewsIDByCourseID[selectedCourseID] else {
            return
        }
        if !force, newsCommentsByNewsID[selectedNewsID] != nil {
            return
        }
        guard !loadingNewsCommentIDs.contains(selectedNewsID) else {
            return
        }

        let requestCourseID = selectedCourseID
        let requestNewsID = selectedNewsID
        loadingNewsCommentIDs.insert(requestNewsID)
        newsCommentErrorsByNewsID[requestNewsID] = nil
        defer { loadingNewsCommentIDs.remove(requestNewsID) }

        do {
            let comments = try await repository.fetchNewsComments(
                newsID: requestNewsID,
                offset: 0,
                limit: 1000
            )

            let sorted = comments.sorted { lhs, rhs in
                lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }

            if selectedCourseID == requestCourseID,
               selectedNewsIDByCourseID[requestCourseID] == requestNewsID {
                newsCommentsByNewsID[requestNewsID] = sorted
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: "news")
            }
        } catch {
            if selectedCourseID == requestCourseID,
               selectedNewsIDByCourseID[requestCourseID] == requestNewsID {
                newsCommentErrorsByNewsID[requestNewsID] = "Fehler beim Laden der News-Kommentare: \(error.localizedDescription)"
            }
        }
    }

    func loadFilesForSelectedSection(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.files.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        let selectedFolderID = activeFileFolderID(for: selectedCourseID)
        let contextKey = fileContextKey(courseID: selectedCourseID, folderID: selectedFolderID)
        if !force, filesByContextKey[contextKey] != nil, foldersByContextKey[contextKey] != nil {
            return
        }

        let requestCourseID = selectedCourseID
        let requestFolderID = selectedFolderID
        let requestContextKey = contextKey
        isLoadingFiles = true
        fileErrorsByContextKey[requestContextKey] = nil
        defer {
            if selectedCourseID == requestCourseID, activeFileFolderID(for: requestCourseID) == requestFolderID {
                isLoadingFiles = false
            }
        }

        do {
            async let loadedFolders: [FolderDTO] = {
                if let requestFolderID {
                    return try await repository.fetchFolderFolders(folderID: requestFolderID, offset: 0, limit: 1000)
                }
                return try await repository.fetchFolders(scope: .course(requestCourseID), offset: 0, limit: 1000)
            }()

            async let loadedFiles: [CourseFileRefDTO] = {
                if let requestFolderID {
                    return try await repository.fetchFolderFileRefs(folderID: requestFolderID, offset: 0, limit: 1000)
                }
                return try await repository.fetchFileRefs(scope: .course(requestCourseID), offset: 0, limit: 1000)
            }()

            let (folders, files) = try await (loadedFolders, loadedFiles)
            let sortedFolders = folders.sorted { lhs, rhs in
                let lhsName = nonEmpty(lhs.name) ?? lhs.id
                let rhsName = nonEmpty(rhs.name) ?? rhs.id
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
            let sortedFiles = files.sorted { lhs, rhs in
                let lhsDate = parseAPIDate(lhs.chdate) ?? parseAPIDate(lhs.mkdate) ?? .distantPast
                let rhsDate = parseAPIDate(rhs.chdate) ?? parseAPIDate(rhs.mkdate) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                let lhsName = nonEmpty(lhs.name) ?? lhs.id
                let rhsName = nonEmpty(rhs.name) ?? rhs.id
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

            if selectedCourseID == requestCourseID, activeFileFolderID(for: requestCourseID) == requestFolderID {
                foldersByContextKey[requestContextKey] = sortedFolders
                filesByContextKey[requestContextKey] = sortedFiles
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.files.id)
            }
        } catch {
            if selectedCourseID == requestCourseID, activeFileFolderID(for: requestCourseID) == requestFolderID {
                fileErrorsByContextKey[requestContextKey] = "Fehler beim Laden der Dateien/Ordner: \(error.localizedDescription)"
            }
        }
    }

    func loadChatsForSelectedSection(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.chat.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        if !force, chatsByCourseID[selectedCourseID] != nil {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingChats = true
        chatErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingChats = false
            }
        }

        do {
            let threads = try await repository.fetchCourseChatThreads(courseID: requestCourseID)
            if selectedCourseID == requestCourseID {
                chatsByCourseID[requestCourseID] = threads
                if let currentSelection = selectedChatThreadIDByCourseID[requestCourseID],
                   threads.contains(where: { $0.id == currentSelection }) {
                    selectedChatThreadIDByCourseID[requestCourseID] = currentSelection
                } else {
                    selectedChatThreadIDByCourseID[requestCourseID] = threads.first?.id
                }
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.chat.id)
            }
        } catch {
            if selectedCourseID == requestCourseID {
                chatErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Chat-Threads: \(error.localizedDescription)"
            }
        }
    }

    func loadChatMessagesForSelectedThread(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.chat.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        guard let selectedThreadID = selectedChatThreadIDByCourseID[selectedCourseID] else {
            return
        }
        if !force, chatMessagesByThreadID[selectedThreadID] != nil {
            return
        }
        guard !loadingChatThreadIDs.contains(selectedThreadID) else {
            return
        }

        let requestCourseID = selectedCourseID
        let requestThreadID = selectedThreadID
        loadingChatThreadIDs.insert(requestThreadID)
        chatMessageErrorsByThreadID[requestThreadID] = nil
        defer { loadingChatThreadIDs.remove(requestThreadID) }

        do {
            let postings = try await repository.fetchBlubberThreadComments(
                threadID: requestThreadID,
                offset: 0,
                limit: 1000
            )
            let sorted = postings.sorted { lhs, rhs in
                let lhsDate = parseAPIDate(lhs.discussionTime) ?? parseAPIDate(lhs.mkdate) ?? parseAPIDate(lhs.chdate) ?? .distantPast
                let rhsDate = parseAPIDate(rhs.discussionTime) ?? parseAPIDate(rhs.mkdate) ?? parseAPIDate(rhs.chdate) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
            await resolveDisplayNamesIfNeeded(for: sorted.compactMap(\.authorID))

            if selectedCourseID == requestCourseID,
               selectedChatThreadIDByCourseID[requestCourseID] == requestThreadID {
                chatMessagesByThreadID[requestThreadID] = sorted
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.chat.id)
            }
        } catch {
            if selectedCourseID == requestCourseID,
               selectedChatThreadIDByCourseID[requestCourseID] == requestThreadID {
                chatMessageErrorsByThreadID[requestThreadID] = "Fehler beim Laden des Chatfensters: \(error.localizedDescription)"
            }
        }
    }

    func loadWikisForSelectedSection(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.wiki.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        if !force, wikisByCourseID[selectedCourseID] != nil {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingWikis = true
        wikiErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingWikis = false
            }
        }

        do {
            let pages = try await repository.fetchCourseWikiPages(courseID: requestCourseID)
            if selectedCourseID == requestCourseID {
                wikisByCourseID[requestCourseID] = pages
                if let currentSelection = selectedWikiPageIDByCourseID[requestCourseID],
                   pages.contains(where: { $0.id == currentSelection }) {
                    selectedWikiPageIDByCourseID[requestCourseID] = currentSelection
                } else {
                    selectedWikiPageIDByCourseID[requestCourseID] = pages.first?.id
                }
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.wiki.id)
            }
        } catch {
            if selectedCourseID == requestCourseID {
                wikiErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Wiki-Seiten: \(error.localizedDescription)"
            }
        }
    }

    func loadParticipantsForSelectedSection(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.participants.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        if !force, participantsByCourseID[selectedCourseID] != nil {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingParticipants = true
        participantErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingParticipants = false
            }
        }

        do {
            let participants = try await repository.fetchCourseParticipants(courseID: requestCourseID)
            if selectedCourseID == requestCourseID {
                participantsByCourseID[requestCourseID] = participants
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.participants.id)
            }
        } catch {
            if selectedCourseID == requestCourseID {
                participantErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Teilnehmer: \(error.localizedDescription)"
            }
        }
    }

    func loadForumsForSelectedSection(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.forum.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        if !force, forumsByCourseID[selectedCourseID] != nil {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingForums = true
        forumErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingForums = false
            }
        }

        do {
            let categories = try await repository.fetchCourseForumCategories(
                courseID: requestCourseID,
                offset: 0,
                limit: 1000
            )

            let sorted = categories.sorted { lhs, rhs in
                let lhsPosition = lhs.position ?? Int.max
                let rhsPosition = rhs.position ?? Int.max
                if lhsPosition != rhsPosition {
                    return lhsPosition < rhsPosition
                }

                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }

            if selectedCourseID == requestCourseID {
                forumsByCourseID[requestCourseID] = sorted
                if let selectedID = selectedForumCategoryIDByCourseID[requestCourseID],
                   sorted.contains(where: { $0.id == selectedID }) {
                    selectedForumCategoryIDByCourseID[requestCourseID] = selectedID
                } else {
                    selectedForumCategoryIDByCourseID[requestCourseID] = sorted.first?.id
                }
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.forum.id)
            }
        } catch {
            if selectedCourseID == requestCourseID {
                forumErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Forum-Kategorien: \(error.localizedDescription)"
            }
        }
    }

    func loadForumEntriesForSelectedCategory(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.forum.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        guard let selectedCategoryID = selectedForumCategoryIDByCourseID[selectedCourseID] else {
            return
        }
        if !force, forumEntriesByCategoryID[selectedCategoryID] != nil {
            return
        }
        guard !loadingForumCategoryIDs.contains(selectedCategoryID) else {
            return
        }

        let requestCourseID = selectedCourseID
        let requestCategoryID = selectedCategoryID
        loadingForumCategoryIDs.insert(requestCategoryID)
        forumEntryErrorsByCategoryID[requestCategoryID] = nil
        defer { loadingForumCategoryIDs.remove(requestCategoryID) }

        do {
            let entries = try await repository.fetchForumCategoryEntries(
                categoryID: requestCategoryID,
                offset: 0,
                limit: 1000
            )

            let sorted = entries.sorted { lhs, rhs in
                let lhsArea = lhs.area ?? Int.max
                let rhsArea = rhs.area ?? Int.max
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            await resolveDisplayNamesIfNeeded(for: sorted.compactMap(\.authorID))

            if selectedCourseID == requestCourseID,
               selectedForumCategoryIDByCourseID[requestCourseID] == requestCategoryID {
                forumEntriesByCategoryID[requestCategoryID] = sorted
                if let selectedID = selectedForumEntryIDByCategoryID[requestCategoryID],
                   sorted.contains(where: { $0.id == selectedID }) {
                    selectedForumEntryIDByCategoryID[requestCategoryID] = selectedID
                } else {
                    selectedForumEntryIDByCategoryID[requestCategoryID] = sorted.first?.id
                }
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.forum.id)
            }
        } catch {
            if selectedCourseID == requestCourseID,
               selectedForumCategoryIDByCourseID[requestCourseID] == requestCategoryID {
                forumEntryErrorsByCategoryID[requestCategoryID] = "Fehler beim Laden der Forum-Themen: \(error.localizedDescription)"
            }
        }
    }

    func loadForumRepliesForSelectedEntry(force: Bool = false) async {
        guard selectedCourseDetailSectionID == CourseDetailSection.forum.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        guard let selectedCategoryID = selectedForumCategoryIDByCourseID[selectedCourseID] else {
            return
        }
        guard let selectedEntryID = selectedForumEntryIDByCategoryID[selectedCategoryID] else {
            return
        }
        if !force, forumRepliesByEntryID[selectedEntryID] != nil {
            return
        }
        guard !loadingForumEntryIDs.contains(selectedEntryID) else {
            return
        }

        let requestCourseID = selectedCourseID
        let requestCategoryID = selectedCategoryID
        let requestEntryID = selectedEntryID
        loadingForumEntryIDs.insert(requestEntryID)
        forumReplyErrorsByEntryID[requestEntryID] = nil
        defer { loadingForumEntryIDs.remove(requestEntryID) }

        do {
            let replies = try await repository.fetchForumEntryEntries(
                entryID: requestEntryID,
                offset: 0,
                limit: 1000
            )

            let sorted = replies.sorted { lhs, rhs in
                let lhsArea = lhs.area ?? Int.max
                let rhsArea = rhs.area ?? Int.max
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            await resolveDisplayNamesIfNeeded(for: sorted.compactMap(\.authorID))

            if selectedCourseID == requestCourseID,
               selectedForumCategoryIDByCourseID[requestCourseID] == requestCategoryID,
               selectedForumEntryIDByCategoryID[requestCategoryID] == requestEntryID {
                forumRepliesByEntryID[requestEntryID] = sorted
                markDetailSectionLoadedNow(courseID: requestCourseID, sectionID: CourseDetailSection.forum.id)
            }
        } catch {
            if selectedCourseID == requestCourseID,
               selectedForumCategoryIDByCourseID[requestCourseID] == requestCategoryID,
               selectedForumEntryIDByCategoryID[requestCategoryID] == requestEntryID {
                forumReplyErrorsByEntryID[requestEntryID] = "Fehler beim Laden der Antworten: \(error.localizedDescription)"
            }
        }
    }

    func forceReloadNewsForSelectedCourse() async {
        guard let courseID = selectedCourseID else { return }

        courseNewsByCourseID[courseID] = nil
        courseNewsErrorsByCourseID[courseID] = nil

        if let selectedNewsID = selectedNewsIDByCourseID[courseID] {
            newsCommentsByNewsID[selectedNewsID] = nil
            newsCommentErrorsByNewsID[selectedNewsID] = nil
        }

        await loadNewsForSelectedCourse(force: true)
        await loadNewsCommentsForSelectedNews(force: true)
    }

    func forceReloadAllDetailContent(for courseID: String) async {
        let contextPrefix = "\(courseID)::"
        let fileContextKeys = foldersByContextKey.keys.filter { $0.hasPrefix(contextPrefix) }

        let knownNewsIDs = Set((courseNewsByCourseID[courseID] ?? []).map(\.id))
        let selectedNewsID = selectedNewsIDByCourseID[courseID]
        let newsIDsToClear = selectedNewsID.map { knownNewsIDs.union([$0]) } ?? knownNewsIDs

        let knownThreadIDs = Set((chatsByCourseID[courseID] ?? []).map(\.id))
        let selectedThreadID = selectedChatThreadIDByCourseID[courseID]
        let threadIDsToClear = selectedThreadID.map { knownThreadIDs.union([$0]) } ?? knownThreadIDs

        var categoryIDsToClear = Set((forumsByCourseID[courseID] ?? []).map(\.id))
        if let selectedCategoryID = selectedForumCategoryIDByCourseID[courseID] {
            categoryIDsToClear.insert(selectedCategoryID)
        }

        var entryIDsToClear: Set<String> = []
        for categoryID in categoryIDsToClear {
            if let entries = forumEntriesByCategoryID[categoryID] {
                entryIDsToClear.formUnion(entries.map(\.id))
            }
            if let selectedEntryID = selectedForumEntryIDByCategoryID[categoryID] {
                entryIDsToClear.insert(selectedEntryID)
            }
        }

        for key in fileContextKeys {
            foldersByContextKey[key] = nil
            filesByContextKey[key] = nil
            fileErrorsByContextKey[key] = nil
        }
        fileFolderPathByCourseID[courseID] = []

        courseNewsByCourseID[courseID] = nil
        courseNewsErrorsByCourseID[courseID] = nil
        selectedNewsIDByCourseID[courseID] = nil
        for newsID in newsIDsToClear {
            newsCommentsByNewsID[newsID] = nil
            newsCommentErrorsByNewsID[newsID] = nil
        }

        chatsByCourseID[courseID] = nil
        chatErrorsByCourseID[courseID] = nil
        selectedChatThreadIDByCourseID[courseID] = nil
        for threadID in threadIDsToClear {
            chatMessagesByThreadID[threadID] = nil
            chatMessageErrorsByThreadID[threadID] = nil
        }

        wikisByCourseID[courseID] = nil
        wikiErrorsByCourseID[courseID] = nil
        selectedWikiPageIDByCourseID[courseID] = nil

        participantsByCourseID[courseID] = nil
        participantErrorsByCourseID[courseID] = nil

        forumsByCourseID[courseID] = nil
        forumErrorsByCourseID[courseID] = nil
        selectedForumCategoryIDByCourseID[courseID] = nil
        for categoryID in categoryIDsToClear {
            forumEntriesByCategoryID[categoryID] = nil
            forumEntryErrorsByCategoryID[categoryID] = nil
            selectedForumEntryIDByCategoryID[categoryID] = nil
        }
        for entryID in entryIDsToClear {
            forumRepliesByEntryID[entryID] = nil
            forumReplyErrorsByEntryID[entryID] = nil
        }

        await prefetchAllTabContentForCourse(courseID)
    }

    func forceReloadFilesForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }
        let contextKey = activeFileContextKey(for: courseID)

        foldersByContextKey[contextKey] = nil
        filesByContextKey[contextKey] = nil
        fileErrorsByContextKey[contextKey] = nil

        await loadFilesForSelectedSection(force: true)
    }

    func forceReloadChatsForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }

        chatsByCourseID[courseID] = nil
        chatErrorsByCourseID[courseID] = nil

        if let selectedThreadID = selectedChatThreadIDByCourseID[courseID] {
            chatMessagesByThreadID[selectedThreadID] = nil
            chatMessageErrorsByThreadID[selectedThreadID] = nil
        }

        await loadChatsForSelectedSection(force: true)
        await loadChatMessagesForSelectedThread(force: true)
    }

    func forceReloadWikisForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }

        wikisByCourseID[courseID] = nil
        wikiErrorsByCourseID[courseID] = nil

        await loadWikisForSelectedSection(force: true)
    }

    func forceReloadParticipantsForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }

        participantsByCourseID[courseID] = nil
        participantErrorsByCourseID[courseID] = nil

        await loadParticipantsForSelectedSection(force: true)
    }

    func forceReloadForumsForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }

        forumsByCourseID[courseID] = nil
        forumErrorsByCourseID[courseID] = nil

        if let selectedCategoryID = selectedForumCategoryIDByCourseID[courseID] {
            forumEntriesByCategoryID[selectedCategoryID] = nil
            forumEntryErrorsByCategoryID[selectedCategoryID] = nil
            if let selectedEntryID = selectedForumEntryIDByCategoryID[selectedCategoryID] {
                forumRepliesByEntryID[selectedEntryID] = nil
                forumReplyErrorsByEntryID[selectedEntryID] = nil
            }
        }

        await loadForumsForSelectedSection(force: true)
        await loadForumEntriesForSelectedCategory(force: true)
        await loadForumRepliesForSelectedEntry(force: true)
    }
}
