import SwiftUI

struct ContentView: View {
    enum SidebarPage: String, CaseIterable, Hashable, Identifiable {
        case start
        case profil
        case benutzer
        case veranstaltungen
        case einrichtungen
        case platzhalter

        var id: String { rawValue }

        var title: String {
            switch self {
            case .start: return "Start"
            case .profil: return "Profil"
            case .benutzer: return "Benutzer"
            case .veranstaltungen: return "Veranstaltungen"
            case .einrichtungen: return "Einrichtungen"
            case .platzhalter: return "Platzhalter"
            }
        }

        var systemImage: String {
            switch self {
            case .start: return "house"
            case .profil: return "person.crop.circle"
            case .benutzer: return "person.2"
            case .veranstaltungen: return "book.closed"
            case .einrichtungen: return "building.2"
            case .platzhalter: return "square.dashed"
            }
        }
    }

    struct CourseDetailSection: Identifiable, Hashable {
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

    struct QuickLookPreviewFile: Identifiable {
        let id: String
        let title: String
        let url: URL
    }

    struct SidebarNavigationState: Equatable {
        let page: SidebarPage
        let semesterID: String?
        let courseID: String?
    }

    let statusController: MenuBarStatusController
    let syncScheduler: SyncScheduler
    let semesterSelectionStore: SemesterSelectionStore
    let repository: StudIPResourceRepository
    let sharedCourseParticipationCache: SharedCourseParticipationCache
    let debugWindowState: DebugWindowState

    @Environment(\.openWindow) var openWindow

