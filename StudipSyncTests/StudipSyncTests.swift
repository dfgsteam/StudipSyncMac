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
        let minDateToPersist = Date(timeIntervalSince1970: 1_648_771_200) // 2022-04-01T00:00:00Z
        let maxDateToPersist = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z
        store.updateSemesterSearchStartDate(minDateToPersist)
        store.updateSemesterSearchEndDate(maxDateToPersist)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.configuration.baseURL.absoluteString == "https://example.edu")
        #expect(reloaded.configuration.syncIntervalMinutes == 15)
        #expect(reloaded.configuration.semesterSearchStartDate == Calendar.current.startOfDay(for: minDateToPersist))
        #expect(reloaded.configuration.semesterSearchEndDate == Calendar.current.startOfDay(for: maxDateToPersist))
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

    @Test
    func courseDTODecodesDetailedPayload() throws {
        let json = """
        {
          "data": {
            "type": "courses",
            "id": "8c03b7332cccf554d135152ce9f2db25",
            "attributes": {
              "course-number": null,
              "title": "Studieren mit Kind",
              "subtitle": null,
              "course-type": 99,
              "description": "Ein Raum fuer studierende Eltern.",
              "location": null,
              "miscellaneous": null
            },
            "relationships": {
              "institute": {
                "data": {
                  "type": "institutes",
                  "id": "03868081c9133f74d1f83ab5271fd3f5"
                }
              },
              "start-semester": {
                "data": {
                  "type": "semesters",
                  "id": "1e9b80f9d228270fc77a0fd31ad057d8"
                }
              },
              "sem-class": {
                "data": {
                  "type": "sem-classes",
                  "id": "99"
                }
              },
              "sem-type": {
                "data": {
                  "type": "sem-types",
                  "id": "99"
                }
              }
            }
          }
        }
        """

        let rawData = Data(json.utf8)
        let topLevel = try JSONSerialization.jsonObject(with: rawData) as? [String: Any]
        let courseObject = topLevel?["data"] as? [String: Any]
        let courseData = try JSONSerialization.data(withJSONObject: courseObject as Any)
        let course = try JSONDecoder().decode(CourseDTO.self, from: courseData)

        #expect(course.id == "8c03b7332cccf554d135152ce9f2db25")
        #expect(course.title == "Studieren mit Kind")
        #expect(course.courseType == 99)
        #expect(course.instituteID == "03868081c9133f74d1f83ab5271fd3f5")
        #expect(course.startSemesterRef == "1e9b80f9d228270fc77a0fd31ad057d8")
        #expect(course.semClassID == "99")
        #expect(course.semTypeID == "99")
    }
}
