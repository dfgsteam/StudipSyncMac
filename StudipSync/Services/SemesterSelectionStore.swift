import Foundation
import Observation

@MainActor
@Observable
final class SemesterSelectionStore {
    private(set) var activeSemesterIDs: Set<String>

    private let settingsStore: SettingsStore
    private let defaults: UserDefaults
    private let selectionsByBaseURLDefaultsKey = "studipsync.active-semester-ids.by-base-url.v1"
    private var currentBaseURLKey: String

    init(settingsStore: SettingsStore, defaults: UserDefaults = .standard) {
        self.settingsStore = settingsStore
        self.defaults = defaults
        self.currentBaseURLKey = Self.baseURLKey(for: settingsStore.configuration.baseURL)
        self.activeSemesterIDs = []

        let selectionsByBaseURL = loadSelectionsByBaseURL()
        if let persistedSelection = selectionsByBaseURL[currentBaseURLKey] {
            self.activeSemesterIDs = Set(persistedSelection)
        } else {
            // Migration path for older config versions with a single global selection set.
            let legacySelection = settingsStore.configuration.activeSemesterIDs
            self.activeSemesterIDs = legacySelection

            if !legacySelection.isEmpty {
                var updatedSelections = selectionsByBaseURL
                updatedSelections[currentBaseURLKey] = Array(legacySelection).sorted()
                saveSelectionsByBaseURL(updatedSelections)
            }
        }

        settingsStore.updateActiveSemesterIDs(activeSemesterIDs)
    }

    func setActive(_ isActive: Bool, semesterID: String) {
        if isActive {
            activeSemesterIDs.insert(semesterID)
        } else {
            activeSemesterIDs.remove(semesterID)
        }

        persistCurrentSelection()
    }

    func isActive(semesterID: String) -> Bool {
        activeSemesterIDs.contains(semesterID)
    }

    func reloadForCurrentBaseURL() {
        let nextBaseURLKey = Self.baseURLKey(for: settingsStore.configuration.baseURL)
        guard nextBaseURLKey != currentBaseURLKey else {
            return
        }

        currentBaseURLKey = nextBaseURLKey
        let selectionsByBaseURL = loadSelectionsByBaseURL()
        activeSemesterIDs = Set(selectionsByBaseURL[nextBaseURLKey] ?? [])
        settingsStore.updateActiveSemesterIDs(activeSemesterIDs)
    }

    private func persistCurrentSelection() {
        var selectionsByBaseURL = loadSelectionsByBaseURL()
        selectionsByBaseURL[currentBaseURLKey] = Array(activeSemesterIDs).sorted()
        saveSelectionsByBaseURL(selectionsByBaseURL)
        settingsStore.updateActiveSemesterIDs(activeSemesterIDs)
    }

    private func loadSelectionsByBaseURL() -> [String: [String]] {
        guard let data = defaults.data(forKey: selectionsByBaseURLDefaultsKey) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func saveSelectionsByBaseURL(_ selectionsByBaseURL: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(selectionsByBaseURL) else {
            return
        }

        defaults.set(data, forKey: selectionsByBaseURLDefaultsKey)
    }

    private static func baseURLKey(for baseURL: URL) -> String {
        var key = baseURL.absoluteString.lowercased()
        if key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }
}
