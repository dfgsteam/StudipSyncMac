import AppKit
import QuickLookUI
import SwiftUI

struct ContentView: View {
    private enum SidebarPage: String, CaseIterable, Hashable, Identifiable {
        case start
        case benutzer
        case einrichtungen
        case platzhalter

        var id: String { rawValue }

        var title: String {
            switch self {
            case .start: return "Start"
            case .benutzer: return "Benutzer"
            case .einrichtungen: return "Einrichtungen"
            case .platzhalter: return "Platzhalter"
            }
        }

        var systemImage: String {
            switch self {
            case .start: return "house"
            case .benutzer: return "person.2"
            case .einrichtungen: return "building.2"
            case .platzhalter: return "square.dashed"
            }
        }
    }

    private struct CourseDetailSection: Identifiable, Hashable {
        let id: String
        let title: String
        let systemImage: String

        static let description = CourseDetailSection(id: "description", title: "Beschreibung", systemImage: "text.alignleft")
        static let metadata = CourseDetailSection(id: "metadata", title: "Metadaten", systemImage: "square.text.square")
        static let files = CourseDetailSection(id: "files", title: "Dateien", systemImage: "folder")
        static let chat = CourseDetailSection(id: "chat", title: "Chat", systemImage: "bubble.left.and.bubble.right")
        static let wiki = CourseDetailSection(id: "wiki", title: "Wiki", systemImage: "book.pages")
        static let participants = CourseDetailSection(id: "participants", title: "Teilnehmer", systemImage: "person.2")
        static let forum = CourseDetailSection(id: "forum", title: "Forum", systemImage: "list.bullet.rectangle")
    }

    private struct QuickLookPreviewFile: Identifiable {
        let id: String
        let title: String
        let url: URL
    }

    let statusController: MenuBarStatusController
    let syncScheduler: SyncScheduler
    let semesterSelectionStore: SemesterSelectionStore
    let repository: StudIPResourceRepository
    let debugWindowState: DebugWindowState

    @Environment(\.openWindow) private var openWindow

    @State private var semesterViewModel: SemesterListViewModel
    @State private var selectedSidebarPage: SidebarPage? = .start
    @State private var selectedSemesterID: String?
    @State private var selectedCourseID: String?
    @State private var startScheduleEntries: [ScheduleEntryDTO] = []
    @State private var startScheduleError: String?
    @State private var isLoadingStartSchedule = false
    @State private var startScheduleLoadedDate: Date?
    @State private var semesterScheduleEventsBySemesterID: [String: [EventDTO]] = [:]
    @State private var semesterScheduleErrorsBySemesterID: [String: String] = [:]
    @State private var loadingSemesterScheduleIDs: Set<String> = []
    @State private var semesterScheduleLoadedAtBySemesterID: [String: Date] = [:]
    @State private var coursesBySemesterID: [String: [CourseDTO]] = [:]
    @State private var prefetchingSemesterCourseIDs: Set<String> = []
    @State private var coursePrefetchErrorsBySemesterID: [String: String] = [:]
    @State private var courses: [CourseDTO] = []
    @State private var isLoadingCourses = false
    @State private var isLoadingCourseDetail = false
    @State private var courseStatusMessage = "Waehle ein Semester aus"
    @State private var selectedCourseDetailSectionID = CourseDetailSection.description.id
    @State private var foldersByContextKey: [String: [FolderDTO]] = [:]
    @State private var filesByContextKey: [String: [CourseFileRefDTO]] = [:]
    @State private var fileErrorsByContextKey: [String: String] = [:]
    @State private var fileFolderPathByCourseID: [String: [FolderDTO]] = [:]
    @State private var downloadingFileIDs: Set<String> = []
    @State private var fileDownloadErrorsByFileID: [String: String] = [:]
    @State private var previewingFileIDs: Set<String> = []
    @State private var filePreviewErrorsByFileID: [String: String] = [:]
    @State private var selectedQuickLookFile: QuickLookPreviewFile?
    @State private var isLoadingFiles = false
    @State private var chatsByCourseID: [String: [StudIPResourceRepository.CourseChatThread]] = [:]
    @State private var chatErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingChats = false
    @State private var selectedChatThreadIDByCourseID: [String: String] = [:]
    @State private var chatMessagesByThreadID: [String: [BlubberPostingDTO]] = [:]
    @State private var chatMessageErrorsByThreadID: [String: String] = [:]
    @State private var loadingChatThreadIDs: Set<String> = []
    @State private var wikisByCourseID: [String: [StudIPResourceRepository.CourseWikiPage]] = [:]
    @State private var wikiErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingWikis = false
    @State private var selectedWikiPageIDByCourseID: [String: String] = [:]
    @State private var participantsByCourseID: [String: [StudIPResourceRepository.CourseParticipant]] = [:]
    @State private var participantErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingParticipants = false
    @State private var courseNewsByCourseID: [String: [NewsDTO]] = [:]
    @State private var courseNewsErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingCourseNews = false
    @State private var selectedNewsIDByCourseID: [String: String] = [:]
    @State private var newsCommentsByNewsID: [String: [NewsCommentDTO]] = [:]
    @State private var newsCommentErrorsByNewsID: [String: String] = [:]
    @State private var loadingNewsCommentIDs: Set<String> = []
    @State private var forumsByCourseID: [String: [StudIPResourceRepository.CourseForumCategory]] = [:]
    @State private var forumErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingForums = false
    @State private var selectedForumCategoryIDByCourseID: [String: String] = [:]
    @State private var forumEntriesByCategoryID: [String: [ForumEntryDTO]] = [:]
    @State private var forumEntryErrorsByCategoryID: [String: String] = [:]
    @State private var loadingForumCategoryIDs: Set<String> = []
    @State private var selectedForumEntryIDByCategoryID: [String: String] = [:]
    @State private var forumRepliesByEntryID: [String: [ForumEntryDTO]] = [:]
    @State private var forumReplyErrorsByEntryID: [String: String] = [:]
    @State private var loadingForumEntryIDs: Set<String> = []
    @State private var userDisplayNameByID: [String: String] = [:]
    @State private var loadingUserNameIDs: Set<String> = []
    @State private var prefetchingCourseIDs: Set<String> = []
    @State private var detailSearchTextBySectionID: [String: String] = [:]
    @State private var detailSectionLoadedAtByKey: [String: Date] = [:]
    @State private var selectedParticipantForInfo: StudIPResourceRepository.CourseParticipant?

