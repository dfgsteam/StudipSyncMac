import Foundation

@MainActor
final class AppContainer {
    let settingsStore: SettingsStore
    let keychainService: KeychainService
    let syncEngine: SyncEngine
    let syncScheduler: SyncScheduler
    let statusController: MenuBarStatusController
    let semesterSelectionStore: SemesterSelectionStore
    let apiClient: StudIPAPIClient
    let resourceRepository: StudIPResourceRepository
    let metadataCache: MetadataCache
    let sharedCourseParticipationCache: SharedCourseParticipationCache
    let debugWindowState: DebugWindowState

    init() {
        let settingsStore = SettingsStore()
        let keychainService = KeychainService()
        let statusController = MenuBarStatusController()
        let metadataCache = MetadataCache()
        let sharedCourseParticipationCache = SharedCourseParticipationCache()
        let apiClient = StudIPAPIClient(settingsStore: settingsStore, keychainService: keychainService)
        let resourceRepository = StudIPResourceRepository(
            apiClient: apiClient,
            settingsStore: settingsStore,
            metadataCache: metadataCache
        )
        let syncEngine = SyncEngine(
            repository: resourceRepository,
            settingsStore: settingsStore
        )

        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.syncEngine = syncEngine
        self.statusController = statusController
        self.syncScheduler = SyncScheduler(
            syncEngine: syncEngine,
            statusController: statusController,
            settingsStore: settingsStore
        )
        self.semesterSelectionStore = SemesterSelectionStore(settingsStore: settingsStore)
        self.apiClient = apiClient
        self.resourceRepository = resourceRepository
        self.metadataCache = metadataCache
        self.sharedCourseParticipationCache = sharedCourseParticipationCache
        self.debugWindowState = DebugWindowState()
    }
}