    @State var semesterViewModel: SemesterListViewModel
    @State var selectedSidebarPage: SidebarPage? = .start
    @State var sidebarNavigationBackStack: [SidebarNavigationState] = []
    @State var sidebarNavigationForwardStack: [SidebarNavigationState] = []
    @State var isRestoringSidebarNavigationState = false
    @State var sidebarSemesterSearchQuery = ""
    @State var selectedSemesterID: String?
    @State var selectedCourseID: String?
    @State var courseListSearchQuery = ""
    @State var startScheduleEntries: [ScheduleEntryDTO] = []
    @State var startScheduleError: String?
    @State var isLoadingStartSchedule = false
    @State var startScheduleLoadedDate: Date?
    @State var selectedSemesterCalendarDay = Calendar.current.startOfDay(for: Date())
    @State var selectedUserCalendarDay = Calendar.current.startOfDay(for: Date())
    @State var semesterScheduleEventsBySemesterID: [String: [EventDTO]] = [:]
    @State var semesterScheduleErrorsBySemesterID: [String: String] = [:]
    @State var loadingSemesterScheduleIDs: Set<String> = []
    @State var semesterScheduleLoadedAtBySemesterID: [String: Date] = [:]
    @State var coursesBySemesterID: [String: [CourseDTO]] = [:]
    @State var prefetchingSemesterCourseIDs: Set<String> = []
    @State var coursePrefetchErrorsBySemesterID: [String: String] = [:]
    @State var courses: [CourseDTO] = []
    @State var isLoadingCourses = false
    @State var isLoadingCourseDetail = false
    @State var courseStatusMessage = "Waehle ein Semester aus"
    @State var selectedCourseDetailSectionID = CourseDetailSection.description.id
    @State var foldersByContextKey: [String: [FolderDTO]] = [:]
    @State var filesByContextKey: [String: [CourseFileRefDTO]] = [:]
    @State var fileErrorsByContextKey: [String: String] = [:]
    @State var fileFolderPathByCourseID: [String: [FolderDTO]] = [:]
    @State var downloadingFileIDs: Set<String> = []
    @State var fileDownloadErrorsByFileID: [String: String] = [:]
    @State var previewingFileIDs: Set<String> = []
    @State var filePreviewErrorsByFileID: [String: String] = [:]
    @State var selectedQuickLookFile: QuickLookPreviewFile?
    @State var quickLookSecurityScopedURL: URL?
    @State var isLoadingFiles = false
    @State var chatsByCourseID: [String: [StudIPResourceRepository.CourseChatThread]] = [:]
    @State var chatErrorsByCourseID: [String: String] = [:]
    @State var isLoadingChats = false
    @State var selectedChatThreadIDByCourseID: [String: String] = [:]
    @State var chatMessagesByThreadID: [String: [BlubberPostingDTO]] = [:]
    @State var chatMessageErrorsByThreadID: [String: String] = [:]
    @State var loadingChatThreadIDs: Set<String> = []
    @State var wikisByCourseID: [String: [StudIPResourceRepository.CourseWikiPage]] = [:]
    @State var wikiErrorsByCourseID: [String: String] = [:]
    @State var isLoadingWikis = false
    @State var selectedWikiPageIDByCourseID: [String: String] = [:]
    @State var participantsByCourseID: [String: [StudIPResourceRepository.CourseParticipant]] = [:]
    @State var participantErrorsByCourseID: [String: String] = [:]
    @State var isLoadingParticipants = false
    @State var courseNewsByCourseID: [String: [NewsDTO]] = [:]
    @State var courseNewsErrorsByCourseID: [String: String] = [:]
    @State var isLoadingCourseNews = false
    @State var selectedNewsIDByCourseID: [String: String] = [:]
    @State var newsCommentsByNewsID: [String: [NewsCommentDTO]] = [:]
    @State var newsCommentErrorsByNewsID: [String: String] = [:]
    @State var loadingNewsCommentIDs: Set<String> = []
    @State var forumsByCourseID: [String: [StudIPResourceRepository.CourseForumCategory]] = [:]
    @State var forumErrorsByCourseID: [String: String] = [:]
    @State var isLoadingForums = false
    @State var selectedForumCategoryIDByCourseID: [String: String] = [:]
    @State var forumEntriesByCategoryID: [String: [ForumEntryDTO]] = [:]
    @State var forumEntryErrorsByCategoryID: [String: String] = [:]
    @State var loadingForumCategoryIDs: Set<String> = []
    @State var selectedForumEntryIDByCategoryID: [String: String] = [:]
    @State var forumRepliesByEntryID: [String: [ForumEntryDTO]] = [:]
    @State var forumReplyErrorsByEntryID: [String: String] = [:]
    @State var loadingForumEntryIDs: Set<String> = []
    @State var userDisplayNameByID: [String: String] = [:]
    @State var loadingUserNameIDs: Set<String> = []
    @State var prefetchingCourseIDs: Set<String> = []
    @State var detailSearchTextBySectionID: [String: String] = [:]
    @State var detailSectionLoadedAtByKey: [String: Date] = [:]
    @AppStorage("remembered_user_ids_csv") var rememberedUserIDsCSV = ""
    @State var userSearchQuery = ""
    @State var userSearchResults: [UserDTO] = []
    @State var isLoadingUserSearch = false
    @State var userSearchError: String?
    @State var lastUserSearchDate: Date?
    @State var selectedUserID: String?
    @State var userNavigationHistory: [String] = []
    @State var userNavigationHistoryIndex: Int = -1
    @State var meUserID: String?
    @State var userDetailByID: [String: UserDTO] = [:]
    @State var userDetailErrorByID: [String: String] = [:]
    @State var loadingUserDetailIDs: Set<String> = []
    @State var userInstituteMembershipsByID: [String: [InstituteMembershipDTO]] = [:]
    @State var userNewsByID: [String: [NewsDTO]] = [:]
    @State var userCoursesByID: [String: [CourseDTO]] = [:]
    @State var userUpcomingEventsByID: [String: [EventDTO]] = [:]
    @State var userScheduleByID: [String: [ScheduleEntryDTO]] = [:]
    @State var userExtrasErrorByID: [String: String] = [:]
    @State var rememberedUsersByID: [String: UserDTO] = [:]
    @State var isLoadingRememberedUsers = false
    @State var sharedCoursesByUserID: [String: [SharedCourseParticipationCache.SharedCourseEntry]] = [:]
    @State var sharedCoursesUpdatedAt: Date?
    @State var sharedCoursesNamespaceKey: String?
    @State var isLoadingSharedCourses = false
    @State var sharedCoursesError: String?
    @State var institutionSearchQuery = ""
    @State var institutions: [InstituteDTO] = []
    @State var isLoadingInstitutions = false
    @State var institutionsError: String?
    @State var institutionsLoadedDate: Date?
    @State var selectedInstituteID: String?
    @State var selectedInstitutionSemesterID: String?
    @State var institutionCourseSearchQuery = ""
    @State var institutionCoursesByKey: [String: [CourseDTO]] = [:]
    @State var institutionCourseErrorsByKey: [String: String] = [:]
    @State var loadingInstitutionCourseKeys: Set<String> = []
    @State var courseCatalogQuery = ""
    @State var selectedCatalogSemesterID: String?
    @State var catalogCourses: [CourseDTO] = []
    @State var isLoadingCatalogCourses = false
    @State var catalogCoursesLoadedDate: Date?
    @State var catalogCoursesError: String?
    @State var lastCatalogLoadRequestKey: String?
    @State var selectedCatalogCourseID: String?
    @State var selectedCatalogCourseDetail: CourseDTO?
    @State var selectedCatalogCourseDetailError: String?
    @State var isLoadingCatalogCourseDetail = false
    @State var enrolledCourseIDs: Set<String> = []
    @State var isLoadingEnrolledCourses = false
    @State var enrollmentInFlightCourseIDs: Set<String> = []
    @State var enrollmentErrorByCourseID: [String: String] = [:]
    @State var meProfile: UserDTO?
    @State var meProfileError: String?
    @State var isLoadingMeProfile = false
    @State var meProfileLoadedDate: Date?
    @State var meProfileRawJSON: String?
    @State var meProfileRawError: String?
    @State var isLoadingMeProfileRaw = false
    @State var isShowingMeProfileRawJSON = false
    @State var apiBaseURLForAssets: URL?

