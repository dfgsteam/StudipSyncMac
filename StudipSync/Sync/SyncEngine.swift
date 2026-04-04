import Foundation
import CryptoKit
import Security

struct SyncManifestEntryRecord: Equatable {
    let fileID: String
    let relativePath: String
    let semesterID: String
}

enum SyncManifestCleanupPlanner {
    static func staleFileIDs(
        entries: [SyncManifestEntryRecord],
        seenFileIDs: Set<String>,
        activeSemesterIDs: Set<String>
    ) -> Set<String> {
        Set(
            entries.compactMap { entry in
                guard activeSemesterIDs.contains(canonicalStudIPID(entry.semesterID)) else { return nil }
                return seenFileIDs.contains(entry.fileID) ? nil : entry.fileID
            }
        )
    }
}

enum SyncSecurityScopePolicy {
    static func isRootFolderAccessDenied(isAppSandboxed: Bool, didAccessScope: Bool) -> Bool {
        isAppSandboxed && !didAccessScope
    }
}

enum SyncPathPlanner {
    static func sanitizedPathComponent(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = raw.components(separatedBy: invalid)
        let joined = parts.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "unbenannt" : joined
    }

    static func semesterDirectoryName(for semester: SemesterDTO) -> String {
        let title = sanitizedPathComponent(semester.title)
        return "\(title) [\(shortID(semester.id))]"
    }

    static func courseDirectoryName(for course: CourseDTO) -> String {
        let title = sanitizedPathComponent(course.title)
        return "\(title) [\(shortID(course.id))]"
    }

    static func fileNameMap(for files: [StudIPCourseFileRef]) -> [String: String] {
        var baseNamesByID: [String: String] = [:]
        baseNamesByID.reserveCapacity(files.count)

        for file in files {
            let fallbackName = "datei-\(shortID(file.id))"
            let candidate = sanitizedPathComponent(file.name.trimmingCharacters(in: .whitespacesAndNewlines))
            let base = candidate.isEmpty ? fallbackName : candidate
            baseNamesByID[file.id] = base
        }

        var groupedIDsByLowercasedName: [String: [String]] = [:]
        for (fileID, baseName) in baseNamesByID {
            groupedIDsByLowercasedName[baseName.lowercased(), default: []].append(fileID)
        }

        var namesByID: [String: String] = [:]
        namesByID.reserveCapacity(files.count)

        for file in files {
            let baseName = baseNamesByID[file.id] ?? "datei-\(shortID(file.id))"
            let collidingIDs = groupedIDsByLowercasedName[baseName.lowercased()] ?? []

            if collidingIDs.count <= 1 {
                namesByID[file.id] = baseName
                continue
            }

            namesByID[file.id] = appendingSuffix(shortID(file.id), toFileName: baseName)
        }

        return namesByID
    }

    static func fileFingerprint(for file: StudIPCourseFileRef) -> String {
        let changedAt = Int64((file.changedAt ?? file.createdAt ?? .distantPast).timeIntervalSince1970)
        let size = Int64(file.fileSize ?? -1)
        return "\(changedAt)|\(size)"
    }

    static func shortID(_ rawID: String) -> String {
        String(canonicalStudIPID(rawID).prefix(8))
    }

    private static func appendingSuffix(_ suffix: String, toFileName fileName: String) -> String {
        let nameURL = URL(fileURLWithPath: fileName)
        let stem = nameURL.deletingPathExtension().lastPathComponent
        let ext = nameURL.pathExtension
        if ext.isEmpty {
            return "\(stem)-\(suffix)"
        }
        return "\(stem)-\(suffix).\(ext)"
    }
}

struct SyncRunReport: Sendable {
    let didRun: Bool
    let downloadedFiles: Int
    let skippedFiles: Int
    let removedFiles: Int

    var hasChanges: Bool {
        downloadedFiles > 0 || removedFiles > 0
    }
}

protocol SyncEngineRepository: Sendable {
    func loadSemestersStaleWhileRevalidate(
        onRefresh: (@MainActor ([SemesterDTO]) -> Void)?
    ) async throws -> StudIPSemesterLoadResult
    func fetchCourses(for semesterID: String, offset: Int?, limit: Int?) async throws -> [CourseDTO]
    func fetchCourseFiles(courseID: String, offset: Int, limit: Int) async throws -> [StudIPCourseFileRef]
    func downloadFileContent(
        fileRefID: String,
        fallbackDownloadPath: String?,
        ifNoneMatch: String?,
        ifModifiedSince: String?
    ) async throws -> StudIPFileRepository.FileContentDownloadResult
    func ensureRootFolderAccessByPromptingUserIfNeeded() async -> Bool
}

