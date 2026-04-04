import SwiftUI

extension ContentView {
    var defaultCourseDetailSections: [CourseDetailSection] {
        [
            .description,
            .files,
            .chat,
            .wiki,
            .participants,
            .forum,
            .metadata
        ]
    }

    var visibleCourseDetailSections: [CourseDetailSection] {
        guard let selectedCourseID else { return defaultCourseDetailSections }
        guard let pages = wikisByCourseID[selectedCourseID] else { return defaultCourseDetailSections }
        if pages.isEmpty {
            return defaultCourseDetailSections.filter { $0.id != CourseDetailSection.wiki.id }
        }
        return defaultCourseDetailSections
    }

    var participantTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    var fileListTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let folderID = selectedCourseID
            .flatMap { activeFileFolderID(for: $0) }
            ?? "root"
        return "\(courseID):\(selectedCourseDetailSectionID):\(folderID)"
    }

    var chatListTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    var chatWindowTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let threadID = selectedCourseID
            .flatMap { selectedChatThreadIDByCourseID[$0] }
            ?? "none"
        return "\(courseID):\(selectedCourseDetailSectionID):\(threadID)"
    }

    var wikiListTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    var forumTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    var forumEntryTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let categoryID = selectedCourseID
            .flatMap { selectedForumCategoryIDByCourseID[$0] }
            ?? "none"
        return "\(courseID):\(selectedCourseDetailSectionID):\(categoryID)"
    }

    var forumReplyTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let categoryID = selectedCourseID
            .flatMap { selectedForumCategoryIDByCourseID[$0] }
            ?? "none"
        let entryID = selectedForumEntryIDByCategoryID[categoryID] ?? "none"
        return "\(courseID):\(selectedCourseDetailSectionID):\(categoryID):\(entryID)"
    }

    var newsTaskID: String {
        selectedCourseID ?? "none"
    }

    var newsCommentTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let newsID = selectedCourseID
            .flatMap { selectedNewsIDByCourseID[$0] }
            ?? "none"
        return "\(courseID):\(newsID)"
    }

    var semesterIDsSignature: String {
        semesterViewModel.semesters.map(\.id).joined(separator: ",")
    }

    var startScheduleTaskID: String {
        let dayKey = Self.scheduleDayFormatter.string(from: Date())
        return "\(selectedPage.rawValue):\(selectedSemesterID == nil ? "no-semester" : "semester"):\(dayKey)"
    }

    var semesterScheduleTaskID: String {
        "\(selectedSemesterID ?? "none"):\(selectedCourseID ?? "none")"
    }

    func isSelectedMenuPage(_ page: SidebarPage) -> Bool {
        selectedSemesterID == nil && selectedSidebarPage == page
    }

    func isSelectedSemester(_ semesterID: String) -> Bool {
        selectedSemesterID == semesterID
    }

    var currentSidebarNavigationState: SidebarNavigationState {
        SidebarNavigationState(
            page: selectedSidebarPage ?? .start,
            semesterID: selectedSemesterID,
            courseID: selectedCourseID
        )
    }

    var canGoBackInSidebarNavigation: Bool {
        !sidebarNavigationBackStack.isEmpty
    }

    var canGoForwardInSidebarNavigation: Bool {
        !sidebarNavigationForwardStack.isEmpty
    }

    func navigateToSidebarState(_ newState: SidebarNavigationState) {
        let currentState = currentSidebarNavigationState
        guard currentState != newState else { return }

        if !isRestoringSidebarNavigationState {
            sidebarNavigationBackStack.append(currentState)
            sidebarNavigationForwardStack.removeAll()
        }

        selectedSidebarPage = newState.page
        selectedSemesterID = newState.semesterID
        selectedCourseID = newState.courseID
    }

    func navigateToSidebarPage(_ page: SidebarPage) {
        navigateToSidebarState(
            SidebarNavigationState(page: page, semesterID: nil, courseID: nil)
        )
    }

    func selectSidebarSemester(_ semesterID: String) {
        navigateToSidebarState(
            SidebarNavigationState(page: selectedSidebarPage ?? .start, semesterID: semesterID, courseID: nil)
        )
    }

    func selectSidebarCourse(_ courseID: String) {
        navigateToSidebarState(
            SidebarNavigationState(page: selectedSidebarPage ?? .start, semesterID: selectedSemesterID, courseID: courseID)
        )
    }

    func goBackInSidebarNavigation() {
        guard let previousState = sidebarNavigationBackStack.popLast() else { return }
        sidebarNavigationForwardStack.append(currentSidebarNavigationState)
        isRestoringSidebarNavigationState = true
        selectedSidebarPage = previousState.page
        selectedSemesterID = previousState.semesterID
        selectedCourseID = previousState.courseID
        isRestoringSidebarNavigationState = false
    }

    func goForwardInSidebarNavigation() {
        guard let nextState = sidebarNavigationForwardStack.popLast() else { return }
        sidebarNavigationBackStack.append(currentSidebarNavigationState)
        isRestoringSidebarNavigationState = true
        selectedSidebarPage = nextState.page
        selectedSemesterID = nextState.semesterID
        selectedCourseID = nextState.courseID
        isRestoringSidebarNavigationState = false
    }

    func startScheduleRow(_ entry: ScheduleEntryDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(nonEmpty(entry.title) ?? "Termin \(entry.id)")
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Text(scheduleTimeLine(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isScheduleEntryNow(entry) {
                Text("Jetzt")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func semesterScheduleRow(_ event: EventDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(nonEmpty(event.title) ?? "Termin \(event.id)")
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Text(eventTimeLine(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let details = nonEmpty(event.details) {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func activeRowBackground(isActive: Bool) -> Color {
        isActive ? Color.accentColor.opacity(0.14) : .clear
    }

    func activeRowForeground(isActive: Bool) -> Color {
        isActive ? Color.accentColor : Color.primary
    }

    struct SidebarSelectionModifier: ViewModifier {
        let isActive: Bool

        func body(content: Content) -> some View {
            content
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    func pruneCourseOverviewCacheToKnownSemesters() {
        let knownSemesterIDs = Set(semesterViewModel.semesters.map(\.id))
        coursesBySemesterID = coursesBySemesterID.filter { knownSemesterIDs.contains($0.key) }
        coursePrefetchErrorsBySemesterID = coursePrefetchErrorsBySemesterID.filter { knownSemesterIDs.contains($0.key) }
        prefetchingSemesterCourseIDs = prefetchingSemesterCourseIDs.intersection(knownSemesterIDs)
    }

    func handleCachesClearedNotification() {
        coursesBySemesterID.removeAll()
        coursePrefetchErrorsBySemesterID.removeAll()
        prefetchingSemesterCourseIDs.removeAll()
        courses = []
        selectedCourseID = nil
        courseStatusMessage = "Lokaler Cache geleert - Kursdaten werden neu geladen."

        semesterScheduleEventsBySemesterID.removeAll()
        semesterScheduleErrorsBySemesterID.removeAll()
        semesterScheduleLoadedAtBySemesterID.removeAll()
        loadingSemesterScheduleIDs.removeAll()

        sharedCoursesByUserID.removeAll()
        sharedCoursesUpdatedAt = nil
        sharedCoursesNamespaceKey = nil
        sharedCoursesError = nil

        semesterViewModel.loadSemesters()

        if selectedPage == .benutzer, selectedSemesterID == nil {
            Task {
                await loadSharedCoursesFromLocalCacheIfNeeded()
            }
        }

        if selectedSemesterID != nil {
            Task {
                await loadCoursesForSelectedSemester()
            }
        }
    }

    func prefetchCourseOverviewsForLoadedSemesters() async {
        guard !semesterViewModel.semesters.isEmpty else { return }
        for semester in semesterViewModel.semesters {
            await prefetchCourseOverview(for: semester.id)
        }
    }

    func prefetchCourseOverview(for semesterID: String) async {
        guard coursesBySemesterID[semesterID] == nil else { return }
        guard !prefetchingSemesterCourseIDs.contains(semesterID) else { return }

        prefetchingSemesterCourseIDs.insert(semesterID)
        defer { prefetchingSemesterCourseIDs.remove(semesterID) }

        do {
            let result = try await repository.loadCoursesStaleWhileRevalidate(for: semesterID) { refreshed in
                let refreshedSorted = sortCoursesForDisplay(refreshed)
                coursesBySemesterID[semesterID] = refreshedSorted
                if selectedSemesterID == semesterID {
                    courses = refreshedSorted
                    courseStatusMessage = refreshedSorted.isEmpty
                        ? "Keine Kurse gefunden"
                        : "\(refreshedSorted.count) Kurse geladen"
                }
                coursePrefetchErrorsBySemesterID[semesterID] = nil
            }
            let sorted = sortCoursesForDisplay(result.courses)
            coursesBySemesterID[semesterID] = sorted
            coursePrefetchErrorsBySemesterID[semesterID] = nil
        } catch {
            coursePrefetchErrorsBySemesterID[semesterID] = "Fehler beim Vorladen der Kurse: \(error.localizedDescription)"
        }
    }

    func loadCoursesForSelectedSemester() async {
        guard let selectedSemesterID else {
            courses = []
            selectedCourseID = nil
            courseStatusMessage = "Waehle ein Semester aus"
            return
        }

        isLoadingCourses = true
        selectedCourseID = nil
        defer { isLoadingCourses = false }

        if let cached = coursesBySemesterID[selectedSemesterID] {
            courses = cached
            courseStatusMessage = cached.isEmpty ? "Keine Kurse gefunden" : "\(cached.count) Kurse geladen"
            return
        }

        do {
            let result = try await repository.loadCoursesStaleWhileRevalidate(for: selectedSemesterID) { refreshed in
                let refreshedSorted = sortCoursesForDisplay(refreshed)
                coursesBySemesterID[selectedSemesterID] = refreshedSorted
                courses = refreshedSorted
                courseStatusMessage = refreshedSorted.isEmpty
                    ? "Keine Kurse gefunden"
                    : "\(refreshedSorted.count) Kurse geladen"
            }
            let sorted = sortCoursesForDisplay(result.courses)
            coursesBySemesterID[selectedSemesterID] = sorted
            courses = sorted
            if result.source == .cache {
                courseStatusMessage = sorted.isEmpty
                    ? "Keine Kurse im lokalen Cache"
                    : "\(sorted.count) Kurse aus lokalem Cache geladen"
            } else {
                courseStatusMessage = sorted.isEmpty ? "Keine Kurse gefunden" : "\(sorted.count) Kurse geladen"
            }
        } catch {
            courses = []
            courseStatusMessage = "Fehler beim Laden der Kurse: \(error.localizedDescription)"
        }
    }

    func sortCoursesForDisplay(_ courses: [CourseDTO]) -> [CourseDTO] {
        courses.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func loadStartScheduleIfNeeded() async {
        guard selectedSemesterID == nil, selectedPage == .start else { return }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        if let loadedDate = startScheduleLoadedDate, calendar.isDate(loadedDate, inSameDayAs: todayStart) {
            return
        }

        await loadStartSchedule(force: false)
    }

    func loadStartSchedule(force: Bool) async {
        guard selectedSemesterID == nil, selectedPage == .start else { return }
        if isLoadingStartSchedule {
            return
        }
        if !force, !startScheduleEntries.isEmpty {
            return
        }

        isLoadingStartSchedule = true
        startScheduleError = nil
        defer { isLoadingStartSchedule = false }

        do {
            let me = try await repository.fetchMe()
            let calendar = Calendar.current
            let now = Date()
            let todayStart = calendar.startOfDay(for: now)
            let dayTimestamp = Int(todayStart.timeIntervalSince1970)
            let allEntries = try await repository.fetchUserSchedule(userID: me.id, timestamp: dayTimestamp)

            let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
            let entriesToday = allEntries.filter { entry in
                guard let start = parseAPIDate(entry.start) else { return false }
                return start >= todayStart && start < todayEnd
            }

            startScheduleEntries = entriesToday.sorted { lhs, rhs in
                let lhsStart = parseAPIDate(lhs.start) ?? .distantFuture
                let rhsStart = parseAPIDate(rhs.start) ?? .distantFuture
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            startScheduleLoadedDate = now
        } catch {
            startScheduleError = "Fehler beim Laden des Stundenplans: \(error.localizedDescription)"
            startScheduleEntries = []
        }
    }

    func loadSemesterScheduleIfNeeded() async {
        guard selectedCourseID == nil else { return }
        guard let semester = selectedSemester else { return }
        guard semesterScheduleEventsBySemesterID[semester.id] == nil else { return }
        await loadSemesterSchedule(for: semester, force: false)
    }

    func loadSemesterSchedule(for semester: SemesterDTO, force: Bool) async {
        let semesterID = semester.id

        if loadingSemesterScheduleIDs.contains(semesterID) {
            return
        }
        if !force, semesterScheduleEventsBySemesterID[semesterID] != nil {
            return
        }

        loadingSemesterScheduleIDs.insert(semesterID)
        semesterScheduleErrorsBySemesterID[semesterID] = nil
        defer { loadingSemesterScheduleIDs.remove(semesterID) }

        do {
            let semesterCourses: [CourseDTO]
            if selectedSemesterID == semesterID, !courses.isEmpty {
                semesterCourses = courses
            } else {
                semesterCourses = try await repository.fetchCourses(for: semesterID)
            }

            if semesterCourses.isEmpty {
                semesterScheduleEventsBySemesterID[semesterID] = []
                semesterScheduleLoadedAtBySemesterID[semesterID] = Date()
                return
            }

            let allEvents: [EventDTO] = try await withThrowingTaskGroup(of: [EventDTO].self) { group in
                for course in semesterCourses {
                    group.addTask {
                        try await repository.fetchCourseEvents(courseID: course.id, offset: 0, limit: 1000)
                    }
                }

                var collected: [EventDTO] = []
                for try await events in group {
                    collected.append(contentsOf: events)
                }
                return collected
            }

            let filtered = filterEventsToSemester(allEvents, semester: semester)
            let deduplicated = deduplicatedEvents(filtered)
            let sorted = deduplicated.sorted { lhs, rhs in
                let lhsStart = parseAPIDate(lhs.start) ?? .distantFuture
                let rhsStart = parseAPIDate(rhs.start) ?? .distantFuture
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }

            semesterScheduleEventsBySemesterID[semesterID] = sorted
            semesterScheduleLoadedAtBySemesterID[semesterID] = Date()
        } catch {
            semesterScheduleEventsBySemesterID[semesterID] = []
            semesterScheduleErrorsBySemesterID[semesterID] = "Fehler beim Laden des Semester-Stundenplans: \(error.localizedDescription)"
        }
    }

    func loadCourseDetailForSelectedCourse() async {
        guard let selectedCourseID else {
            return
        }

        selectedCourseDetailSectionID = CourseDetailSection.description.id
        fileFolderPathByCourseID[selectedCourseID] = []
        selectedChatThreadIDByCourseID[selectedCourseID] = nil
        selectedWikiPageIDByCourseID[selectedCourseID] = nil
        selectedNewsIDByCourseID[selectedCourseID] = nil
        selectedForumCategoryIDByCourseID[selectedCourseID] = nil
        isLoadingCourseDetail = true
        defer { isLoadingCourseDetail = false }

        do {
            let detailedCourse = try await repository.fetchCourse(id: selectedCourseID)
            if let index = courses.firstIndex(where: { $0.id == selectedCourseID }) {
                courses[index] = detailedCourse
            }
            if let cachedThreads = chatsByCourseID[selectedCourseID], !cachedThreads.isEmpty {
                selectedChatThreadIDByCourseID[selectedCourseID] = cachedThreads.first?.id
            }
            await preloadWikiAvailability(for: selectedCourseID)
            Task(priority: .utility) {
                await prefetchAllTabContentForCourse(selectedCourseID)
            }
        } catch {
            AppLogger.error("Failed to load course detail: \(error.localizedDescription)")
            courseStatusMessage = "Fehler beim Laden der Kursdetails: \(error.localizedDescription)"
        }
    }

    func prefetchAllTabContentForCourse(_ courseID: String) async {
        guard !prefetchingCourseIDs.contains(courseID) else {
            return
        }
        prefetchingCourseIDs.insert(courseID)
        defer { prefetchingCourseIDs.remove(courseID) }

        async let newsTask: Void = prefetchNewsContent(for: courseID)
        async let filesTask: Void = prefetchRootFilesContent(for: courseID)
        async let chatTask: Void = prefetchChatContent(for: courseID)
        async let wikiTask: Void = prefetchWikiContent(for: courseID)
        async let participantTask: Void = prefetchParticipantContent(for: courseID)
        async let forumTask: Void = prefetchForumContent(for: courseID)

        _ = await (newsTask, filesTask, chatTask, wikiTask, participantTask, forumTask)
    }

    func prefetchNewsContent(for courseID: String) async {
        if courseNewsByCourseID[courseID] == nil {
            do {
                let newsItems = try await repository.fetchCourseNews(courseID: courseID, offset: 0, limit: 100)
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

                courseNewsByCourseID[courseID] = sorted
                courseNewsErrorsByCourseID[courseID] = nil
                if let selectedID = selectedNewsIDByCourseID[courseID],
                   sorted.contains(where: { $0.id == selectedID }) {
                    selectedNewsIDByCourseID[courseID] = selectedID
                } else {
                    selectedNewsIDByCourseID[courseID] = sorted.first?.id
                }
                markDetailSectionLoadedNow(courseID: courseID, sectionID: "news")
            } catch {
                courseNewsErrorsByCourseID[courseID] = "Fehler beim Laden der Veranstaltungsnews: \(error.localizedDescription)"
            }
        }

        guard let newsID = selectedNewsIDByCourseID[courseID] else {
            return
        }
        guard newsCommentsByNewsID[newsID] == nil else {
            return
        }

        do {
            let comments = try await repository.fetchNewsComments(newsID: newsID, offset: 0, limit: 1000)
            let sorted = comments.sorted { lhs, rhs in
                lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
            newsCommentsByNewsID[newsID] = sorted
            newsCommentErrorsByNewsID[newsID] = nil
            markDetailSectionLoadedNow(courseID: courseID, sectionID: "news")
        } catch {
            newsCommentErrorsByNewsID[newsID] = "Fehler beim Laden der News-Kommentare: \(error.localizedDescription)"
        }
    }

    func prefetchRootFilesContent(for courseID: String) async {
        let contextKey = fileContextKey(courseID: courseID, folderID: nil)
        if filesByContextKey[contextKey] != nil, foldersByContextKey[contextKey] != nil {
            return
        }

        do {
            async let loadedFolders = repository.fetchFolders(scope: .course(courseID), offset: 0, limit: 1000)
            async let loadedFiles = repository.fetchFileRefs(scope: .course(courseID), offset: 0, limit: 1000)
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

            foldersByContextKey[contextKey] = sortedFolders
            filesByContextKey[contextKey] = sortedFiles
            fileErrorsByContextKey[contextKey] = nil
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.files.id)
        } catch {
            fileErrorsByContextKey[contextKey] = "Fehler beim Laden der Dateien/Ordner: \(error.localizedDescription)"
        }
    }

    func prefetchChatContent(for courseID: String) async {
        if chatsByCourseID[courseID] == nil {
            do {
                let threads = try await repository.fetchCourseChatThreads(courseID: courseID)
                chatsByCourseID[courseID] = threads
                chatErrorsByCourseID[courseID] = nil
                if let currentSelection = selectedChatThreadIDByCourseID[courseID],
                   threads.contains(where: { $0.id == currentSelection }) {
                    selectedChatThreadIDByCourseID[courseID] = currentSelection
                } else {
                    selectedChatThreadIDByCourseID[courseID] = threads.first?.id
                }
                markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.chat.id)
            } catch {
                chatErrorsByCourseID[courseID] = "Fehler beim Laden der Chat-Threads: \(error.localizedDescription)"
            }
        }

        guard let threadID = selectedChatThreadIDByCourseID[courseID] else {
            return
        }
        guard chatMessagesByThreadID[threadID] == nil else {
            return
        }

        do {
            let postings = try await repository.fetchBlubberThreadComments(threadID: threadID, offset: 0, limit: 1000)
            let sorted = postings.sorted { lhs, rhs in
                let lhsDate = parseAPIDate(lhs.discussionTime) ?? parseAPIDate(lhs.mkdate) ?? parseAPIDate(lhs.chdate) ?? .distantPast
                let rhsDate = parseAPIDate(rhs.discussionTime) ?? parseAPIDate(rhs.mkdate) ?? parseAPIDate(rhs.chdate) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
            await resolveDisplayNamesIfNeeded(for: sorted.compactMap(\.authorID))
            chatMessagesByThreadID[threadID] = sorted
            chatMessageErrorsByThreadID[threadID] = nil
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.chat.id)
        } catch {
            chatMessageErrorsByThreadID[threadID] = "Fehler beim Laden des Chatfensters: \(error.localizedDescription)"
        }
    }

    func prefetchWikiContent(for courseID: String) async {
        guard wikisByCourseID[courseID] == nil else {
            return
        }

        do {
            let pages = try await repository.fetchCourseWikiPages(courseID: courseID)
            wikisByCourseID[courseID] = pages
            wikiErrorsByCourseID[courseID] = nil
            if let currentSelection = selectedWikiPageIDByCourseID[courseID],
               pages.contains(where: { $0.id == currentSelection }) {
                selectedWikiPageIDByCourseID[courseID] = currentSelection
            } else {
                selectedWikiPageIDByCourseID[courseID] = pages.first?.id
            }
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.wiki.id)
        } catch {
            wikiErrorsByCourseID[courseID] = "Fehler beim Laden der Wiki-Seiten: \(error.localizedDescription)"
        }
    }

    func prefetchParticipantContent(for courseID: String) async {
        guard participantsByCourseID[courseID] == nil else {
            return
        }

        do {
            let participants = try await repository.fetchCourseParticipants(courseID: courseID)
            participantsByCourseID[courseID] = participants
            participantErrorsByCourseID[courseID] = nil
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.participants.id)
        } catch {
            participantErrorsByCourseID[courseID] = "Fehler beim Laden der Teilnehmer: \(error.localizedDescription)"
        }
    }

    func prefetchForumContent(for courseID: String) async {
        if forumsByCourseID[courseID] == nil {
            do {
                let categories = try await repository.fetchCourseForumCategories(courseID: courseID, offset: 0, limit: 1000)
                let sortedCategories = categories.sorted { lhs, rhs in
                    let lhsPosition = lhs.position ?? Int.max
                    let rhsPosition = rhs.position ?? Int.max
                    if lhsPosition != rhsPosition {
                        return lhsPosition < rhsPosition
                    }
                    let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                    let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                    return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
                }

                forumsByCourseID[courseID] = sortedCategories
                forumErrorsByCourseID[courseID] = nil
                if let selectedID = selectedForumCategoryIDByCourseID[courseID],
                   sortedCategories.contains(where: { $0.id == selectedID }) {
                    selectedForumCategoryIDByCourseID[courseID] = selectedID
                } else {
                    selectedForumCategoryIDByCourseID[courseID] = sortedCategories.first?.id
                }
                markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.forum.id)
            } catch {
                forumErrorsByCourseID[courseID] = "Fehler beim Laden der Forum-Kategorien: \(error.localizedDescription)"
            }
        }

        guard let categoryID = selectedForumCategoryIDByCourseID[courseID] else {
            return
        }
        if forumEntriesByCategoryID[categoryID] == nil {
            do {
                let entries = try await repository.fetchForumCategoryEntries(categoryID: categoryID, offset: 0, limit: 1000)
                let sortedEntries = entries.sorted { lhs, rhs in
                    let lhsArea = lhs.area ?? Int.max
                    let rhsArea = rhs.area ?? Int.max
                    if lhsArea != rhsArea {
                        return lhsArea < rhsArea
                    }
                    let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                    let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                    return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
                }
                await resolveDisplayNamesIfNeeded(for: sortedEntries.compactMap(\.authorID))
                forumEntriesByCategoryID[categoryID] = sortedEntries
                forumEntryErrorsByCategoryID[categoryID] = nil
                if let selectedID = selectedForumEntryIDByCategoryID[categoryID],
                   sortedEntries.contains(where: { $0.id == selectedID }) {
                    selectedForumEntryIDByCategoryID[categoryID] = selectedID
                } else {
                    selectedForumEntryIDByCategoryID[categoryID] = sortedEntries.first?.id
                }
                markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.forum.id)
            } catch {
                forumEntryErrorsByCategoryID[categoryID] = "Fehler beim Laden der Forum-Themen: \(error.localizedDescription)"
            }
        }

        guard let entryID = selectedForumEntryIDByCategoryID[categoryID] else {
            return
        }
        guard forumRepliesByEntryID[entryID] == nil else {
            return
        }

        do {
            let replies = try await repository.fetchForumEntryEntries(entryID: entryID, offset: 0, limit: 1000)
            let sortedReplies = replies.sorted { lhs, rhs in
                let lhsArea = lhs.area ?? Int.max
                let rhsArea = rhs.area ?? Int.max
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            await resolveDisplayNamesIfNeeded(for: sortedReplies.compactMap(\.authorID))
            forumRepliesByEntryID[entryID] = sortedReplies
            forumReplyErrorsByEntryID[entryID] = nil
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.forum.id)
        } catch {
            forumReplyErrorsByEntryID[entryID] = "Fehler beim Laden der Forum-Antworten: \(error.localizedDescription)"
        }
    }
}
