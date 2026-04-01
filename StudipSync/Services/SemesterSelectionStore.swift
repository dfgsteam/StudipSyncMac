import Foundation
import Observation

@MainActor
@Observable
final class SemesterSelectionStore {
    private(set) var activeSemesterIDs: Set<String>

    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.activeSemesterIDs = settingsStore.configuration.activeSemesterIDs
    }

    func setActive(_ isActive: Bool, semesterID: String) {
        if isActive {
            activeSemesterIDs.insert(semesterID)
        } else {
            activeSemesterIDs.remove(semesterID)
        }
        settingsStore.updateActiveSemesterIDs(activeSemesterIDs)
    }

    func isActive(semesterID: String) -> Bool {
        activeSemesterIDs.contains(semesterID)
    }
}