    init(
        statusController: MenuBarStatusController,
        syncScheduler: SyncScheduler,
        semesterSelectionStore: SemesterSelectionStore,
        repository: StudIPResourceRepository,
        sharedCourseParticipationCache: SharedCourseParticipationCache,
        debugWindowState: DebugWindowState
    ) {
        self.statusController = statusController
        self.syncScheduler = syncScheduler
        self.semesterSelectionStore = semesterSelectionStore
        self.repository = repository
        self.sharedCourseParticipationCache = sharedCourseParticipationCache
        self.debugWindowState = debugWindowState
        self._semesterViewModel = State(initialValue: SemesterListViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if selectedSemesterID != nil {
                NavigationSplitView {
                    pagesSidebar
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                } content: {
                    coursesColumn
                        .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
                } detail: {
                    detailColumn
                }
            } else if usesSingleDetailLayoutForSelectedPage {
                NavigationSplitView {
                    pagesSidebar
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                } detail: {
                    detailForSelectedPage
                }
            } else {
                NavigationSplitView {
                    pagesSidebar
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                } content: {
                    contentForSelectedPage
                        .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
                } detail: {
                    detailForSelectedPage
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            appToolbarActions
        }
        .frame(minWidth: 980, minHeight: 560)
        .background(appBackgroundGradient)
        .groupBoxStyle(StudipSoftGroupBoxStyle())
        .task {
            if semesterViewModel.semesters.isEmpty {
                semesterViewModel.loadSemesters()
            }
        }
        .task {
            if apiBaseURLForAssets == nil {
                apiBaseURLForAssets = await repository.currentBaseURL()
            }
        }
        .task(id: selectedSemesterID) {
            debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
            selectedSemesterCalendarDay = Calendar.current.startOfDay(for: Date())
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
            pruneCourseOverviewCacheToKnownSemesters()
            await prefetchCourseOverviewsForLoadedSemesters()
        }
        .task(id: startScheduleTaskID) {
            await loadStartScheduleIfNeeded()
        }
        .task(id: semesterScheduleTaskID) {
            await loadSemesterScheduleIfNeeded()
        }
        .sheet(item: $selectedQuickLookFile) { previewFile in
            quickLookSheet(for: previewFile)
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
        sharedCourseParticipationCache: container.sharedCourseParticipationCache,
        debugWindowState: container.debugWindowState
    )
}
#endif
