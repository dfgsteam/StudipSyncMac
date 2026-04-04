import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private(set) var configuration: AppConfiguration

    private let defaults: UserDefaults
    private let key = "studipsync.configuration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: key),
           let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            self.configuration = configuration
        } else {
            self.configuration = .default
        }
    }

    func updateBaseURL(_ url: URL) {
        configuration.baseURL = url
        persist()
    }

    func updateSyncInterval(minutes: Int) {
        configuration.syncIntervalMinutes = max(1, minutes)
        persist()
    }

    func updateMaxConcurrentFileDownloads(_ count: Int) {
        configuration.maxConcurrentFileDownloads = min(4, max(2, count))
        persist()
    }

    func updatePauseSyncOnLowPowerMode(_ isEnabled: Bool) {
        configuration.pauseSyncOnLowPowerMode = isEnabled
        persist()
    }

    func updateSyncOnlyOnWiFi(_ isEnabled: Bool) {
        configuration.syncOnlyOnWiFi = isEnabled
        persist()
    }

    func updateRootFolderBookmark(_ bookmark: Data?) {
        configuration.rootFolderBookmark = bookmark
        persist()
    }

    func updateActiveSemesterIDs(_ ids: Set<String>) {
        configuration.activeSemesterIDs = ids
        persist()
    }

    func updateSemesterSearchStartDate(_ date: Date?) {
        if let date {
            configuration.semesterSearchStartDate = Calendar.current.startOfDay(for: date)
        } else {
            configuration.semesterSearchStartDate = nil
        }
        persist()
    }

    func updateSemesterSearchEndDate(_ date: Date?) {
        if let date {
            configuration.semesterSearchEndDate = Calendar.current.startOfDay(for: date)
        } else {
            configuration.semesterSearchEndDate = nil
        }
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(configuration)
            defaults.set(data, forKey: key)
        } catch {
            AppLogger.error("Failed to persist configuration: \(error.localizedDescription)")
        }
    }
}
