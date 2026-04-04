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
    @MainActor
    func metadataCacheClearRemovesCurrentBaseURLSnapshot() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudipSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = MetadataCache(cacheRootURL: tempDir)
        let baseURL = URL(string: "https://studip.example.edu")!
        let semesters = [SemesterDTO(id: "s1", title: "SoSe 2026")]

        try await cache.save(semesters: semesters, baseURL: baseURL)
        let savedSnapshot = try await cache.load(baseURL: baseURL)
        #expect(savedSnapshot != nil)

        try await cache.clear(baseURL: baseURL)
        let clearedSnapshot = try await cache.load(baseURL: baseURL)
        #expect(clearedSnapshot == nil)
    }

    @Test
    @MainActor
    func metadataCachePersistsCoursesBySemester() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudipSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = MetadataCache(cacheRootURL: tempDir)
        let baseURL = URL(string: "https://studip.example.edu")!
        let semesterID = "semester-1"
        let courses = [makeCourseDTO(id: "course-1", title: "Algo 1", semesterID: semesterID)]

        try await cache.saveCourses(courses, for: semesterID, baseURL: baseURL)
        let loadedCourses = try await cache.loadCourses(for: semesterID, baseURL: baseURL)
        #expect(loadedCourses == courses)

        try await cache.save(semesters: [SemesterDTO(id: semesterID, title: "SoSe 2026")], baseURL: baseURL)
        let stillLoaded = try await cache.loadCourses(for: semesterID, baseURL: baseURL)
        #expect(stillLoaded == courses)
    }

    @Test
    @MainActor
    func keychainServiceRoundtripForAPIKeyAndBasicCredentials() throws {
        let service = KeychainService()
        let baseURL = URL(string: "https://studipsync-keychain-\(UUID().uuidString).example")!
        defer { try? service.deleteCredentials(for: baseURL) }

        try service.saveAPIKey("test-api-key", for: baseURL)
        let apiKey = try service.readAPIKey(for: baseURL)
        #expect(apiKey == "test-api-key")

        try service.saveCredentials(HTTPBasicCredentials(username: "alice", password: "secret"), for: baseURL)
        let credentials = try service.readCredentials(for: baseURL)
        #expect(credentials?.username == "alice")
        #expect(credentials?.password == "secret")

        try service.deleteCredentials(for: baseURL)
        #expect(try service.readAPIKey(for: baseURL) == nil)
        #expect(try service.readCredentials(for: baseURL) == nil)
    }

    @Test
    @MainActor
    func sharedCourseParticipationCacheCanBeCleared() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudipSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = SharedCourseParticipationCache(cacheRootURL: tempDir)
        let baseURL = URL(string: "https://studip.example.edu")!
        let snapshot = SharedCourseParticipationCache.Snapshot(
            ownerUserID: "owner-1",
            updatedAt: Date(),
            version: 1,
            entriesByUserID: [
                "user-a": [
                    .init(courseID: "c1", courseTitle: "Kurs A", semesterID: "s1", semesterTitle: "SoSe")
                ]
            ]
        )

        try await cache.save(baseURL: baseURL, snapshot: snapshot)
        let beforeClear = try await cache.load(baseURL: baseURL, ownerUserID: "owner-1")
        #expect(beforeClear != nil)

        try await cache.clearAll()
        let afterClear = try await cache.load(baseURL: baseURL, ownerUserID: "owner-1")
        #expect(afterClear == nil)
    }

    @Test
    @MainActor
    func semesterSelectionStoreSeparatesSelectionsByBaseURL() {
        let suiteName = "StudipSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.updateBaseURL(URL(string: "https://instanz-a.example")!)

        let selectionStore = SemesterSelectionStore(settingsStore: settings, defaults: defaults)
        selectionStore.setActive(true, semesterID: "semester-a")
        #expect(selectionStore.isActive(semesterID: "semester-a"))

        settings.updateBaseURL(URL(string: "https://instanz-b.example")!)
        selectionStore.reloadForCurrentBaseURL()
        #expect(!selectionStore.isActive(semesterID: "semester-a"))

        selectionStore.setActive(true, semesterID: "semester-b")
        #expect(selectionStore.isActive(semesterID: "semester-b"))

        settings.updateBaseURL(URL(string: "https://instanz-a.example")!)
        selectionStore.reloadForCurrentBaseURL()
        #expect(selectionStore.isActive(semesterID: "semester-a"))
        #expect(!selectionStore.isActive(semesterID: "semester-b"))
    }

    @Test
    func syncPathPlannerAddsDeterministicSuffixForDuplicateFileNames() {
        let first = StudIPCourseFileRef(
            id: "aaaaaaaa11111111",
            name: "Skript.pdf",
            description: nil,
            ownerName: nil,
            mimeType: nil,
            downloads: nil,
            fileSize: nil,
            createdAt: nil,
            changedAt: nil,
            isReadable: true,
            isDownloadable: true,
            downloadURL: nil
        )
        let second = StudIPCourseFileRef(
            id: "bbbbbbbb22222222",
            name: "Skript.pdf",
            description: nil,
            ownerName: nil,
            mimeType: nil,
            downloads: nil,
            fileSize: nil,
            createdAt: nil,
            changedAt: nil,
            isReadable: true,
            isDownloadable: true,
            downloadURL: nil
        )

        let names = SyncPathPlanner.fileNameMap(for: [first, second])
        #expect(names[first.id] == "Skript-aaaaaaaa.pdf")
        #expect(names[second.id] == "Skript-bbbbbbbb.pdf")
    }

    @Test
    func syncPathPlannerFingerprintUsesChangedDateAndFileSize() {
        let changedAt = Date(timeIntervalSince1970: 1_712_275_200) // 2024-04-06T00:00:00Z
        let file = StudIPCourseFileRef(
            id: "abc",
            name: "Datei.txt",
            description: nil,
            ownerName: nil,
            mimeType: nil,
            downloads: nil,
            fileSize: 2048,
            createdAt: nil,
            changedAt: changedAt,
            isReadable: true,
            isDownloadable: true,
            downloadURL: nil
        )

        #expect(SyncPathPlanner.fileFingerprint(for: file) == "1712275200|2048")
    }

    @Test
    func syncManifestCleanupPlannerMarksOnlyStaleFilesInActiveSemesters() {
        let entries = [
            SyncManifestEntryRecord(fileID: "seen-active", relativePath: "a.txt", semesterID: "sem-a"),
            SyncManifestEntryRecord(fileID: "stale-active", relativePath: "b.txt", semesterID: "sem-a"),
            SyncManifestEntryRecord(fileID: "stale-inactive", relativePath: "c.txt", semesterID: "sem-b")
        ]

        let stale = SyncManifestCleanupPlanner.staleFileIDs(
            entries: entries,
            seenFileIDs: ["seen-active"],
            activeSemesterIDs: ["sem-a"]
        )

        #expect(stale == ["stale-active"])
    }

    @Test
    func syncSecurityScopePolicyDeniesAccessOnlyForSandboxWithoutGrantedScope() {
        #expect(SyncSecurityScopePolicy.isRootFolderAccessDenied(isAppSandboxed: true, didAccessScope: false))
        #expect(!SyncSecurityScopePolicy.isRootFolderAccessDenied(isAppSandboxed: true, didAccessScope: true))
        #expect(!SyncSecurityScopePolicy.isRootFolderAccessDenied(isAppSandboxed: false, didAccessScope: false))
    }

    @Test
    func syncSchedulePlannerUsesSymmetricToleranceWithoutPositiveBias() {
        let lower = SyncSchedulePlanner.nextDelaySeconds(
            intervalMinutes: 10,
            toleranceSeconds: 30,
            minimumDelaySeconds: 5,
            backoffMultiplier: 1,
            randomUnit: { 0 }
        )
        let center = SyncSchedulePlanner.nextDelaySeconds(
            intervalMinutes: 10,
            toleranceSeconds: 30,
            minimumDelaySeconds: 5,
            backoffMultiplier: 1,
            randomUnit: { 0.5 }
        )
        let upper = SyncSchedulePlanner.nextDelaySeconds(
            intervalMinutes: 10,
            toleranceSeconds: 30,
            minimumDelaySeconds: 5,
            backoffMultiplier: 1,
            randomUnit: { 1 }
        )

        #expect(lower == 570)
        #expect(center == 600)
        #expect(upper == 630)
    }

    @Test
    func syncSchedulePlannerHonorsMinimumDelay() {
        let delay = SyncSchedulePlanner.nextDelaySeconds(
            intervalMinutes: 0,
            toleranceSeconds: 100,
            minimumDelaySeconds: 5,
            backoffMultiplier: 1,
            randomUnit: { 0 }
        )

        #expect(delay == 5)
    }

    @Test
    func syncSchedulePlannerScalesDelayWithBackoffMultiplier() {
        let delay = SyncSchedulePlanner.nextDelaySeconds(
            intervalMinutes: 10,
            toleranceSeconds: 30,
            minimumDelaySeconds: 5,
            backoffMultiplier: 2,
            randomUnit: { 0.5 }
        )

        #expect(delay == 1200)
    }

    @Test
    func syncAdaptiveBackoffPlannerUsesFailureBackoffAndIdleBackoff() {
        let idleMultiplier = SyncAdaptiveBackoffPlanner.multiplier(
            consecutiveIdleRuns: 3,
            consecutiveFailures: 0
        )
        let failureMultiplier = SyncAdaptiveBackoffPlanner.multiplier(
            consecutiveIdleRuns: 0,
            consecutiveFailures: 3
        )

        #expect(idleMultiplier == 2.5)
        #expect(failureMultiplier == 8)
    }

    @Test
    @MainActor
    func syncEngineIntegrationCoversDownloadDeltaAndCleanup() async throws {
        let suiteName = "StudipSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudipSyncSyncRoot-\(UUID().uuidString)", isDirectory: true)
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudipSyncSyncState-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let bookmark = try rootDirectory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.updateBaseURL(URL(string: "https://studip.example.edu")!)
        settingsStore.updateRootFolderBookmark(bookmark)
        settingsStore.updateActiveSemesterIDs(["semester-1"])
        settingsStore.updateMaxConcurrentFileDownloads(2)

        let repository = SyncEngineRepositoryStub()
        await repository.configure(
            semesters: [SemesterDTO(id: "semester-1", title: "SoSe 2026")],
            coursesBySemesterID: ["semester-1": [makeCourseDTO(id: "course-1", title: "Integration Test Kurs", semesterID: "semester-1")]],
            filesByCourseID: [
                "course-1": [
                    StudIPCourseFileRef(
                        id: "file-1",
                        name: "Skript.txt",
                        description: nil,
                        ownerName: nil,
                        mimeType: "text/plain",
                        downloads: nil,
                        fileSize: 4,
                        createdAt: nil,
                        changedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        isReadable: true,
                        isDownloadable: true,
                        downloadURL: nil
                    )
                ]
            ],
            filePayloadsByID: ["file-1": Data("test".utf8)],
            eTagByFileID: ["file-1": "\"etag-v1\""]
        )

        let engine = SyncEngine(
            repository: repository,
            settingsStore: settingsStore,
            fileManager: .default,
            stateDirectory: stateDirectory
        )

        let firstRun = try await engine.runSync()
        #expect(firstRun.didRun)
        #expect(firstRun.downloadedFiles == 1)
        #expect(firstRun.skippedFiles == 0)

        let downloadedFileCountAfterFirstRun = countFiles(named: "Skript.txt", in: rootDirectory)
        #expect(downloadedFileCountAfterFirstRun == 1)

        let secondRun = try await engine.runSync()
        #expect(secondRun.didRun)
        #expect(secondRun.downloadedFiles == 0)
        #expect(secondRun.skippedFiles >= 1)

        await repository.updateFilesByCourseID(["course-1": []])
        let thirdRun = try await engine.runSync()
        #expect(thirdRun.didRun)
        #expect(thirdRun.removedFiles == 1)

        let downloadedFileCountAfterCleanup = countFiles(named: "Skript.txt", in: rootDirectory)
        #expect(downloadedFileCountAfterCleanup == 0)
    }

    @Test
    @MainActor
    func menuBarStatusControllerKeepsLastSuccessfulSyncDateAcrossStateChanges() {
        let controller = MenuBarStatusController()
        #expect(controller.lastSuccessfulSyncAt == nil)

        controller.setSuccess()
        let firstSuccessDate = controller.lastSuccessfulSyncAt
        #expect(firstSuccessDate != nil)

        controller.setRunning()
        #expect(controller.lastSuccessfulSyncAt == firstSuccessDate)

        controller.setOffline()
        #expect(controller.lastSuccessfulSyncAt == firstSuccessDate)

        controller.setError("failure")
        #expect(controller.lastSuccessfulSyncAt == firstSuccessDate)
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

    @Test
    @MainActor
    func settingsAndMenuBarViewSmoke() {
        let container = AppContainer()
        _ = SettingsView(
            settingsStore: container.settingsStore,
            keychainService: container.keychainService,
            metadataCache: container.metadataCache,
            sharedCourseParticipationCache: container.sharedCourseParticipationCache
        ).body
        _ = MenuBarRootView(
            statusController: container.statusController,
            syncScheduler: container.syncScheduler
        ).body
    }
}

