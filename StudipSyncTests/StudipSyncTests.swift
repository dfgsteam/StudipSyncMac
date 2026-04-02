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
    @MainActor
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

    @Test
    func apiPathResolverBuildsCanonicalCoursesURLFromHostBaseURL() {
        let baseURL = URL(string: "https://studip.uni-goettingen.de")!
        let url = StudIPAPIPathResolver.buildURL(baseURL: baseURL, path: "/v1/courses", queryItems: [])

        #expect(url?.absoluteString == "https://studip.uni-goettingen.de/jsonapi.php/v1/courses")
    }

    @Test
    func apiPathResolverDoesNotDuplicatePrefixWhenBaseURLAlreadyContainsV1() {
        let baseURL = URL(string: "https://studip.uni-goettingen.de/jsonapi.php/v1")!
        let url = StudIPAPIPathResolver.buildURL(baseURL: baseURL, path: "/v1/courses", queryItems: [])

        #expect(url?.absoluteString == "https://studip.uni-goettingen.de/jsonapi.php/v1/courses")
    }

    @Test
    func apiPathResolverBuildsCourseDetailURLAndPreservesQueryItems() {
        let baseURL = URL(string: "https://studip.uni-goettingen.de/jsonapi.php")!
        let query = [URLQueryItem(name: "filter[semester]", value: "abc123")]
        let url = StudIPAPIPathResolver.buildURL(
            baseURL: baseURL,
            path: "/jsonapi.php/v1/courses/course123",
            queryItems: query
        )

        #expect(url?.absoluteString == "https://studip.uni-goettingen.de/jsonapi.php/v1/courses/course123?filter%5Bsemester%5D=abc123")
    }

    @Test
    func studIPQueryBuildsCollectionPathAndFilterQueryItems() {
        let query = StudIPQuery<CourseResource>()
            .whereFilter("semester", equals: "s1")
            .paginate(offset: 10, limit: 25)

        #expect(query.path == "/v1/courses")
        #expect(query.queryItems == [
            URLQueryItem(name: "filter[semester]", value: "s1"),
            URLQueryItem(name: "page[offset]", value: "10"),
            URLQueryItem(name: "page[limit]", value: "25")
        ])
    }

    @Test
    func studIPQueryBuildsDetailPathWithTrimmedID() {
        let query = StudIPQuery<CourseResource>().byID("/course123/")
        #expect(query.path == "/v1/courses/course123")
    }

    @Test
    func studIPSemesterQueryBuildsCollectionPathAndPagination() {
        let query = StudIPQuery<SemesterResource>().paginate(offset: 5, limit: 10)

        #expect(query.path == "/v1/semesters")
        #expect(query.queryItems == [
            URLQueryItem(name: "page[offset]", value: "5"),
            URLQueryItem(name: "page[limit]", value: "10")
        ])
    }

    @Test
    func studIPSemesterQueryBuildsDetailPath() {
        let query = StudIPQuery<SemesterResource>().byID("abc123")
        #expect(query.path == "/v1/semesters/abc123")
    }
}