extension SyncEngineRepository {
    func ensureRootFolderAccessByPromptingUserIfNeeded() async -> Bool { true }
}

actor SyncEngine {
    struct ActiveSemesterFailure: Sendable, Equatable {
        enum Category: String, Sendable {
            case offline
            case unauthorized
            case configuration
            case localAccess
            case serverTemporary
            case unknown
        }

        let semesterID: String
        let category: Category
        let message: String
    }

    enum SyncEngineError: LocalizedError {
        case rootFolderNotConfigured
        case couldNotResolveRootFolder
        case rootFolderNotAccessible
        case activeSemesterSyncFailed([ActiveSemesterFailure])
        case missingDownloadedFilePayload(fileID: String)

        var errorDescription: String? {
            switch self {
            case .rootFolderNotConfigured:
                return "Kein Sync-Ordner konfiguriert."
            case .couldNotResolveRootFolder:
                return "Sync-Ordner konnte nicht aus dem Bookmark gelesen werden. Bitte in den Einstellungen neu auswaehlen."
            case .rootFolderNotAccessible:
                return "Sync-Ordner ist aktuell nicht zugreifbar. Bitte in den Einstellungen erneut autorisieren."
            case .activeSemesterSyncFailed(let failures):
                let message = failures
                    .prefix(3)
                    .map { "\($0.semesterID) [\($0.category.rawValue)]: \($0.message)" }
                    .joined(separator: " | ")
                return "Sync teilweise fehlgeschlagen: \(message)"
            case .missingDownloadedFilePayload(let fileID):
                return "Download lieferte keinen Dateistrom fuer Datei \(fileID)."
            }
        }
    }

    private struct SyncManifest: Codable {
        struct Entry: Codable, Sendable {
            let fingerprint: String
            let relativePath: String
            let semesterID: String
            let updatedAt: Date
            let eTag: String?
            let lastModified: String?
        }

        var version: Int
        var entries: [String: Entry]
    }

    private struct SyncSummary {
        var semestersSynced: Int = 0
        var coursesSynced: Int = 0
        var downloadedFiles: Int = 0
        var skippedFiles: Int = 0
        var removedFiles: Int = 0

        var runReport: SyncRunReport {
            SyncRunReport(
                didRun: true,
                downloadedFiles: downloadedFiles,
                skippedFiles: skippedFiles,
                removedFiles: removedFiles
            )
        }
    }

    private struct FileSyncPlan: Sendable {
        let fileID: String
        let fingerprint: String
        let canonicalSemesterID: String
        let targetURL: URL
        let relativePath: String
        let fallbackDownloadPath: String?
        let existingEntry: SyncManifest.Entry?
    }

    private struct FileSyncResult: Sendable {
        let fileID: String
        let didSkip: Bool
        let entry: SyncManifest.Entry
    }

    private let currentManifestVersion = 2

    private let repository: any SyncEngineRepository
    private let settingsStore: SettingsStore
    private let fileManager: FileManager
    private let stateDirectory: URL

    private var isRunning = false

    init(
        repository: any SyncEngineRepository,
        settingsStore: SettingsStore,
        fileManager: FileManager = .default,
        stateDirectory: URL? = nil
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.fileManager = fileManager

        if let stateDirectory {
            self.stateDirectory = stateDirectory
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.stateDirectory = support
                .appendingPathComponent("StudipSync", isDirectory: true)
                .appendingPathComponent("SyncState", isDirectory: true)
        }
    }

    @discardableResult
    func runSync() async throws -> SyncRunReport {
        guard !isRunning else {
            AppLogger.info("Sync skipped because another run is in progress")
            return SyncRunReport(didRun: false, downloadedFiles: 0, skippedFiles: 0, removedFiles: 0)
        }

        isRunning = true
        defer { isRunning = false }

        AppLogger.info("Sync run started")
        let summary = try await performSync()
        let report = summary.runReport
        AppLogger.info(
            "Sync run completed | semesters=\(summary.semestersSynced) courses=\(summary.coursesSynced) downloaded=\(summary.downloadedFiles) skipped=\(summary.skippedFiles) removed=\(summary.removedFiles)"
        )
        return report
    }

    private func performSync() async throws -> SyncSummary {
        var configuration = await MainActor.run { settingsStore.configuration }
        guard let bookmark = configuration.rootFolderBookmark else {
            throw SyncEngineError.rootFolderNotConfigured
        }

        var rootURL = try await resolveRootFolderURL(from: bookmark)
        var didAccessScope = rootURL.startAccessingSecurityScopedResource()

        if SyncSecurityScopePolicy.isRootFolderAccessDenied(
            isAppSandboxed: isAppSandboxed(),
            didAccessScope: didAccessScope
        ) {
            if didAccessScope {
                rootURL.stopAccessingSecurityScopedResource()
            }

            let reauthorized = await repository.ensureRootFolderAccessByPromptingUserIfNeeded()
            guard reauthorized else {
                throw SyncEngineError.rootFolderNotAccessible
            }

            configuration = await MainActor.run { settingsStore.configuration }
            guard let refreshedBookmark = configuration.rootFolderBookmark else {
                throw SyncEngineError.rootFolderNotConfigured
            }

            rootURL = try await resolveRootFolderURL(from: refreshedBookmark)
            didAccessScope = rootURL.startAccessingSecurityScopedResource()

            if SyncSecurityScopePolicy.isRootFolderAccessDenied(
                isAppSandboxed: isAppSandboxed(),
                didAccessScope: didAccessScope
            ) {
                throw SyncEngineError.rootFolderNotAccessible
            }
        }

        defer {
            if didAccessScope {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        guard verifyRootFolderReadWriteAccess(rootURL) else {
            throw SyncEngineError.rootFolderNotAccessible
        }

        try ensureStateDirectoryExists()

        let activeSemesterIDs = configuration.activeSemesterIDs.sorted()
        guard !activeSemesterIDs.isEmpty else {
            AppLogger.info("Sync skipped because no semesters are active")
            return SyncSummary()
        }

        let maxConcurrentDownloads = min(4, max(2, configuration.maxConcurrentFileDownloads))

        var manifest = try loadManifest(baseURL: configuration.baseURL, rootURL: rootURL)
        var seenFileIDs: Set<String> = []
        var summary = SyncSummary()
        var syncErrors: [ActiveSemesterFailure] = []
        let activeSemesterIDsCanonical = Set(configuration.activeSemesterIDs.map(canonicalStudIPID))

        let semesterResult = try await repository.loadSemestersStaleWhileRevalidate(onRefresh: nil)
        let semestersByID = Dictionary(uniqueKeysWithValues: semesterResult.semesters.map { (canonicalStudIPID($0.id), $0) })

        for semesterID in activeSemesterIDs {
            if Task.isCancelled {
                break
            }

            do {
                let canonicalSemesterID = canonicalStudIPID(semesterID)
                let semester = semestersByID[canonicalSemesterID] ?? SemesterDTO(
                    id: canonicalSemesterID,
                    title: "Semester \(SyncPathPlanner.shortID(canonicalSemesterID))"
                )

                let semesterSummary = try await syncSemester(
                    semester,
                    rootURL: rootURL,
                    manifest: &manifest,
                    seenFileIDs: &seenFileIDs,
                    maxConcurrentDownloads: maxConcurrentDownloads
                )

                summary.semestersSynced += 1
                summary.coursesSynced += semesterSummary.coursesSynced
                summary.downloadedFiles += semesterSummary.downloadedFiles
                summary.skippedFiles += semesterSummary.skippedFiles
            } catch {
                syncErrors.append(
                    ActiveSemesterFailure(
                        semesterID: canonicalStudIPID(semesterID),
                        category: classifyFailureCategory(for: error),
                        message: error.localizedDescription
                    )
                )
            }
        }

        let removedFileCount = try cleanupRemovedLocalFiles(
            manifest: &manifest,
            seenFileIDs: seenFileIDs,
            activeSemesterIDs: activeSemesterIDsCanonical,
            rootURL: rootURL
        )
        summary.removedFiles = removedFileCount

        if removedFileCount > 0 {
            AppLogger.info("Sync cleanup removed \(removedFileCount) local files that no longer exist remotely")
        }

        try saveManifest(manifest, baseURL: configuration.baseURL, rootURL: rootURL)

        if !syncErrors.isEmpty {
            throw SyncEngineError.activeSemesterSyncFailed(syncErrors)
        }

        return summary
    }

    private func syncSemester(
        _ semester: SemesterDTO,
        rootURL: URL,
        manifest: inout SyncManifest,
        seenFileIDs: inout Set<String>,
        maxConcurrentDownloads: Int
    ) async throws -> SyncSummary {
        let semesterFolder = SyncPathPlanner.semesterDirectoryName(for: semester)
        let semesterURL = rootURL.appendingPathComponent(semesterFolder, isDirectory: true)
        try fileManager.createDirectory(at: semesterURL, withIntermediateDirectories: true)

        let courses = try await repository.fetchCourses(for: semester.id, offset: 0, limit: 1000)
        var summary = SyncSummary()
        summary.coursesSynced = courses.count

        for course in courses {
            if Task.isCancelled {
                break
            }

            let courseFolder = SyncPathPlanner.courseDirectoryName(for: course)
            let courseURL = semesterURL.appendingPathComponent(courseFolder, isDirectory: true)
            try fileManager.createDirectory(at: courseURL, withIntermediateDirectories: true)

            let files = try await repository.fetchCourseFiles(courseID: course.id, offset: 0, limit: 1000)
            let fileNamesByID = SyncPathPlanner.fileNameMap(for: files)

            var plans: [FileSyncPlan] = []
            plans.reserveCapacity(files.count)

            for file in files {
                if Task.isCancelled {
                    break
                }

                guard file.isReadable != false, file.isDownloadable != false else {
                    continue
                }

                let targetFileName = fileNamesByID[file.id] ?? "datei-\(SyncPathPlanner.shortID(file.id))"
                let targetURL = courseURL.appendingPathComponent(targetFileName, isDirectory: false)
                let plan = FileSyncPlan(
                    fileID: file.id,
                    fingerprint: SyncPathPlanner.fileFingerprint(for: file),
                    canonicalSemesterID: canonicalStudIPID(semester.id),
                    targetURL: targetURL,
                    relativePath: relativePath(from: rootURL, to: targetURL),
                    fallbackDownloadPath: fallbackDownloadPath(from: file.downloadURL),
                    existingEntry: manifest.entries[file.id]
                )
                plans.append(plan)
            }

            if plans.isEmpty {
                continue
            }

            var iterator = plans.makeIterator()
            try await withThrowingTaskGroup(of: FileSyncResult.self) { group in
                var inFlight = 0

                func scheduleNext(_ group: inout ThrowingTaskGroup<FileSyncResult, Error>) {
                    guard let nextPlan = iterator.next() else {
                        return
                    }

                    inFlight += 1
                    group.addTask {
                        try await self.syncFile(nextPlan, rootURL: rootURL)
                    }
                }

                let initialTasks = min(maxConcurrentDownloads, plans.count)
                for _ in 0..<initialTasks {
                    scheduleNext(&group)
                }

                while inFlight > 0 {
                    guard let result = try await group.next() else {
                        break
                    }
                    inFlight -= 1

                    seenFileIDs.insert(result.fileID)
                    manifest.entries[result.fileID] = result.entry
                    if result.didSkip {
                        summary.skippedFiles += 1
                    } else {
                        summary.downloadedFiles += 1
                    }

                    scheduleNext(&group)
                }
            }
        }

        return summary
    }

    private func syncFile(_ plan: FileSyncPlan, rootURL: URL) async throws -> FileSyncResult {
        if let entry = plan.existingEntry,
           entry.fingerprint == plan.fingerprint,
           fileManager.fileExists(atPath: plan.targetURL.path) {
            return FileSyncResult(
                fileID: plan.fileID,
                didSkip: true,
                entry: SyncManifest.Entry(
                    fingerprint: plan.fingerprint,
                    relativePath: plan.relativePath,
                    semesterID: plan.canonicalSemesterID,
                    updatedAt: Date(),
                    eTag: entry.eTag,
                    lastModified: entry.lastModified
                )
            )
        }

        if let entry = plan.existingEntry,
           entry.fingerprint == plan.fingerprint {
            let previousURL = rootURL.appendingPathComponent(entry.relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: previousURL.path) {
                try moveKnownLocalFile(from: previousURL, to: plan.targetURL)
                return FileSyncResult(
                    fileID: plan.fileID,
                    didSkip: true,
                    entry: SyncManifest.Entry(
                        fingerprint: plan.fingerprint,
                        relativePath: plan.relativePath,
                        semesterID: plan.canonicalSemesterID,
                        updatedAt: Date(),
                        eTag: entry.eTag,
                        lastModified: entry.lastModified
                    )
                )
            }
        }

        var deltaResult = try await repository.downloadFileContent(
            fileRefID: plan.fileID,
            fallbackDownloadPath: plan.fallbackDownloadPath,
            ifNoneMatch: plan.existingEntry?.eTag,
            ifModifiedSince: plan.existingEntry?.lastModified
        )

        if deltaResult.wasNotModified {
            let recoveredLocalFile = try recoverLocalFileIfNeeded(rootURL: rootURL, plan: plan)
            if recoveredLocalFile {
                return FileSyncResult(
                    fileID: plan.fileID,
                    didSkip: true,
                    entry: SyncManifest.Entry(
                        fingerprint: plan.fingerprint,
                        relativePath: plan.relativePath,
                        semesterID: plan.canonicalSemesterID,
                        updatedAt: Date(),
                        eTag: normalizedHeaderValue(deltaResult.headers, key: "etag") ?? plan.existingEntry?.eTag,
                        lastModified: normalizedHeaderValue(deltaResult.headers, key: "last-modified") ?? plan.existingEntry?.lastModified
                    )
                )
            }

            // Lokale Datei fehlt trotz 304 -> einmal ohne Bedingungen nachladen.
            deltaResult = try await repository.downloadFileContent(
                fileRefID: plan.fileID,
                fallbackDownloadPath: plan.fallbackDownloadPath,
                ifNoneMatch: nil,
                ifModifiedSince: nil
            )
        }

        guard deltaResult.statusCode == 200,
              let downloadedURL = deltaResult.temporaryFileURL else {
            throw SyncEngineError.missingDownloadedFilePayload(fileID: plan.fileID)
        }

        let didSkip = try applyDownloadedFileAtomically(downloadedFileURL: downloadedURL, targetURL: plan.targetURL)

        let entry = SyncManifest.Entry(
            fingerprint: plan.fingerprint,
            relativePath: plan.relativePath,
            semesterID: plan.canonicalSemesterID,
            updatedAt: Date(),
            eTag: normalizedHeaderValue(deltaResult.headers, key: "etag") ?? plan.existingEntry?.eTag,
            lastModified: normalizedHeaderValue(deltaResult.headers, key: "last-modified") ?? plan.existingEntry?.lastModified
        )

        return FileSyncResult(fileID: plan.fileID, didSkip: didSkip, entry: entry)
    }

    private func recoverLocalFileIfNeeded(rootURL: URL, plan: FileSyncPlan) throws -> Bool {
        if fileManager.fileExists(atPath: plan.targetURL.path) {
            return true
        }

        guard let existingEntry = plan.existingEntry else {
            return false
        }

        let previousURL = rootURL
            .appendingPathComponent(existingEntry.relativePath, isDirectory: false)
            .standardizedFileURL

        guard fileManager.fileExists(atPath: previousURL.path) else {
            return false
        }

        try moveKnownLocalFile(from: previousURL, to: plan.targetURL)
        return true
    }

    private func moveKnownLocalFile(from sourceURL: URL, to targetURL: URL) throws {
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sourceURL.standardizedFileURL == targetURL.standardizedFileURL {
            return
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: targetURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            try? fileManager.removeItem(at: sourceURL)
        }
    }

    private func applyDownloadedFileAtomically(downloadedFileURL: URL, targetURL: URL) throws -> Bool {
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let stagingURL = targetURL
            .deletingLastPathComponent()
            .appendingPathComponent(".studipsync-\(UUID().uuidString).part", isDirectory: false)

        if fileManager.fileExists(atPath: stagingURL.path) {
            try? fileManager.removeItem(at: stagingURL)
        }

        do {
            try fileManager.moveItem(at: downloadedFileURL, to: stagingURL)
        } catch {
            try fileManager.copyItem(at: downloadedFileURL, to: stagingURL)
            try? fileManager.removeItem(at: downloadedFileURL)
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            let isUnchanged = try filesHaveSameContent(lhs: stagingURL, rhs: targetURL)
            if isUnchanged {
                try? fileManager.removeItem(at: stagingURL)
                return true
            }

            do {
                _ = try fileManager.replaceItemAt(targetURL, withItemAt: stagingURL)
            } catch {
                try? fileManager.removeItem(at: targetURL)
                try fileManager.moveItem(at: stagingURL, to: targetURL)
            }
            return false
        }

        try fileManager.moveItem(at: stagingURL, to: targetURL)
        return false
    }

    private func filesHaveSameContent(lhs: URL, rhs: URL) throws -> Bool {
        let lhsAttributes = try fileManager.attributesOfItem(atPath: lhs.path)
        let rhsAttributes = try fileManager.attributesOfItem(atPath: rhs.path)

        let lhsSize = (lhsAttributes[.size] as? NSNumber)?.int64Value ?? -1
        let rhsSize = (rhsAttributes[.size] as? NSNumber)?.int64Value ?? -1
        if lhsSize != rhsSize {
            return false
        }

        let lhsDigest = try sha256Hex(of: lhs)
        let rhsDigest = try sha256Hex(of: rhs)
        return lhsDigest == rhsDigest
    }

    private func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func resolveRootFolderURL(from bookmarkData: Data) async throws -> URL {
        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                let refreshedBookmark = try resolvedURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                await MainActor.run {
                    settingsStore.updateRootFolderBookmark(refreshedBookmark)
                }
            }

            return resolvedURL
        } catch {
            AppLogger.error("Resolving sync root bookmark failed: \(error.localizedDescription)")
            throw SyncEngineError.couldNotResolveRootFolder
        }
    }

    private func fallbackDownloadPath(from downloadURL: URL?) -> String? {
        guard let downloadURL else { return nil }
        var components = URLComponents(url: downloadURL, resolvingAgainstBaseURL: false)
        var path = components?.percentEncodedPath ?? downloadURL.path
        if let query = components?.percentEncodedQuery, !query.isEmpty {
            path.append("?\(query)")
        }
        return path.isEmpty ? nil : path
    }

    private func normalizedHeaderValue(_ headers: [AnyHashable: Any], key: String) -> String? {
        for (headerKey, value) in headers {
            let normalizedKey = String(describing: headerKey).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalizedKey == key.lowercased() else {
                continue
            }

            let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func classifyFailureCategory(for error: Error) -> ActiveSemesterFailure.Category {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .offline
            case .timedOut, .resourceUnavailable, .internationalRoamingOff:
                return .serverTemporary
            default:
                return .unknown
            }
        }

        if let apiError = error as? StudIPAPIClient.APIClientError {
            switch apiError {
            case .missingCredentials, .sandboxNetworkPermissionMissing, .invalidPath, .invalidResponse:
                return .configuration
            case .unauthorized:
                return .unauthorized
            case .httpStatus(let code, _, _):
                if code == 401 || code == 403 {
                    return .unauthorized
                }
                if code == 408 || code == 425 || code == 429 || (500...599).contains(code) {
                    return .serverTemporary
                }
                return .unknown
            }
        }

        if let syncError = error as? SyncEngineError {
            switch syncError {
            case .rootFolderNotConfigured:
                return .configuration
            case .couldNotResolveRootFolder, .rootFolderNotAccessible:
                return .localAccess
            case .activeSemesterSyncFailed(let failures):
                return failures.first?.category ?? .unknown
            case .missingDownloadedFilePayload:
                return .serverTemporary
            }
        }

        return .unknown
    }

    private func manifestFileURL(baseURL: URL, rootURL: URL) -> URL {
        let baseURLKey = normalizedBaseURLKey(baseURL)
        let rootPath = rootURL.standardizedFileURL.path
        let hashInput = "\(baseURLKey)|\(rootPath)"
        let digest = SHA256.hash(data: Data(hashInput.utf8))
        let hash = digest.compactMap { String(format: "%02x", $0) }.joined()
        return stateDirectory.appendingPathComponent("manifest.\(hash).json")
    }

    private func loadManifest(baseURL: URL, rootURL: URL) throws -> SyncManifest {
        let fileURL = manifestFileURL(baseURL: baseURL, rootURL: rootURL)
        guard let data = try? Data(contentsOf: fileURL) else {
            return SyncManifest(version: currentManifestVersion, entries: [:])
        }

        guard var manifest = try? JSONDecoder().decode(SyncManifest.self, from: data) else {
            return SyncManifest(version: currentManifestVersion, entries: [:])
        }

        guard manifest.version >= 1, manifest.version <= currentManifestVersion else {
            return SyncManifest(version: currentManifestVersion, entries: [:])
        }

        manifest.version = currentManifestVersion
        return manifest
    }

    private func saveManifest(_ manifest: SyncManifest, baseURL: URL, rootURL: URL) throws {
        var persistable = manifest
        persistable.version = currentManifestVersion

        let fileURL = manifestFileURL(baseURL: baseURL, rootURL: rootURL)
        let data = try JSONEncoder().encode(persistable)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureStateDirectoryExists() throws {
        try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    }

    private func normalizedBaseURLKey(_ baseURL: URL) -> String {
        var key = baseURL.absoluteString.lowercased()
        if key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }

    private func relativePath(from rootURL: URL, to fileURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private func isAppSandboxed() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }

        let sandboxEntitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        return (sandboxEntitlement as? Bool) == true
    }

    private func verifyRootFolderReadWriteAccess(_ rootURL: URL) -> Bool {
        do {
            _ = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            AppLogger.error("Sync root listing failed: \(error.localizedDescription)")
            return false
        }

        let probeURL = rootURL.appendingPathComponent("studipsync-access-\(UUID().uuidString).tmp", isDirectory: false)
        let created = fileManager.createFile(atPath: probeURL.path, contents: Data(), attributes: nil)
        guard created else {
            AppLogger.error("Sync root write probe failed: createFile returned false")
            return false
        }

        do {
            let handle = try FileHandle(forWritingTo: probeURL)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data("probe".utf8))
            try fileManager.removeItem(at: probeURL)
            return true
        } catch {
            AppLogger.error("Sync root write probe failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: probeURL)
            return false
        }
    }

    private func cleanupRemovedLocalFiles(
        manifest: inout SyncManifest,
        seenFileIDs: Set<String>,
        activeSemesterIDs: Set<String>,
        rootURL: URL
    ) throws -> Int {
        let records = manifest.entries.map { fileID, entry in
            SyncManifestEntryRecord(
                fileID: fileID,
                relativePath: entry.relativePath,
                semesterID: entry.semesterID
            )
        }
        let staleFileIDs = SyncManifestCleanupPlanner.staleFileIDs(
            entries: records,
            seenFileIDs: seenFileIDs,
            activeSemesterIDs: activeSemesterIDs
        )

        guard !staleFileIDs.isEmpty else {
            return 0
        }

        let normalizedRootPath = rootURL.standardizedFileURL.path
        var removedCount = 0

        for fileID in staleFileIDs {
            guard let entry = manifest.entries[fileID] else {
                continue
            }

            defer {
                manifest.entries.removeValue(forKey: fileID)
            }

            let fileURL = rootURL
                .appendingPathComponent(entry.relativePath, isDirectory: false)
                .standardizedFileURL
            let filePath = fileURL.path

            guard filePath.hasPrefix(normalizedRootPath + "/") else {
                continue
            }

            guard fileManager.fileExists(atPath: filePath) else {
                continue
            }

            do {
                try fileManager.removeItem(at: fileURL)
                removedCount += 1
                try pruneEmptyParentDirectories(startingAt: fileURL.deletingLastPathComponent(), rootURL: rootURL)
            } catch {
                AppLogger.error("Removing stale local file failed (\(fileID)): \(error.localizedDescription)")
            }
        }

        return removedCount
    }

    private func pruneEmptyParentDirectories(startingAt directoryURL: URL, rootURL: URL) throws {
        let normalizedRoot = rootURL.standardizedFileURL
        var currentDirectory = directoryURL.standardizedFileURL

        while currentDirectory.path.hasPrefix(normalizedRoot.path + "/") {
            let children = try fileManager.contentsOfDirectory(
                at: currentDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            if !children.isEmpty {
                break
            }

            try fileManager.removeItem(at: currentDirectory)
            currentDirectory.deleteLastPathComponent()
        }
    }
}

extension StudIPResourceRepository: SyncEngineRepository {}