@MainActor
private func makeCourseDTO(id: String, title: String, semesterID: String) -> CourseDTO {
    let json = """
    {
      "id": "\(id)",
      "title": "\(title)",
      "semester_id": "\(semesterID)"
    }
    """
    return try! JSONDecoder().decode(CourseDTO.self, from: Data(json.utf8))
}

private func countFiles(named name: String, in rootDirectory: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(
        at: rootDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return 0
    }

    var count = 0
    for case let url as URL in enumerator where url.lastPathComponent == name {
        count += 1
    }
    return count
}

actor SyncEngineRepositoryStub: SyncEngineRepository {
    private var semesters: [SemesterDTO] = []
    private var coursesBySemesterID: [String: [CourseDTO]] = [:]
    private var filesByCourseID: [String: [StudIPCourseFileRef]] = [:]
    private var filePayloadsByID: [String: Data] = [:]
    private var eTagByFileID: [String: String] = [:]
    private var lastModifiedByFileID: [String: String] = [:]

    func configure(
        semesters: [SemesterDTO],
        coursesBySemesterID: [String: [CourseDTO]],
        filesByCourseID: [String: [StudIPCourseFileRef]],
        filePayloadsByID: [String: Data],
        eTagByFileID: [String: String]
    ) {
        self.semesters = semesters
        self.coursesBySemesterID = coursesBySemesterID
        self.filesByCourseID = filesByCourseID
        self.filePayloadsByID = filePayloadsByID
        self.eTagByFileID = eTagByFileID
        self.lastModifiedByFileID = Dictionary(uniqueKeysWithValues: eTagByFileID.keys.map { ($0, "Mon, 01 Jan 2024 00:00:00 GMT") })
    }

    func updateFilesByCourseID(_ filesByCourseID: [String: [StudIPCourseFileRef]]) {
        self.filesByCourseID = filesByCourseID
    }

    func loadSemestersStaleWhileRevalidate(
        onRefresh: (@MainActor ([SemesterDTO]) -> Void)?
    ) async throws -> StudIPSemesterLoadResult {
        .init(semesters: semesters, source: .remote)
    }

    func fetchCourses(for semesterID: String, offset: Int?, limit: Int?) async throws -> [CourseDTO] {
        coursesBySemesterID[canonicalStudIPID(semesterID)] ?? coursesBySemesterID[semesterID] ?? []
    }

    func fetchCourseFiles(courseID: String, offset: Int, limit: Int) async throws -> [StudIPCourseFileRef] {
        filesByCourseID[canonicalStudIPID(courseID)] ?? filesByCourseID[courseID] ?? []
    }

    func downloadFileContent(
        fileRefID: String,
        fallbackDownloadPath: String?,
        ifNoneMatch: String?,
        ifModifiedSince: String?
    ) async throws -> StudIPFileRepository.FileContentDownloadResult {
        let normalizedID = canonicalStudIPID(fileRefID)
        let payload = filePayloadsByID[normalizedID] ?? filePayloadsByID[fileRefID] ?? Data()
        let eTag = eTagByFileID[normalizedID] ?? eTagByFileID[fileRefID]
        let lastModified = lastModifiedByFileID[normalizedID] ?? lastModifiedByFileID[fileRefID]

        if let ifNoneMatch, let eTag, ifNoneMatch == eTag {
            return .init(temporaryFileURL: nil, statusCode: 304, headers: ["ETag": eTag, "Last-Modified": lastModified ?? ""])
        }
        if let ifModifiedSince, let lastModified, ifModifiedSince == lastModified {
            return .init(temporaryFileURL: nil, statusCode: 304, headers: ["ETag": eTag ?? "", "Last-Modified": lastModified])
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudipSyncTests-\(UUID().uuidString).bin")
        try payload.write(to: tempURL, options: .atomic)
        return .init(
            temporaryFileURL: tempURL,
            statusCode: 200,
            headers: [
                "ETag": eTag ?? "\"stub-etag\"",
                "Last-Modified": lastModified ?? "Mon, 01 Jan 2024 00:00:00 GMT"
            ]
        )
    }
}
