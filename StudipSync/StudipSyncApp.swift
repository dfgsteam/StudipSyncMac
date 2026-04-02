import SwiftUI

@main
struct StudipSyncApp: App {
    @State private var container = AppContainer()
    @State private var hasWarmedUpCurrentUser = false

    var body: some Scene {
        WindowGroup("StudipSync") {
            ContentView(
                statusController: container.statusController,
                syncScheduler: container.syncScheduler,
                semesterSelectionStore: container.semesterSelectionStore,
                repository: container.resourceRepository,
                debugWindowState: container.debugWindowState
            )
            .onAppear {
                container.syncScheduler.start(intervalMinutes: container.settingsStore.configuration.syncIntervalMinutes)

                if !hasWarmedUpCurrentUser {
                    hasWarmedUpCurrentUser = true
                    Task {
                        await container.resourceRepository.warmupCurrentUserID()
                    }
                }
            }
        }

        MenuBarExtra("StudipSync", systemImage: container.statusController.syncState.symbolName) {
            MenuBarRootView(
                statusController: container.statusController,
                syncScheduler: container.syncScheduler
            )
        }

        WindowGroup(id: "debugWindow") {
            DebugWindowView(
                repository: container.resourceRepository,
                state: container.debugWindowState
            )
        }

        Settings {
            SettingsView(
                settingsStore: container.settingsStore,
                keychainService: container.keychainService
            )
        }
    }
}
