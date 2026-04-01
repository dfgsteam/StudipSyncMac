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

    init() {
        let settingsStore = SettingsStore()
        let keychainService = KeychainService()
        let syncEngine = SyncEngine()
        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.syncEngine = syncEngine
        self.syncScheduler = SyncScheduler(syncEngine: syncEngine)
        self.statusController = MenuBarStatusController()
        self.semesterSelectionStore = SemesterSelectionStore(settingsStore: settingsStore)
        self.apiClient = StudIPAPIClient(settingsStore: settingsStore, keychainService: keychainService)
        self.resourceRepository = StudIPResourceRepository(apiClient: apiClient)
        self.metadataCache = MetadataCache()
    }
}