    init(
        statusController: MenuBarStatusController,
        syncScheduler: SyncScheduler,
        semesterSelectionStore: SemesterSelectionStore,
        repository: StudIPResourceRepository,
        debugWindowState: DebugWindowState
    ) {
        self.statusController = statusController
        self.syncScheduler = syncScheduler
        self.semesterSelectionStore = semesterSelectionStore
        self.repository = repository
        self.debugWindowState = debugWindowState
        self._semesterViewModel = State(initialValue: SemesterListViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if selectedSemesterID == nil {
                NavigationSplitView {
                    pagesSidebar
                } detail: {
                    detailForSelectedPage
                }
            } else {
                NavigationSplitView {
                    pagesSidebar
                } content: {
                    coursesColumn
                } detail: {
                    detailColumn
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 560)
        .task {
            if semesterViewModel.semesters.isEmpty {
                semesterViewModel.loadSemesters()
            }
        }
        .task(id: selectedSemesterID) {
            debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
            await loadCoursesForSelectedSemester()
        }
        .task(id: selectedCourseID) {
            debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
            await loadCourseDetailForSelectedCourse()
        }
        .task(id: newsTaskID) {
            await loadNewsForSelectedCourse()
        }
        .task(id: newsCommentTaskID) {
            await loadNewsCommentsForSelectedNews()
        }
        .task(id: fileListTaskID) {
            await loadFilesForSelectedSection()
        }
        .task(id: chatListTaskID) {
            await loadChatsForSelectedSection()
        }
        .task(id: chatWindowTaskID) {
            await loadChatMessagesForSelectedThread()
        }
        .task(id: wikiListTaskID) {
            await loadWikisForSelectedSection()
        }
        .task(id: participantTaskID) {
            await loadParticipantsForSelectedSection()
        }
        .task(id: forumTaskID) {
            await loadForumsForSelectedSection()
        }
        .task(id: forumEntryTaskID) {
            await loadForumEntriesForSelectedCategory()
        }
        .task(id: forumReplyTaskID) {
            await loadForumRepliesForSelectedEntry()
        }
        .task(id: semesterIDsSignature) {
            selectFirstSemesterIfNeeded()
            pruneCourseOverviewCacheToKnownSemesters()
            await prefetchCourseOverviewsForLoadedSemesters()
        }
        .task(id: startScheduleTaskID) {
            await loadStartScheduleIfNeeded()
        }
        .task(id: semesterScheduleTaskID) {
            await loadSemesterScheduleIfNeeded()
        }
        .sheet(item: $selectedParticipantForInfo) { participant in
            participantInfoSheet(for: participant)
        }
        .sheet(item: $selectedQuickLookFile) { previewFile in
            quickLookSheet(for: previewFile)
        }
    }

    private var selectedPage: SidebarPage {
        selectedSidebarPage ?? .start
    }

    private var pagesSidebar: some View {
        VStack(spacing: 0) {
            List(SidebarPage.allCases) { page in
                Button {
                    selectedSidebarPage = page
                    selectedSemesterID = nil
                    selectedCourseID = nil
                } label: {
                    Label(page.title, systemImage: page.systemImage)
                        .font(.body.weight(.medium))
                        .modifier(SidebarSelectionModifier(isActive: isSelectedMenuPage(page)))
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
            .frame(minHeight: 180, maxHeight: 220)

            Divider()
            semesterSidebar
        }
    }

    private var contentForSelectedPage: some View {
        Group {
            if selectedSemesterID != nil {
                coursesColumn
            } else {
                switch selectedPage {
                case .start:
                    startContentColumn
                case .benutzer:
                    benutzerContentColumn
                case .einrichtungen:
                    einrichtungenContentColumn
                case .platzhalter:
                    platzhalterContentColumn
                }
            }
        }
    }

    private var detailForSelectedPage: some View {
        Group {
            if selectedSemesterID != nil {
                detailColumn
            } else {
                switch selectedPage {
                case .start:
                    startDetailColumn
                case .benutzer:
                    benutzerDetailColumn
                case .einrichtungen:
                    einrichtungenDetailColumn
                case .platzhalter:
                    platzhalterDetailColumn
                }
            }
        }
    }

    private var semesterSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Semester")
                    .font(.headline)
                Spacer()
                Button("Neu laden") {
                    semesterViewModel.loadSemesters()
                }
                .disabled(semesterViewModel.isLoading)
            }

            List(semesterViewModel.semesters) { semester in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(semester.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help("Semester-ID: \(semester.id)")
                    }
                    Spacer()
                    Image(systemName: semesterSelectionStore.isActive(semesterID: semester.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(semesterSelectionStore.isActive(semesterID: semester.id) ? .green : .secondary)
                }
                .modifier(SidebarSelectionModifier(isActive: isSelectedSemester(semester.id)))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSemesterID = semester.id
                    selectedCourseID = nil
                }
                .contextMenu {
                    Button(semesterSelectionStore.isActive(semesterID: semester.id) ? "Fuer Sync deaktivieren" : "Fuer Sync aktivieren") {
                        semesterSelectionStore.setActive(!semesterSelectionStore.isActive(semesterID: semester.id), semesterID: semester.id)
                    }
                }
            }

            Text(semesterViewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var startContentColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                startStatsGrid
                startScheduleWidget(limit: 5)
                startSemesterOverviewWidget
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private var startDetailColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StudIP Dashboard")
                        .font(.title2.weight(.bold))
                    Text(startSubtitleText)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: statusController.syncState.symbolName)
                    Text(statusController.syncState.statusText)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    startStatsGrid
                    startScheduleWidget(limit: 8)
                    startSemesterOverviewWidget
                    startQuickActionsWidget
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            detailActions
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    private var benutzerContentColumn: some View {
        staticMenuContentColumn(
            title: "Benutzer",
            subtitle: "Statische Testseite: Inhaltsbereich"
        )
    }

    private var benutzerDetailColumn: some View {
        staticMenuDetailColumn(
            title: "Benutzer",
            subtitle: "Statische Testseite: Detailbereich"
        )
    }

    private var einrichtungenContentColumn: some View {
        staticMenuContentColumn(
            title: "Einrichtungen",
            subtitle: "Statische Testseite: Inhaltsbereich"
        )
    }

    private var einrichtungenDetailColumn: some View {
        staticMenuDetailColumn(
            title: "Einrichtungen",
            subtitle: "Statische Testseite: Detailbereich"
        )
    }

    private var platzhalterContentColumn: some View {
        staticMenuContentColumn(
            title: "Platzhalter",
            subtitle: "Diese Seite ist ein Platzhalter vor dem Veranstaltungsbereich."
        )
    }

    private var platzhalterDetailColumn: some View {
        staticMenuDetailColumn(
            title: "Platzhalter",
            subtitle: "Statische Testseite: Detailbereich"
        )
    }

    private func staticMenuContentColumn(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            GroupBox("Testinhalt") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subtitle)
                    Text("Diese Seite ist bewusst statisch und dient als Platzhalter.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(12)
    }

    private func staticMenuDetailColumn(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
            GroupBox("Testdetails") {
                Text("Statischer Detailbereich fuer UI-Tests.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            Divider()
            detailActions
        }
        .padding(24)
    }

    private var startSubtitleText: String {
        if let current = currentSemesterForDashboard {
            return "Aktives Semester: \(current.title)"
        }
        return "Uebersicht ueber Synchronisation, Semester und Termine"
    }

    private var currentSemesterForDashboard: SemesterDTO? {
        semesterViewModel.semesters.first(where: { $0.isCurrent == true }) ?? semesterViewModel.semesters.first
    }

    private var visibleSemesterCount: Int {
        semesterViewModel.semesters.filter { $0.visible != false }.count
    }

    private var cachedCourseCount: Int {
        coursesBySemesterID.values.reduce(0) { partial, items in partial + items.count }
    }

    private var upcomingStartEntries: [ScheduleEntryDTO] {
        let now = Date()
        let upcoming = startScheduleEntries.filter { entry in
            guard let start = parseAPIDate(entry.start) else { return false }
            return start >= now
        }
        return upcoming.isEmpty ? startScheduleEntries : upcoming
    }

    private var startStatsGrid: some View {
        let columns = [
            GridItem(.flexible(minimum: 150)),
            GridItem(.flexible(minimum: 150))
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            dashboardStatTile(
                title: "Semester",
                value: "\(semesterViewModel.semesters.count)",
                systemImage: "graduationcap"
            )
            dashboardStatTile(
                title: "Aktiv fuer Sync",
                value: "\(semesterSelectionStore.activeSemesterIDs.count)",
                systemImage: "checkmark.seal",
                footnote: "\(visibleSemesterCount) sichtbar"
            )
            dashboardStatTile(
                title: "Kurse im Cache",
                value: "\(cachedCourseCount)",
                systemImage: "books.vertical"
            )
            dashboardStatTile(
                title: "Termine heute",
                value: "\(startScheduleEntries.count)",
                systemImage: "calendar.badge.clock",
                footnote: startScheduleLoadedDate.map { "Stand: \(Self.fileDateFormatter.string(from: $0))" }
            )
        }
    }

    @ViewBuilder
    private func dashboardStatTile(title: String, value: String, systemImage: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func startScheduleWidget(limit: Int) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Heute", systemImage: "sun.max")
                        .font(.headline)
                    Spacer()
                    if isLoadingStartSchedule {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Neu laden") {
                        Task { await loadStartSchedule(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoadingStartSchedule)
                }

                if isLoadingStartSchedule, startScheduleEntries.isEmpty {
                    ProgressView("Lade Stundenplan ...")
                        .controlSize(.small)
                } else if let startScheduleError {
                    Text(startScheduleError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if upcomingStartEntries.isEmpty {
                    Text("Heute sind keine Termine im Stundenplan.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(upcomingStartEntries.prefix(limit))) { entry in
                            startScheduleRow(entry)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Tagesagenda", systemImage: "clock")
        }
    }

    private var startSemesterOverviewWidget: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if semesterViewModel.semesters.isEmpty {
                    Text("Noch keine Semester geladen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(semesterViewModel.semesters.prefix(6))) { semester in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(semester.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(semesterDateRangeText(semester))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if semesterSelectionStore.isActive(semesterID: semester.id) {
                                Text("Aktiv")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Semesterueberblick", systemImage: "calendar")
        }
    }

    private var startQuickActionsWidget: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Schnellaktionen")
                    .font(.headline)

                HStack(spacing: 8) {
                    Button("Semester neu laden") {
                        semesterViewModel.loadSemesters()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Erstes Semester oeffnen") {
                        if let first = semesterViewModel.semesters.first {
                            selectedSemesterID = first.id
                            selectedCourseID = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(semesterViewModel.semesters.isEmpty)

                    Button("Debug oeffnen") {
                        debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
                        openWindow(id: "debugWindow")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func semesterDateRangeText(_ semester: SemesterDTO) -> String {
        let start = semester.begin ?? semester.startOfLectures
        let end = semester.end ?? semester.endOfLectures

        switch (start, end) {
        case (.some(let start), .some(let end)):
            return "\(Self.fileDateFormatter.string(from: start)) - \(Self.fileDateFormatter.string(from: end))"
        case (.some(let start), .none):
            return "Start: \(Self.fileDateFormatter.string(from: start))"
        case (.none, .some(let end)):
            return "Ende: \(Self.fileDateFormatter.string(from: end))"
        default:
            return "Kein Zeitraum hinterlegt"
        }
    }

    private var coursesColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kurse im Semester")
                    .font(.headline.weight(.semibold))
                Spacer()
                if isLoadingCourses {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(courses.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            List(courses, selection: $selectedCourseID) { course in
                courseRow(course)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))

            Text(courseStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            detailHeader

            VStack(alignment: .leading, spacing: 16) {
                if let selectedCourse = selectedCourse {
                    courseDetailCard(for: selectedCourse)
                    if isLoadingCourseDetail {
                        ProgressView("Lade Kursdetail ...")
                            .controlSize(.small)
                    }
                } else if let selectedSemester {
                    semesterStatusPlaceholder(for: selectedSemester)
                } else {
                    Text("Waehle links ein Semester aus.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            detailActions
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedSemester?.title ?? "Kein Semester ausgewaehlt")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(statusController.syncState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func semesterStatusPlaceholder(for semester: SemesterDTO) -> some View {
        let entries = semesterScheduleEventsBySemesterID[semester.id] ?? []
        let errorText = semesterScheduleErrorsBySemesterID[semester.id]
        let isLoading = loadingSemesterScheduleIDs.contains(semester.id)
        let loadedAt = semesterScheduleLoadedAtBySemesterID[semester.id]

        return GroupBox("Semester-Status") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(semester.title)
                        .font(.title3.weight(.semibold))

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("Neu laden") {
                        Task {
                            await loadSemesterSchedule(for: semester, force: true)
                        }
                    }
                    .disabled(isLoading)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isLoading, entries.isEmpty {
                    ProgressView("Lade Stundenplan des Semesters ...")
                        .controlSize(.small)
                } else if entries.isEmpty {
                    Text("Keine Stundenplantermine fuer dieses Semester gefunden.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(entries) { event in
                                semesterScheduleRow(event)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 140, maxHeight: 320)
                }

                if let loadedAt {
                    Text("Stand: \(Self.fileDateFormatter.string(from: loadedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Waehle in der mittleren Spalte einen Kurs aus, um Kursdetails zu sehen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var detailActions: some View {
        HStack {
            Button("Jetzt synchronisieren") {
                syncScheduler.triggerManualSync()
            }

            SettingsLink {
                Text("Einstellungen")
            }

            Button("Debug öffnen") {
                debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
                openWindow(id: "debugWindow")
            }
        }
    }

    private var selectedSemester: SemesterDTO? {
        guard let selectedSemesterID else { return nil }
        return semesterViewModel.semesters.first { $0.id == selectedSemesterID }
    }

    private var selectedCourse: CourseDTO? {
        guard let selectedCourseID else { return nil }
        return courses.first { $0.id == selectedCourseID }
    }

    private var defaultCourseDetailSections: [CourseDetailSection] {
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

    private var visibleCourseDetailSections: [CourseDetailSection] {
        guard let selectedCourseID else { return defaultCourseDetailSections }
        guard let pages = wikisByCourseID[selectedCourseID] else { return defaultCourseDetailSections }
        if pages.isEmpty {
            return defaultCourseDetailSections.filter { $0.id != CourseDetailSection.wiki.id }
        }
        return defaultCourseDetailSections
    }

    private var participantTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var fileListTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let folderID = selectedCourseID
            .flatMap { activeFileFolderID(for: $0) }
            ?? "root"
        return "\(courseID):\(selectedCourseDetailSectionID):\(folderID)"
    }

    private var chatListTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var chatWindowTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let threadID = selectedCourseID
            .flatMap { selectedChatThreadIDByCourseID[$0] }
            ?? "none"
        return "\(courseID):\(selectedCourseDetailSectionID):\(threadID)"
    }

    private var wikiListTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var forumTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var forumEntryTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let categoryID = selectedCourseID
            .flatMap { selectedForumCategoryIDByCourseID[$0] }
            ?? "none"
        return "\(courseID):\(selectedCourseDetailSectionID):\(categoryID)"
    }

    private var forumReplyTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let categoryID = selectedCourseID
            .flatMap { selectedForumCategoryIDByCourseID[$0] }
            ?? "none"
        let entryID = selectedForumEntryIDByCategoryID[categoryID] ?? "none"
        return "\(courseID):\(selectedCourseDetailSectionID):\(categoryID):\(entryID)"
    }

    private var newsTaskID: String {
        selectedCourseID ?? "none"
    }

    private var newsCommentTaskID: String {
        let courseID = selectedCourseID ?? "none"
        let newsID = selectedCourseID
            .flatMap { selectedNewsIDByCourseID[$0] }
            ?? "none"
        return "\(courseID):\(newsID)"
    }

    private var semesterIDsSignature: String {
        semesterViewModel.semesters.map(\.id).joined(separator: ",")
    }

    private var startScheduleTaskID: String {
        let dayKey = Self.scheduleDayFormatter.string(from: Date())
        return "\(selectedPage.rawValue):\(selectedSemesterID == nil ? "no-semester" : "semester"):\(dayKey)"
    }

    private var semesterScheduleTaskID: String {
        "\(selectedSemesterID ?? "none"):\(selectedCourseID ?? "none")"
    }

    private func isSelectedMenuPage(_ page: SidebarPage) -> Bool {
        selectedSemesterID == nil && selectedSidebarPage == page
    }

    private func isSelectedSemester(_ semesterID: String) -> Bool {
        selectedSemesterID == semesterID
    }

    private func startScheduleRow(_ entry: ScheduleEntryDTO) -> some View {
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

    private func semesterScheduleRow(_ event: EventDTO) -> some View {
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

    private func activeRowBackground(isActive: Bool) -> Color {
        isActive ? Color.accentColor.opacity(0.14) : .clear
    }

    private func activeRowForeground(isActive: Bool) -> Color {
        isActive ? Color.accentColor : Color.primary
    }

    private struct SidebarSelectionModifier: ViewModifier {
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

    private func selectFirstSemesterIfNeeded() {
        guard selectedSemesterID == nil else { return }
        guard let firstSemester = semesterViewModel.semesters.first else { return }
        selectedSemesterID = firstSemester.id
    }

    private func pruneCourseOverviewCacheToKnownSemesters() {
        let knownSemesterIDs = Set(semesterViewModel.semesters.map(\.id))
        coursesBySemesterID = coursesBySemesterID.filter { knownSemesterIDs.contains($0.key) }
        coursePrefetchErrorsBySemesterID = coursePrefetchErrorsBySemesterID.filter { knownSemesterIDs.contains($0.key) }
        prefetchingSemesterCourseIDs = prefetchingSemesterCourseIDs.intersection(knownSemesterIDs)
    }

    private func prefetchCourseOverviewsForLoadedSemesters() async {
        guard !semesterViewModel.semesters.isEmpty else { return }
        for semester in semesterViewModel.semesters {
            await prefetchCourseOverview(for: semester.id)
        }
    }

    private func prefetchCourseOverview(for semesterID: String) async {
        guard coursesBySemesterID[semesterID] == nil else { return }
        guard !prefetchingSemesterCourseIDs.contains(semesterID) else { return }

        prefetchingSemesterCourseIDs.insert(semesterID)
        defer { prefetchingSemesterCourseIDs.remove(semesterID) }

        do {
            let fetched = try await repository.fetchCourses(for: semesterID)
            let sorted = sortCoursesForDisplay(fetched)
            coursesBySemesterID[semesterID] = sorted
            coursePrefetchErrorsBySemesterID[semesterID] = nil
        } catch {
            coursePrefetchErrorsBySemesterID[semesterID] = "Fehler beim Vorladen der Kurse: \(error.localizedDescription)"
        }
    }

    private func loadCoursesForSelectedSemester() async {
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
            let fetched = try await repository.fetchCourses(for: selectedSemesterID)
            let sorted = sortCoursesForDisplay(fetched)
            coursesBySemesterID[selectedSemesterID] = sorted
            courses = sorted
            courseStatusMessage = fetched.isEmpty ? "Keine Kurse gefunden" : "\(fetched.count) Kurse geladen"
        } catch {
            courses = []
            courseStatusMessage = "Fehler beim Laden der Kurse: \(error.localizedDescription)"
        }
    }

    private func sortCoursesForDisplay(_ courses: [CourseDTO]) -> [CourseDTO] {
        courses.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func loadStartScheduleIfNeeded() async {
        guard selectedSemesterID == nil, selectedPage == .start else { return }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        if let loadedDate = startScheduleLoadedDate, calendar.isDate(loadedDate, inSameDayAs: todayStart) {
            return
        }

        await loadStartSchedule(force: false)
    }

    private func loadStartSchedule(force: Bool) async {
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

    private func loadSemesterScheduleIfNeeded() async {
        guard selectedCourseID == nil else { return }
        guard let semester = selectedSemester else { return }
        guard semesterScheduleEventsBySemesterID[semester.id] == nil else { return }
        await loadSemesterSchedule(for: semester, force: false)
    }

    private func loadSemesterSchedule(for semester: SemesterDTO, force: Bool) async {
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

    private func loadCourseDetailForSelectedCourse() async {
        guard let selectedCourseID else {
            return
        }

        selectedCourseDetailSectionID = CourseDetailSection.description.id
        selectedParticipantForInfo = nil
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
        }
    }

    private func prefetchAllTabContentForCourse(_ courseID: String) async {
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

    private func prefetchNewsContent(for courseID: String) async {
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
            markDetailSectionLoadedNow(courseID: courseID, sectionID: "news")
        } catch {
            newsCommentErrorsByNewsID[newsID] = "Fehler beim Laden der News-Kommentare: \(error.localizedDescription)"
        }
    }

    private func prefetchRootFilesContent(for courseID: String) async {
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
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.files.id)
        } catch {
            fileErrorsByContextKey[contextKey] = "Fehler beim Laden der Dateien/Ordner: \(error.localizedDescription)"
        }
    }

    private func prefetchChatContent(for courseID: String) async {
        if chatsByCourseID[courseID] == nil {
            do {
                let threads = try await repository.fetchCourseChatThreads(courseID: courseID)
                chatsByCourseID[courseID] = threads
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
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.chat.id)
        } catch {
            chatMessageErrorsByThreadID[threadID] = "Fehler beim Laden des Chatfensters: \(error.localizedDescription)"
        }
    }

    private func prefetchWikiContent(for courseID: String) async {
        guard wikisByCourseID[courseID] == nil else {
            return
        }

        do {
            let pages = try await repository.fetchCourseWikiPages(courseID: courseID)
            wikisByCourseID[courseID] = pages
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

    private func prefetchParticipantContent(for courseID: String) async {
        guard participantsByCourseID[courseID] == nil else {
            return
        }

        do {
            let participants = try await repository.fetchCourseParticipants(courseID: courseID)
            participantsByCourseID[courseID] = participants
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.participants.id)
        } catch {
            participantErrorsByCourseID[courseID] = "Fehler beim Laden der Teilnehmer: \(error.localizedDescription)"
        }
    }

    private func prefetchForumContent(for courseID: String) async {
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
            markDetailSectionLoadedNow(courseID: courseID, sectionID: CourseDetailSection.forum.id)
        } catch {
            forumReplyErrorsByEntryID[entryID] = "Fehler beim Laden der Forum-Antworten: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func courseDetailCard(for course: CourseDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(course.title)
                        .font(.title3.weight(.semibold))
                    if let subtitle = nonEmpty(course.subtitle) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let summary = courseMetaSummary(for: course) {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Uebersicht", systemImage: "info.circle")
                    .font(.headline)
            }

            if shouldShowNewsBlock(for: course.id) {
                newsDemoBlock(for: course)
            }

            HStack(spacing: 10) {
                courseSectionNavigation(for: course)

                Button {
                    Task {
                        await forceReloadAllDetailContent(for: course.id)
                    }
                } label: {
                    if prefetchingCourseIDs.contains(course.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Alle neu laden", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(prefetchingCourseIDs.contains(course.id))
            }

            HStack(spacing: 10) {
                if supportsDetailSearch(for: selectedCourseDetailSectionID) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            "In \(sectionTitle(for: selectedCourseDetailSectionID)) filtern",
                            text: detailSearchBinding(for: selectedCourseDetailSectionID)
                        )
                        .textFieldStyle(.plain)

                        if !rawDetailSearchQuery(for: selectedCourseDetailSectionID).isEmpty {
                            Button {
                                detailSearchTextBySectionID[selectedCourseDetailSectionID] = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Filter leeren")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer(minLength: 8)

                if let loadedAtText = detailSectionLoadedAtText(courseID: course.id, sectionID: selectedCourseDetailSectionID) {
                    Text(loadedAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                ScrollView {
                    courseDetailSectionContent(for: course, sectionID: selectedCourseDetailSectionID)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } label: {
                Text(sectionTitle(for: selectedCourseDetailSectionID))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func courseRow(_ course: CourseDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(course.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let secondary = courseSecondaryLine(for: course) {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCourseID = course.id
            Task(priority: .utility) {
                await prefetchAllTabContentForCourse(course.id)
            }
        }
    }

    private func courseSecondaryLine(for course: CourseDTO) -> String? {
        if let subtitle = nonEmpty(course.subtitle) { return subtitle }
        if let number = nonEmpty(course.courseNumber) { return "Kursnr. \(number)" }
        return courseTypeLabel(for: course)
    }

    private func courseMetaSummary(for course: CourseDTO) -> String? {
        var parts: [String] = []
        if let number = nonEmpty(course.courseNumber) {
            parts.append("Kursnr. \(number)")
        }
        if let type = courseTypeLabel(for: course) {
            parts.append(type)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func courseTypeLabel(for course: CourseDTO) -> String? {
        if let type = course.courseType {
            return "Typ \(type)"
        }
        return nonEmpty(course.courseTypeID)
    }

    @ViewBuilder
    private func courseDetailSectionContent(for course: CourseDTO, sectionID: String) -> some View {
        switch sectionID {
        case CourseDetailSection.description.id:
            if let description = nonEmpty(course.description) {
                Text(description)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                emptySectionText("Keine Beschreibung vorhanden.")
            }

        case CourseDetailSection.metadata.id:
            VStack(alignment: .leading, spacing: 8) {
                detailRow("Ort", nonEmpty(course.location))
                detailRow("Startsemester", nonEmpty(course.startSemesterRef))
                detailRow("Institut", nonEmpty(course.instituteID))
                detailRow("Sem-Klasse", nonEmpty(course.semClassID))
                detailRow("Sem-Typ", nonEmpty(course.semTypeID))
                detailRow("Zusatz", nonEmpty(course.miscellaneous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.files.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Dateien fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadFilesForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                filesBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.chat.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chat/Threads fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadChatsForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                chatsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.wiki.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Wiki-Seiten fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadWikisForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                wikisBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.participants.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Teilnehmer in diesem Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadParticipantsForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                participantsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.forum.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Forum-Kategorien fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadForumsForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                forumsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            emptySectionText("Dieser Bereich ist noch nicht belegt.")
        }
    }

    private func newsDemoBlock(for course: CourseDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("News")
                    .font(.headline)
                Spacer()
                if let loadedAtText = detailSectionLoadedAtText(courseID: course.id, sectionID: "news") {
                    Text(loadedAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Neu laden") {
                    Task { await forceReloadNewsForSelectedCourse() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isLoadingCourseNews, courseNewsByCourseID[course.id] == nil {
                ProgressView("Lade Veranstaltungsnews ...")
                    .controlSize(.small)
            } else if let newsItems = courseNewsByCourseID[course.id], !newsItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(newsItems) { item in
                            newsRow(item, courseID: course.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    newsCommentsWindowBlock(for: course.id)
                }
            } else if let errorText = courseNewsErrorsByCourseID[course.id] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Keine Veranstaltungsnews vorhanden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func shouldShowNewsBlock(for courseID: String) -> Bool {
        if isLoadingCourseNews, courseNewsByCourseID[courseID] == nil {
            return true
        }
        if let errorText = courseNewsErrorsByCourseID[courseID], nonEmpty(errorText) != nil {
            return true
        }
        if let newsItems = courseNewsByCourseID[courseID] {
            return !newsItems.isEmpty
        }
        return false
    }

    private func newsRow(_ newsItem: NewsDTO, courseID: String) -> some View {
        let isSelected = selectedNewsIDByCourseID[courseID] == newsItem.id

        return Button {
            selectedNewsIDByCourseID[courseID] = newsItem.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(nonEmpty(newsItem.title) ?? "News \(newsItem.id)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let content = nonEmpty(newsItem.content) {
                    let preview = content.contains("<") && content.contains(">")
                        ? plainText(fromHTML: content)
                        : content
                    if let preview = nonEmpty(preview) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Text(newsMetadataLine(newsItem))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func newsCommentsWindowBlock(for courseID: String) -> some View {
        if let selectedNewsID = selectedNewsIDByCourseID[courseID] {
            if loadingNewsCommentIDs.contains(selectedNewsID), newsCommentsByNewsID[selectedNewsID] == nil {
                ProgressView("Lade Kommentare ...")
                    .controlSize(.small)
            } else if let comments = newsCommentsByNewsID[selectedNewsID], !comments.isEmpty {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(comments) { comment in
                        newsCommentRow(comment)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let errorText = newsCommentErrorsByNewsID[selectedNewsID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Kommentare zu dieser News.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle eine News aus, um Kommentare zu sehen.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func newsCommentRow(_ comment: NewsCommentDTO) -> some View {
        let parsed = nonEmpty(comment.content).flatMap { content in
            if content.contains("<"), content.contains(">") {
                return nonEmpty(plainText(fromHTML: content) ?? content)
            }
            return nonEmpty(content)
        } ?? "(leer)"

        return VStack(alignment: .leading, spacing: 4) {
            Text(parsed)
                .font(.callout)
                .lineLimit(6)

            Text("Kommentar \(comment.id)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func courseSectionNavigation(for course: CourseDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleCourseDetailSections) { section in
                    Button {
                        selectedCourseDetailSectionID = section.id
                    } label: {
                        HStack(spacing: 6) {
                            Label(section.title, systemImage: section.systemImage)
                                .font(.subheadline.weight(.medium))

                            if let count = sectionItemCount(for: section.id, courseID: course.id) {
                                Text("\(count)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedCourseDetailSectionID == section.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                        .foregroundStyle(selectedCourseDetailSectionID == section.id ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sectionItemCount(for sectionID: String, courseID: String) -> Int? {
        switch sectionID {
        case CourseDetailSection.files.id:
            let contextKey = fileContextKey(courseID: courseID, folderID: nil)
            guard let files = filesByContextKey[contextKey], let folders = foldersByContextKey[contextKey] else {
                return nil
            }
            return files.count + folders.count
        case CourseDetailSection.chat.id:
            return chatsByCourseID[courseID]?.count
        case CourseDetailSection.wiki.id:
            return wikisByCourseID[courseID]?.count
        case CourseDetailSection.participants.id:
            return participantsByCourseID[courseID]?.count
        case CourseDetailSection.forum.id:
            return forumsByCourseID[courseID]?.count
        default:
            return nil
        }
    }

    private func sectionTitle(for sectionID: String) -> String {
        visibleCourseDetailSections.first(where: { $0.id == sectionID })?.title
            ?? defaultCourseDetailSections.first(where: { $0.id == sectionID })?.title
            ?? "Bereich"
    }

    private func supportsDetailSearch(for sectionID: String) -> Bool {
        switch sectionID {
        case CourseDetailSection.files.id,
             CourseDetailSection.chat.id,
             CourseDetailSection.wiki.id,
             CourseDetailSection.participants.id,
             CourseDetailSection.forum.id:
            return true
        default:
            return false
        }
    }

    private func detailSearchBinding(for sectionID: String) -> Binding<String> {
        Binding(
            get: { detailSearchTextBySectionID[sectionID] ?? "" },
            set: { detailSearchTextBySectionID[sectionID] = $0 }
        )
    }

    private func rawDetailSearchQuery(for sectionID: String) -> String {
        (detailSearchTextBySectionID[sectionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedDetailSearchQuery(for sectionID: String) -> String {
        rawDetailSearchQuery(for: sectionID).lowercased()
    }

    private func detailSearchNoResultsText(for sectionID: String) -> String {
        let raw = rawDetailSearchQuery(for: sectionID)
        guard !raw.isEmpty else { return "Keine Treffer gefunden." }
        return "Keine Treffer fuer \"\(raw)\"."
    }

    private func detailSectionCacheKey(courseID: String, sectionID: String) -> String {
        "\(courseID)::\(sectionID)"
    }

    private func markDetailSectionLoadedNow(courseID: String, sectionID: String) {
        detailSectionLoadedAtByKey[detailSectionCacheKey(courseID: courseID, sectionID: sectionID)] = Date()
    }

    private func detailSectionLoadedAtText(courseID: String, sectionID: String) -> String? {
        guard let loadedAt = detailSectionLoadedAtByKey[detailSectionCacheKey(courseID: courseID, sectionID: sectionID)] else {
            return nil
        }
        return "Stand: \(Self.fileDateFormatter.string(from: loadedAt))"
    }

    private func containsSearch(_ haystack: String, query: String) -> Bool {
        query.isEmpty || haystack.lowercased().contains(query)
    }

    private func preloadWikiAvailability(for courseID: String) async {
        guard wikisByCourseID[courseID] == nil else { return }

        do {
            let pages = try await repository.fetchCourseWikiPages(courseID: courseID)
            if selectedCourseID == courseID {
                wikisByCourseID[courseID] = pages
                if pages.isEmpty, selectedCourseDetailSectionID == CourseDetailSection.wiki.id {
                    selectedCourseDetailSectionID = CourseDetailSection.description.id
                }
            }
        } catch {
            if selectedCourseID == courseID {
                wikiErrorsByCourseID[courseID] = "Fehler beim Laden der Wiki-Seiten: \(error.localizedDescription)"
            }
        }
    }

    private func emptySectionText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func forumsBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.forum.id)

        if isLoadingForums, forumsByCourseID[course.id] == nil {
            ProgressView("Lade Forum ...")
                .controlSize(.small)
        } else if let categories = forumsByCourseID[course.id], !categories.isEmpty {
            let filteredCategories = query.isEmpty ? categories : categories.filter { category in
                containsSearch(
                    [
                        nonEmpty(category.title),
                        forumMetadataLine(category),
                        category.id
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }

            if filteredCategories.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.forum.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Kategorien", systemImage: "rectangle.stack.bubble.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredCategories) { category in
                                forumCategoryRow(category, courseID: course.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    let selectedID = selectedForumCategoryIDByCourseID[course.id]
                    if selectedID == nil || filteredCategories.contains(where: { $0.id == selectedID }) {
                        forumEntriesWindowBlock(for: course.id)
                    } else {
                        Text("Die aktuell ausgewaehlte Kategorie passt nicht zum Filter.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if let errorText = forumErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Forum-Kategorien gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func forumCategoryRow(_ category: StudIPResourceRepository.CourseForumCategory, courseID: String) -> some View {
        let isSelected = selectedForumCategoryIDByCourseID[courseID] == category.id

        return Button {
            selectedForumCategoryIDByCourseID[courseID] = category.id
            if selectedForumEntryIDByCategoryID[category.id] == nil {
                selectedForumEntryIDByCategoryID[category.id] = forumEntriesByCategoryID[category.id]?.first?.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.2))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: "text.bubble")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                        .padding(.top, 1)

                    Text(nonEmpty(category.title) ?? "Forum \(category.id)")
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    Spacer(minLength: 8)
                }

                Text(forumMetadataLine(category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func forumEntriesWindowBlock(for courseID: String) -> some View {
        if let selectedCategoryID = selectedForumCategoryIDByCourseID[courseID] {
            if loadingForumCategoryIDs.contains(selectedCategoryID), forumEntriesByCategoryID[selectedCategoryID] == nil {
                ProgressView("Lade Forum-Themen ...")
                    .controlSize(.small)
            } else if let entries = forumEntriesByCategoryID[selectedCategoryID], !entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Themen", systemImage: "text.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(entries) { entry in
                                forumEntryRow(entry, categoryID: selectedCategoryID)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    forumRepliesWindowBlock(categoryID: selectedCategoryID)
                }
            } else if let errorText = forumEntryErrorsByCategoryID[selectedCategoryID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Forum-Themen in dieser Kategorie.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle eine Forum-Kategorie aus, um die Themen zu sehen.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func forumEntryRow(_ entry: ForumEntryDTO, categoryID: String) -> some View {
        let isSelected = selectedForumEntryIDByCategoryID[categoryID] == entry.id

        return Button {
            selectedForumEntryIDByCategoryID[categoryID] = entry.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(nonEmpty(entry.title) ?? "Eintrag \(entry.id)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let content = nonEmpty(entry.content) {
                    let preview = content.contains("<") && content.contains(">")
                        ? plainText(fromHTML: content)
                        : content
                    if let preview = nonEmpty(preview) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Text(forumEntryMetadataLine(entry))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func forumRepliesWindowBlock(categoryID: String) -> some View {
        if let selectedEntryID = selectedForumEntryIDByCategoryID[categoryID] {
            if loadingForumEntryIDs.contains(selectedEntryID), forumRepliesByEntryID[selectedEntryID] == nil {
                ProgressView("Lade Antworten ...")
                    .controlSize(.small)
            } else if let replies = forumRepliesByEntryID[selectedEntryID], !replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Antworten", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(replies) { reply in
                            forumReplyRow(reply)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            } else if let errorText = forumReplyErrorsByEntryID[selectedEntryID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Antworten zu diesem Thema gefunden.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle ein Thema aus, um Antworten zu sehen.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func forumReplyRow(_ reply: ForumEntryDTO) -> some View {
        let bubbleColor = Color.accentColor.opacity(0.11)

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if let content = nonEmpty(reply.content) {
                    let preview = content.contains("<") && content.contains(">")
                        ? plainText(fromHTML: content)
                        : content
                    Text(nonEmpty(preview) ?? "(leer)")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                } else {
                    Text("(leer)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(forumEntryMetadataLine(reply))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func filesBlock(for course: CourseDTO) -> some View {
        let contextKey = activeFileContextKey(for: course.id)
        let folders = foldersByContextKey[contextKey] ?? []
        let files = filesByContextKey[contextKey] ?? []
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.files.id)
        let filteredFolders = query.isEmpty ? folders : folders.filter { folder in
            containsSearch(
                [
                    nonEmpty(folder.name),
                    nonEmpty(folder.details),
                    folder.id
                ]
                .compactMap { $0 }
                .joined(separator: " "),
                query: query
            )
        }
        let filteredFiles = query.isEmpty ? files : files.filter { file in
            containsSearch(
                [
                    nonEmpty(file.name),
                    nonEmpty(file.description),
                    nonEmpty(file.ownerName),
                    nonEmpty(file.mimeType),
                    file.id
                ]
                .compactMap { $0 }
                .joined(separator: " "),
                query: query
            )
        }
        let hasContent = !folders.isEmpty || !files.isEmpty
        let hasFilteredContent = !filteredFolders.isEmpty || !filteredFiles.isEmpty

        if isLoadingFiles, foldersByContextKey[contextKey] == nil, filesByContextKey[contextKey] == nil {
            ProgressView("Lade Dateien ...")
                .controlSize(.small)
        } else if hasContent {
            if !hasFilteredContent {
                Text(detailSearchNoResultsText(for: CourseDetailSection.files.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let breadcrumb = folderBreadcrumbText(for: course.id) {
                        HStack(spacing: 10) {
                            Text(breadcrumb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Button("Zurueck") {
                                openParentFolder(for: course.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Wurzel") {
                                openRootFolder(for: course.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    ForEach(filteredFolders) { folder in
                        folderRow(folder, courseID: course.id)
                    }

                    ForEach(filteredFiles) { fileRef in
                        fileRow(fileRef, contextKey: contextKey)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 140)
            }
        } else if let errorText = fileErrorsByContextKey[contextKey] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Dateien oder Ordner gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func folderRow(_ folder: FolderDTO, courseID: String) -> some View {
        Button {
            openFolder(folder, for: courseID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(nonEmpty(folder.name) ?? "Ordner \(folder.id)")
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    if let details = nonEmpty(folder.details) {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ fileRef: CourseFileRefDTO, contextKey: String) -> some View {
        let canPreview = fileRef.isReadable ?? fileRef.isDownloadable ?? true
        let canDownload = fileRef.isDownloadable ?? fileRef.isReadable ?? true

        return HStack(alignment: .top, spacing: 10) {
            Button {
                previewFileViaApplePreview(fileRef, contextKey: contextKey)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName(forMIMEType: fileRef.mimeType))
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(nonEmpty(fileRef.name) ?? "Datei \(fileRef.id)")
                            .font(.body.weight(.medium))
                            .lineLimit(2)

                        Text(fileMetadataLine(fileRef))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let description = nonEmpty(fileRef.description) {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if let downloadError = fileDownloadErrorsByFileID[fileRef.id] {
                            Text(downloadError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }

                        if let previewError = filePreviewErrorsByFileID[fileRef.id] {
                            Text(previewError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canPreview || previewingFileIDs.contains(fileRef.id))
            .help(canPreview ? "Apple Vorschau (Quick Look) anzeigen" : "Datei ist nicht lesbar")

            if previewingFileIDs.contains(fileRef.id) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
            }

            Button {
                downloadFileViaAPI(fileRef, contextKey: contextKey)
            } label: {
                if downloadingFileIDs.contains(fileRef.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!canDownload || downloadingFileIDs.contains(fileRef.id))
            .help(canDownload ? "Datei ueber API herunterladen" : "Datei ist nicht downloadbar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func chatsBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.chat.id)

        if isLoadingChats, chatsByCourseID[course.id] == nil {
            ProgressView("Lade Chat ...")
                .controlSize(.small)
        } else if let threads = chatsByCourseID[course.id], !threads.isEmpty {
            let filteredThreads = query.isEmpty ? threads : threads.filter { thread in
                containsSearch(
                    [
                        thread.name,
                        chatPreviewText(thread),
                        chatMetadataLine(thread),
                        thread.id
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }

            if filteredThreads.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.chat.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unterhaltungen", systemImage: "list.bullet.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredThreads) { thread in
                                chatRow(thread, courseID: course.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    let selectedID = selectedChatThreadIDByCourseID[course.id]
                    if selectedID == nil || filteredThreads.contains(where: { $0.id == selectedID }) {
                        chatWindowBlock(for: course.id)
                    } else {
                        Text("Der aktuell ausgewaehlte Thread passt nicht zum Filter.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if let errorText = chatErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Chat-Threads gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chatRow(_ thread: StudIPResourceRepository.CourseChatThread, courseID: String) -> some View {
        let isSelected = selectedChatThreadIDByCourseID[courseID] == thread.id

        return Button {
            selectedChatThreadIDByCourseID[courseID] = thread.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.2))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: thread.isFollowed == true ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.name)
                            .font(.body.weight(.medium))
                            .lineLimit(2)

                        if let preview = chatPreviewText(thread) {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    if let unseen = thread.unseenComments, unseen > 0 {
                        Text("\(unseen)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                Text(chatMetadataLine(thread))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if thread.isCommentable == true { smallBadge("Kommentierbar") }
                    if thread.isWritable == true { smallBadge("Schreibbar") }
                    if thread.isReadable == true { smallBadge("Lesbar") }
                    if thread.isFollowed == true { smallBadge("Abonniert") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chatWindowBlock(for courseID: String) -> some View {
        if let threadID = selectedChatThreadIDByCourseID[courseID] {
            if loadingChatThreadIDs.contains(threadID), chatMessagesByThreadID[threadID] == nil {
                ProgressView("Lade Chatfenster ...")
                    .controlSize(.small)
            } else if let messages = chatMessagesByThreadID[threadID], !messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Nachrichten", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            chatMessageRow(message)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            } else if let errorText = chatMessageErrorsByThreadID[threadID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Nachrichten in diesem Chat.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle einen Thread aus, um das Chatfenster zu laden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chatMessageRow(_ message: BlubberPostingDTO) -> some View {
        let alignTrailing = abs(message.id.hashValue) % 4 == 0
        let bubbleColor = alignTrailing ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1)

        return HStack(alignment: .top, spacing: 0) {
            if alignTrailing {
                Spacer(minLength: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(chatMessageText(message))
                    .font(.callout)
                    .textSelection(.enabled)

                Text(chatMessageMetadataLine(message))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !alignTrailing {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
    }

    private func smallBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.18))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func wikisBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.wiki.id)

        if isLoadingWikis, wikisByCourseID[course.id] == nil {
            ProgressView("Lade Wiki ...")
                .controlSize(.small)
        } else if let pages = wikisByCourseID[course.id], !pages.isEmpty {
            let filteredPages = query.isEmpty ? pages : pages.filter { page in
                containsSearch(
                    [
                        page.keyword,
                        wikiPreviewText(page),
                        wikiMetadataLine(page),
                        wikiContentText(page),
                        page.id
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }

            if filteredPages.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.wiki.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredPages) { page in
                            wikiRow(page, courseID: course.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 100)

                    let selectedID = selectedWikiPageIDByCourseID[course.id]
                    if selectedID == nil || filteredPages.contains(where: { $0.id == selectedID }) {
                        wikiWindowBlock(for: course.id)
                    } else {
                        Text("Die aktuell ausgewaehlte Wiki-Seite passt nicht zum Filter.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if let errorText = wikiErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Wiki-Seiten gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wikiRow(_ page: StudIPResourceRepository.CourseWikiPage, courseID: String) -> some View {
        let isSelected = selectedWikiPageIDByCourseID[courseID] == page.id

        return Button {
            selectedWikiPageIDByCourseID[courseID] = page.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "book.pages")
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.keyword)
                            .font(.body.weight(.medium))
                            .lineLimit(2)

                        if let preview = wikiPreviewText(page) {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }

                Text(wikiMetadataLine(page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func wikiWindowBlock(for courseID: String) -> some View {
        if let pages = wikisByCourseID[courseID], !pages.isEmpty {
            if let selectedPage = selectedWikiPage(for: courseID, pages: pages) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedPage.keyword)
                        .font(.headline)
                        .lineLimit(2)

                    Text(wikiMetadataLine(selectedPage))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(wikiContentText(selectedPage))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Waehle eine Wiki-Seite aus, um den Inhalt zu sehen.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Kein Wiki-Inhalt vorhanden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func participantsBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.participants.id)

        if isLoadingParticipants, participantsByCourseID[course.id] == nil {
            ProgressView("Lade Teilnehmer ...")
                .controlSize(.small)
        } else if let participants = participantsByCourseID[course.id], !participants.isEmpty {
            let filteredParticipants = query.isEmpty ? participants : participants.filter { participant in
                containsSearch(
                    [
                        participant.displayName,
                        nonEmpty(participant.email),
                        nonEmpty(participant.permission),
                        nonEmpty(participant.label),
                        participant.userID
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }
            let groupedParticipants = groupedParticipantsByRole(filteredParticipants)

            if filteredParticipants.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.participants.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if groupedParticipants.isEmpty {
                Text("Keine Teilnehmer mit Rolle root/admin/dozent/tutor/autor vorhanden.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.participantRoleOrder, id: \.self) { roleKey in
                        if let roleParticipants = groupedParticipants[roleKey], !roleParticipants.isEmpty {
                            participantRoleTable(
                                title: participantRoleTitle(for: roleKey),
                                participants: roleParticipants
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 140)
            }
        } else if let errorText = participantErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Teilnehmer gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func participantRoleTable(
        title: String,
        participants: [StudIPResourceRepository.CourseParticipant]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(title) (\(participants.count))", systemImage: "person.3.sequence")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("E-Mail").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Label").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Pos.").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Gr.").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Aktionen").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }

                    Divider()
                        .gridCellColumns(6)

                    ForEach(participants) { participant in
                        GridRow(alignment: .center) {
                            Text(participant.displayName)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help("User-ID: \(participant.userID)")

                            Text(nonEmpty(participant.email) ?? "—")
                                .foregroundStyle(nonEmpty(participant.email) == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(nonEmpty(participant.label) ?? "—")
                                .foregroundStyle(nonEmpty(participant.label) == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(participant.position.map(String.init) ?? "—")
                                .foregroundStyle(participant.position == nil ? .secondary : .primary)
                                .frame(width: 36, alignment: .leading)

                            Text(participant.group.map(String.init) ?? "—")
                                .foregroundStyle(participant.group == nil ? .secondary : .primary)
                                .frame(width: 32, alignment: .leading)

                            HStack(spacing: 8) {
                                Button {
                                    selectedParticipantForInfo = participant
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Personeninfos")

                                Button {
                                    openMail(for: participant)
                                } label: {
                                    Image(systemName: "envelope")
                                }
                                .buttonStyle(.borderless)
                                .disabled(nonEmpty(participant.email) == nil)
                                .help(nonEmpty(participant.email) == nil ? "Keine Mailadresse vorhanden" : "Mail senden")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func loadNewsForSelectedCourse(force: Bool = false) async {
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

    private func loadNewsCommentsForSelectedNews(force: Bool = false) async {
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

    private func loadFilesForSelectedSection(force: Bool = false) async {
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

    private func loadChatsForSelectedSection(force: Bool = false) async {
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

    private func loadChatMessagesForSelectedThread(force: Bool = false) async {
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

    private func loadWikisForSelectedSection(force: Bool = false) async {
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

    private func loadParticipantsForSelectedSection(force: Bool = false) async {
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

    private func loadForumsForSelectedSection(force: Bool = false) async {
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

    private func loadForumEntriesForSelectedCategory(force: Bool = false) async {
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

    private func loadForumRepliesForSelectedEntry(force: Bool = false) async {
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

    private func forceReloadNewsForSelectedCourse() async {
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

    private func forceReloadAllDetailContent(for courseID: String) async {
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

    private func forceReloadFilesForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }
        let contextKey = activeFileContextKey(for: courseID)

        foldersByContextKey[contextKey] = nil
        filesByContextKey[contextKey] = nil
        fileErrorsByContextKey[contextKey] = nil

        await loadFilesForSelectedSection(force: true)
    }

    private func forceReloadChatsForSelectedSection() async {
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

    private func forceReloadWikisForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }

        wikisByCourseID[courseID] = nil
        wikiErrorsByCourseID[courseID] = nil

        await loadWikisForSelectedSection(force: true)
    }

    private func forceReloadParticipantsForSelectedSection() async {
        guard let courseID = selectedCourseID else { return }

        participantsByCourseID[courseID] = nil
        participantErrorsByCourseID[courseID] = nil

        await loadParticipantsForSelectedSection(force: true)
    }

    private func forceReloadForumsForSelectedSection() async {
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

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedUserID(_ rawID: String?) -> String? {
        guard let id = nonEmpty(rawID) else { return nil }
        return canonicalStudIPID(id)
    }

    private func displayName(forUserID rawUserID: String?) -> String? {
        guard let userID = normalizedUserID(rawUserID) else { return nil }
        return nonEmpty(userDisplayNameByID[userID])
    }

    private func resolveDisplayNamesIfNeeded(for rawUserIDs: [String]) async {
        let requestedIDs = Set(rawUserIDs.compactMap { normalizedUserID($0) })
        guard !requestedIDs.isEmpty else { return }

        let idsToLoad = requestedIDs.filter { userID in
            userDisplayNameByID[userID] == nil
                && !loadingUserNameIDs.contains(userID)
        }
        guard !idsToLoad.isEmpty else { return }

        loadingUserNameIDs.formUnion(idsToLoad)
        defer { loadingUserNameIDs.subtract(idsToLoad) }

        let loadedUsersByID = await repository.fetchUsersByIDs(Array(idsToLoad))

        for userID in idsToLoad {
            if let user = loadedUsersByID[userID],
               let preferredDisplayName = nonEmpty(user.preferredDisplayName) {
                userDisplayNameByID[userID] = preferredDisplayName
            }
        }
    }

    private func activeFileFolderID(for courseID: String) -> String? {
        fileFolderPathByCourseID[courseID]?.last?.id
    }

    private func fileContextKey(courseID: String, folderID: String?) -> String {
        "\(courseID)::\(folderID ?? "root")"
    }

    private func activeFileContextKey(for courseID: String) -> String {
        fileContextKey(courseID: courseID, folderID: activeFileFolderID(for: courseID))
    }

    private func folderBreadcrumbText(for courseID: String) -> String? {
        let trail = fileFolderPathByCourseID[courseID] ?? []
        guard !trail.isEmpty else { return nil }

        let names = trail.map { nonEmpty($0.name) ?? $0.id }
        return "Pfad: \(names.joined(separator: " / "))"
    }

    private func openFolder(_ folder: FolderDTO, for courseID: String) {
        var trail = fileFolderPathByCourseID[courseID] ?? []
        trail.append(folder)
        fileFolderPathByCourseID[courseID] = trail
    }

    private func openParentFolder(for courseID: String) {
        var trail = fileFolderPathByCourseID[courseID] ?? []
        guard !trail.isEmpty else { return }
        _ = trail.removeLast()
        fileFolderPathByCourseID[courseID] = trail
    }

    private func openRootFolder(for courseID: String) {
        fileFolderPathByCourseID[courseID] = []
    }

    private func fileMetadataLine(_ fileRef: CourseFileRefDTO) -> String {
        var components: [String] = []

        if let owner = nonEmpty(fileRef.ownerName) {
            components.append(owner)
        }

        if let size = fileRef.fileSize {
            components.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }

        if let downloads = fileRef.downloads {
            components.append("\(downloads) Downloads")
        }

        if let mimeType = nonEmpty(fileRef.mimeType) {
            components.append(mimeType)
        }

        if let date = parseAPIDate(fileRef.chdate) ?? parseAPIDate(fileRef.mkdate) {
            components.append(Self.fileDateFormatter.string(from: date))
        }

        return components.isEmpty ? "Keine Dateidetails" : components.joined(separator: " • ")
    }

    private func iconName(forMIMEType mimeType: String?) -> String {
        guard let mimeType = nonEmpty(mimeType)?.lowercased() else {
            return "doc"
        }
        if mimeType.contains("pdf") {
            return "doc.richtext"
        }
        if mimeType.contains("image") {
            return "photo"
        }
        if mimeType.contains("zip") || mimeType.contains("compressed") {
            return "archivebox"
        }
        if mimeType.contains("word") || mimeType.contains("officedocument.wordprocessingml") {
            return "doc.text"
        }
        if mimeType.contains("excel") || mimeType.contains("spreadsheet") {
            return "tablecells"
        }
        if mimeType.contains("powerpoint") || mimeType.contains("presentation") {
            return "rectangle.on.rectangle"
        }
        return "doc"
    }

    private func downloadFileViaAPI(_ fileRef: CourseFileRefDTO, contextKey: String) {
        guard !downloadingFileIDs.contains(fileRef.id) else {
            return
        }
        downloadingFileIDs.insert(fileRef.id)
        fileDownloadErrorsByFileID[fileRef.id] = nil

        Task {
            do {
                let data = try await repository.fetchFileContent(fileRefID: fileRef.id)
                let targetURL = try makeDownloadURL(for: fileRef)
                try data.write(to: targetURL, options: [.atomic])

                await MainActor.run {
                    downloadingFileIDs.remove(fileRef.id)
                    NSWorkspace.shared.open(targetURL)
                    fileDownloadErrorsByFileID[fileRef.id] = nil
                    fileErrorsByContextKey[contextKey] = nil
                }
            } catch {
                await MainActor.run {
                    downloadingFileIDs.remove(fileRef.id)
                    fileDownloadErrorsByFileID[fileRef.id] = "Download fehlgeschlagen."
                    fileErrorsByContextKey[contextKey] = "Fehler beim API-Download: \(error.localizedDescription)"
                }
            }
        }
    }

    private func previewFileViaApplePreview(_ fileRef: CourseFileRefDTO, contextKey: String) {
        guard !previewingFileIDs.contains(fileRef.id) else {
            return
        }
        previewingFileIDs.insert(fileRef.id)
        filePreviewErrorsByFileID[fileRef.id] = nil

        Task {
            do {
                let data = try await repository.fetchFileContent(fileRefID: fileRef.id)
                let targetURL = try makeQuickLookURL(for: fileRef)
                try data.write(to: targetURL, options: [.atomic])

                await MainActor.run {
                    previewingFileIDs.remove(fileRef.id)
                    selectedQuickLookFile = QuickLookPreviewFile(
                        id: "\(fileRef.id)-\(targetURL.path)",
                        title: nonEmpty(fileRef.name) ?? "Datei \(fileRef.id)",
                        url: targetURL
                    )
                    filePreviewErrorsByFileID[fileRef.id] = nil
                    fileErrorsByContextKey[contextKey] = nil
                }
            } catch {
                await MainActor.run {
                    previewingFileIDs.remove(fileRef.id)
                    filePreviewErrorsByFileID[fileRef.id] = "Vorschau fehlgeschlagen."
                    fileErrorsByContextKey[contextKey] = "Fehler bei der Vorschau: \(error.localizedDescription)"
                }
            }
        }
    }

    private func makeDownloadURL(for fileRef: CourseFileRefDTO) throws -> URL {
        let fileManager = FileManager.default
        let baseName = sanitizedFilename(nonEmpty(fileRef.name) ?? "datei-\(fileRef.id)")

        let preferredDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        do {
            try fileManager.createDirectory(at: preferredDirectory, withIntermediateDirectories: true)
            return uniqueFileURL(in: preferredDirectory, preferredName: baseName)
        } catch {
            let fallbackDirectory = fileManager.temporaryDirectory
            try fileManager.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
            return uniqueFileURL(in: fallbackDirectory, preferredName: baseName)
        }
    }

    private func makeQuickLookURL(for fileRef: CourseFileRefDTO) throws -> URL {
        let fileManager = FileManager.default
        let previewDirectory = fileManager.temporaryDirectory.appendingPathComponent("StudipSyncQuickLook", isDirectory: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)

        let baseName = sanitizedFilename(nonEmpty(fileRef.name) ?? "datei-\(fileRef.id)")
        let previewName = sanitizedFilename("\(fileRef.id)-\(baseName)")
        return previewDirectory.appendingPathComponent(previewName, isDirectory: false)
    }

    private func quickLookSheet(for previewFile: QuickLookPreviewFile) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(previewFile.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(previewFile.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Im Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([previewFile.url])
                }
                .buttonStyle(.bordered)

                Button("Extern oeffnen") {
                    NSWorkspace.shared.open(previewFile.url)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            QuickLookPreviewContainer(url: previewFile.url)
                .frame(minWidth: 760, minHeight: 520)
        }
    }

    private func uniqueFileURL(in directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        let cleanName = sanitizedFilename(preferredName)
        let baseURL = directory.appendingPathComponent(cleanName)

        if !fileManager.fileExists(atPath: baseURL.path) {
            return baseURL
        }

        let ext = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private func sanitizedFilename(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = raw.components(separatedBy: invalid)
        let joined = parts.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "datei" : joined
    }

    private func scheduleTimeLine(for entry: ScheduleEntryDTO) -> String {
        let startDate = parseAPIDate(entry.start)
        let endDate = parseAPIDate(entry.end)

        if let startDate, let endDate {
            return "\(Self.scheduleTimeFormatter.string(from: startDate)) - \(Self.scheduleTimeFormatter.string(from: endDate))"
        }
        if let startDate {
            return "Ab \(Self.scheduleTimeFormatter.string(from: startDate))"
        }
        if let endDate {
            return "Bis \(Self.scheduleTimeFormatter.string(from: endDate))"
        }
        return "Keine Zeitangabe"
    }

    private func eventTimeLine(for event: EventDTO) -> String {
        let startDate = parseAPIDate(event.start)
        let endDate = parseAPIDate(event.end)

        if let startDate, let endDate {
            return "\(Self.eventDateTimeFormatter.string(from: startDate)) - \(Self.eventDateTimeFormatter.string(from: endDate))"
        }
        if let startDate {
            return "Ab \(Self.eventDateTimeFormatter.string(from: startDate))"
        }
        if let endDate {
            return "Bis \(Self.eventDateTimeFormatter.string(from: endDate))"
        }
        return "Keine Zeitangabe"
    }

    private func deduplicatedEvents(_ events: [EventDTO]) -> [EventDTO] {
        var seen: Set<String> = []
        var deduped: [EventDTO] = []
        deduped.reserveCapacity(events.count)

        for event in events {
            if seen.insert(event.id).inserted {
                deduped.append(event)
            }
        }

        return deduped
    }

    private func filterEventsToSemester(_ events: [EventDTO], semester: SemesterDTO) -> [EventDTO] {
        guard let semesterStart = semester.begin ?? semester.startOfLectures,
              let semesterEnd = semester.end ?? semester.endOfLectures else {
            return events
        }

        return events.filter { event in
            guard let eventStart = parseAPIDate(event.start) else {
                return true
            }
            return eventStart >= semesterStart && eventStart <= semesterEnd
        }
    }

    private func isScheduleEntryNow(_ entry: ScheduleEntryDTO) -> Bool {
        guard let startDate = parseAPIDate(entry.start), let endDate = parseAPIDate(entry.end) else {
            return false
        }
        let now = Date()
        return now >= startDate && now <= endDate
    }

    private func chatPreviewText(_ thread: StudIPResourceRepository.CourseChatThread) -> String? {
        if let content = nonEmpty(thread.previewText) {
            if content.contains("<"), content.contains(">") {
                return plainText(fromHTML: content)
            }
            return content
        }
        return nil
    }

    private func chatMessageText(_ message: BlubberPostingDTO) -> String {
        if let content = nonEmpty(message.content) {
            return content
        }
        if let contentHTML = nonEmpty(message.contentHTML) {
            return plainText(fromHTML: contentHTML) ?? contentHTML
        }
        return "(keine Nachricht)"
    }

    private func chatMessageMetadataLine(_ message: BlubberPostingDTO) -> String {
        var components: [String] = []

        if let discussionTime = parseAPIDate(message.discussionTime) {
            components.append(Self.fileDateFormatter.string(from: discussionTime))
        } else if let createdAt = parseAPIDate(message.mkdate) {
            components.append(Self.fileDateFormatter.string(from: createdAt))
        }

        if let authorName = displayName(forUserID: message.authorID) {
            components.append(authorName)
        } else if let authorID = normalizedUserID(message.authorID) {
            components.append("Autor \(authorID)")
        }

        return components.isEmpty ? "Nachricht \(message.id)" : components.joined(separator: " • ")
    }

    private func chatMetadataLine(_ thread: StudIPResourceRepository.CourseChatThread) -> String {
        var components: [String] = []

        if let contextType = nonEmpty(thread.contextType) {
            components.append(contextType.capitalized)
        }

        if let unseen = thread.unseenComments, unseen > 0 {
            components.append("\(unseen) ungelesen")
        }

        if let latest = thread.latestActivity {
            components.append("Aktiv: \(Self.fileDateFormatter.string(from: latest))")
        } else if let changed = thread.changedAt {
            components.append("Aktualisiert: \(Self.fileDateFormatter.string(from: changed))")
        }

        if let visited = thread.visitedAt {
            components.append("Zuletzt besucht: \(Self.fileDateFormatter.string(from: visited))")
        }

        return components.isEmpty ? "Keine Chat-Metadaten" : components.joined(separator: " • ")
    }

    private func wikiPreviewText(_ page: StudIPResourceRepository.CourseWikiPage) -> String? {
        guard let content = nonEmpty(page.content) else {
            return nil
        }

        let normalized = content.replacingOccurrences(of: "<!--HTML-->", with: "")
        if normalized.contains("<"), normalized.contains(">") {
            return plainText(fromHTML: normalized)
        }
        return nonEmpty(normalized)
    }

    private func selectedWikiPage(
        for courseID: String,
        pages: [StudIPResourceRepository.CourseWikiPage]
    ) -> StudIPResourceRepository.CourseWikiPage? {
        if let selectedID = selectedWikiPageIDByCourseID[courseID],
           let selected = pages.first(where: { $0.id == selectedID }) {
            return selected
        }
        return pages.first
    }

    private func wikiContentText(_ page: StudIPResourceRepository.CourseWikiPage) -> String {
        guard let raw = nonEmpty(page.content) else {
            return "Kein Inhalt vorhanden."
        }

        let normalized = raw.replacingOccurrences(of: "<!--HTML-->", with: "")
        guard normalized.contains("<"), normalized.contains(">"),
              let data = normalized.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return normalized
        }

        let parsed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return parsed.isEmpty ? normalized : parsed
    }

    private func wikiMetadataLine(_ page: StudIPResourceRepository.CourseWikiPage) -> String {
        var components: [String] = []

        if let authorName = nonEmpty(page.authorName) {
            components.append(authorName)
        } else if let authorID = nonEmpty(page.authorID) {
            components.append("Autor \(authorID)")
        }

        if let version = page.version {
            components.append("Version \(version)")
        }

        if let changedAt = page.changedAt {
            components.append("Geaendert: \(Self.fileDateFormatter.string(from: changedAt))")
        }

        return components.isEmpty ? "Keine Wiki-Metadaten" : components.joined(separator: " • ")
    }

    private func forumMetadataLine(_ category: StudIPResourceRepository.CourseForumCategory) -> String {
        var components: [String] = []

        if let position = category.position {
            components.append("Position \(position)")
        }
        components.append("ID \(category.id)")

        return components.joined(separator: " • ")
    }

    private func forumEntryMetadataLine(_ entry: ForumEntryDTO) -> String {
        var components: [String] = []

        if let authorName = displayName(forUserID: entry.authorID) {
            components.append(authorName)
        } else if let authorID = normalizedUserID(entry.authorID) {
            components.append("Autor \(authorID)")
        }

        if let area = entry.area {
            components.append("Bereich \(area)")
        }
        components.append("ID \(entry.id)")

        return components.joined(separator: " • ")
    }

    private func newsMetadataLine(_ newsItem: NewsDTO) -> String {
        var components: [String] = []

        if let updatedAt = parseAPIDate(newsItem.chdate) {
            components.append("Aktualisiert: \(Self.fileDateFormatter.string(from: updatedAt))")
        } else if let createdAt = parseAPIDate(newsItem.mkdate) {
            components.append("Erstellt: \(Self.fileDateFormatter.string(from: createdAt))")
        }

        if newsItem.commentsAllowed == true {
            components.append("Kommentare aktiv")
        }

        return components.isEmpty ? "ID \(newsItem.id)" : components.joined(separator: " • ")
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

    private func plainText(fromHTML html: String) -> String? {
        guard let data = html.data(using: .utf8) else { return nil }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            let normalized = attributed.string
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return nonEmpty(normalized)
        }
        return nonEmpty(html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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

    private static let scheduleDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let scheduleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let eventDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let participantRoleOrder = ["root", "admin", "dozent", "tutor", "autor"]

    private func groupedParticipantsByRole(
        _ participants: [StudIPResourceRepository.CourseParticipant]
    ) -> [String: [StudIPResourceRepository.CourseParticipant]] {
        var grouped: [String: [StudIPResourceRepository.CourseParticipant]] = [:]
        grouped.reserveCapacity(Self.participantRoleOrder.count)

        for participant in participants {
            guard let roleKey = participantRoleKey(for: participant.permission) else {
                continue
            }
            grouped[roleKey, default: []].append(participant)
        }

        for roleKey in grouped.keys {
            grouped[roleKey]?.sort { lhs, rhs in
                let lhsPosition = lhs.position ?? Int.max
                let rhsPosition = rhs.position ?? Int.max
                if lhsPosition != rhsPosition {
                    return lhsPosition < rhsPosition
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }

        return grouped
    }

    private func participantRoleKey(for permission: String?) -> String? {
        guard let normalized = nonEmpty(permission)?.lowercased() else {
            return nil
        }
        guard Self.participantRoleOrder.contains(normalized) else {
            return nil
        }
        return normalized
    }

    private func participantRoleTitle(for roleKey: String) -> String {
        switch roleKey {
        case "root":
            return "Root"
        case "admin":
            return "Admin"
        case "dozent":
            return "Dozent"
        case "tutor":
            return "Tutor"
        case "autor":
            return "Autor"
        default:
            return roleKey.capitalized
        }
    }

    private func openMail(for participant: StudIPResourceRepository.CourseParticipant) {
        guard let email = nonEmpty(participant.email) else {
            return
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email

        guard let url = components.url else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func participantInfoSheet(for participant: StudIPResourceRepository.CourseParticipant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(participant.displayName)
                .font(.title3.weight(.semibold))

            Divider()

            participantInfoRow("User-ID", participant.userID)
            participantInfoRow("E-Mail", nonEmpty(participant.email))
            participantInfoRow("Rolle", nonEmpty(participant.permission))
            participantInfoRow("Label", nonEmpty(participant.label))
            participantInfoRow("Position", participant.position.map(String.init))
            participantInfoRow("Gruppe", participant.group.map(String.init))
            participantInfoRow("Erstellt", nonEmpty(participant.mkdate))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 260)
    }

    @ViewBuilder
    private func participantInfoRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            if let value {
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Text("-")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = AppContainer()
    ContentView(
        statusController: container.statusController,
        syncScheduler: container.syncScheduler,
        semesterSelectionStore: container.semesterSelectionStore,
        repository: container.resourceRepository,
        debugWindowState: container.debugWindowState
    )
}
#endif

private struct QuickLookPreviewContainer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        if let view = QLPreviewView(frame: .zero, style: .normal) {
            view.previewItem = url as NSURL
            return view
        }

        let fallback = NSTextField(labelWithString: "Vorschau ist fuer diese Datei nicht verfuegbar.")
        fallback.alignment = .center
        fallback.textColor = .secondaryLabelColor
        return fallback
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? QLPreviewView)?.previewItem = url as NSURL
    }
}
