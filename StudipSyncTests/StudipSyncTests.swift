import Foundation
import Testing
@testable import StudipSync

struct StudipSyncTests {
    @Test
    func baseURLNormalizerAcceptsHTTPSAndTrimsTrailingSlash() {
        let normalized = BaseURLNormalizer.normalizeHTTPSURL("  https://studip.uni-goettingen.de/  ")

        #expect(normalized != nil)
        #expect(normalized?.absoluteString == "https://studip.uni-goettingen.de")
    }

    @Test
    func baseURLNormalizerRejectsNonHTTPS() {
        let normalized = BaseURLNormalizer.normalizeHTTPSURL("http://studip.uni-goettingen.de")
        #expect(normalized == nil)
    }

    @Test
    @MainActor
    func settingsStorePersistsBaseURLAndInterval() {
        let suiteName = "StudipSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.updateBaseURL(URL(string: "https://example.edu")!)
        store.updateSyncInterval(minutes: 15)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.configuration.baseURL.absoluteString == "https://example.edu")
        #expect(reloaded.configuration.syncIntervalMinutes == 15)
    }

    @Test
    func metadataCacheSavesAndLoadsSemesters() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudipSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = MetadataCache(cacheRootURL: tempDir)
        let baseURL = URL(string: "https://studip.example.edu")!
        let semesters = [SemesterDTO(id: "s1", title: "SoSe 2026")]

        try await cache.save(semesters: semesters, baseURL: baseURL)
        let snapshot = try await cache.load(baseURL: baseURL)

        #expect(snapshot != nil)
        #expect(snapshot?.semesters == semesters)
    }
}
