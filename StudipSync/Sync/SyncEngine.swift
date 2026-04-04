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

actor SyncEngine {
    enum SyncEngineError: LocalizedError {
        case rootFolderNotConfigured
        case couldNotResolveRootFolder
        case rootFolderNotAccessible
        case activeSemesterSyncFailed([String])

        var errorDescription: String? {
            switch self {
            case .rootFolderNotConfigured:
                return "Kein Sync-Ordner konfiguriert."
            case .couldNotResolveRootFolder:
                return "Sync-Ordner konnte nicht aus dem Bookmark gelesen werden. Bitte in den Einstellungen neu auswaehlen."
            case .rootFolderNotAccessible:
                return "Sync-Ordner ist aktuell nicht zugreifbar. Bitte in den Einstellungen erneut autorisieren."
            case .activeSemesterSyncFailed(let errors):
                let message = errors.prefix(3).joined(separator: " | ")
                return "Sync teilweise fehlgeschlagen: \(message)"
            }
        }
    }

    private struct SyncManifest: Codable {
        struct Entry: Codable {
            let fingerprint: String
            let relativePath: String
            let semesterID: String
            let updatedAt: Date
        }

        let version: Int
        var entries: [String: Entry]
    }

    private struct SyncSummary {
        var semestersSynced: Int = 0
        var coursesSynced: Int = 0
        var downloadedFiles: Int = 0
        var skippedFiles: Int = 0
    }

    private let repository: StudIPResourceRepository
    private let settingsStore: SettingsStore
    private let fileManager: FileManager
    private let stateDirectory: URL

    private var isRunning = false

    init(
        repository: StudIPResourceRepository,
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
    func runSync() async throws -> Bool {
        guard !isRunning else {
            AppLogger.info("Sync skipped because another run is in progress")
            return false
        }

        isRunning = true
        defer { isRunning = false }

        AppLogger.info("Sync run started")
        let summary = try await performSync()
        AppLogger.info(
            "Sync run completed | semesters=\(summary.semestersSynced) courses=\(summary.coursesSynced) downloaded=\(summary.downloadedFiles) skipped=\(summary.skippedFiles)"
        )
        return true
    }

    private func performSync() async throws -> SyncSummary {
        let configuration = await MainActor.run { settingsStore.configuration }
        guard let bookmark = configuration.rootFolderBookmark else {
            throw SyncEngineError.rootFolderNotConfigured
        }

        let rootURL = try await resolveRootFolderURL(from: bookmark)
        let didAccessScope = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessScope {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }
        if SyncSecurityScopePolicy.isRootFolderAccessDenied(
            isAppSandboxed: isAppSandboxed(),
            didAccessScope: didAccessScope
        ) {
            throw SyncEngineError.rootFolderNotAccessible
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ensureStateDirectoryExists()

        let activeSemesterIDs = configuration.activeSemesterIDs.sorted()
        guard !activeSemesterIDs.isEmpty else {
            AppLogger.info("Sync skipped because no semesters are active")
            return SyncSummary()
        }

        var manifest = try loadManifest(baseURL: configuration.baseURL, rootURL: rootURL)
        var seenFileIDs: Set<String> = []
        var summary = SyncSummary()
        var syncErrors: [String] = []
        let activeSemesterIDsCanonical = Set(configuration.activeSemesterIDs.map(canonicalStudIPID))

        let semesterResult = try await repository.loadSemestersStaleWhileRevalidate()
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
                    seenFileIDs: &seenFileIDs
                )

                summary.semestersSynced += 1
                summary.coursesSynced += semesterSummary.coursesSynced
                summary.downloadedFiles += semesterSummary.downloadedFiles
                summary.skippedFiles += semesterSummary.skippedFiles
            } catch {
                syncErrors.append("Semester \(semesterID): \(error.localizedDescription)")
            }
        }

        let removedFileCount = try cleanupRemovedLocalFiles(
            manifest: &manifest,
            seenFileIDs: seenFileIDs,
            activeSemesterIDs: activeSemesterIDsCanonical,
            rootURL: rootURL
        )
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
        seenFileIDs: inout Set<String>
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

            for file in files {
                if Task.isCancelled {
                    break
                }

                guard file.isReadable != false, file.isDownloadable != false else {
                    continue
                }

                let targetFileName = fileNamesByID[file.id] ?? "datei-\(SyncPathPlanner.shortID(file.id))"
                let targetURL = courseURL.appendingPathComponent(targetFileName, isDirectory: false)

                let didSkip = try await syncFile(
                    file,
                    targetURL: targetURL,
                    semesterID: semester.id,
                    rootURL: rootURL,
                    manifest: &manifest
                )

                seenFileIDs.insert(file.id)
                if didSkip {
                    summary.skippedFiles += 1
                } else {
                    summary.downloadedFiles += 1
                }
            }
        }

        return summary
    }

    private func syncFile(
        _ file: StudIPCourseFileRef,
        targetURL: URL,
        semesterID: String,
        rootURL: URL,
        manifest: inout SyncManifest
    ) async throws -> Bool {
        let fingerprint = SyncPathPlanner.fileFingerprint(for: file)
        let relativePath = relativePath(from: rootURL, to: targetURL)
        let canonicalSemesterID = canonicalStudIPID(semesterID)

        if let entry = manifest.entries[file.id],
           entry.fingerprint == fingerprint,
           fileManager.fileExists(atPath: targetURL.path) {
            manifest.entries[file.id] = .init(
                fingerprint: fingerprint,
                relativePath: relativePath,
                semesterID: canonicalSemesterID,
                updatedAt: Date()
            )
            return true
        }

        if let entry = manifest.entries[file.id],
           entry.fingerprint == fingerprint {
            let previousURL = rootURL.appendingPathComponent(entry.relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: previousURL.path) {
                try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.moveItem(at: previousURL, to: targetURL)
                manifest.entries[file.id] = .init(
                    fingerprint: fingerprint,
                    relativePath: relativePath,
                    semesterID: canonicalSemesterID,
                    updatedAt: Date()
                )
                return true
            }
        }

        let fallbackDownloadPath = fallbackDownloadPath(from: file.downloadURL)
        let data = try await repository.fetchFileContent(fileRefID: file.id, fallbackDownloadPath: fallbackDownloadPath)
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: targetURL, options: .atomic)

        manifest.entries[file.id] = .init(
            fingerprint: fingerprint,
            relativePath: relativePath,
            semesterID: canonicalSemesterID,
            updatedAt: Date()
        )

        return false
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
            return SyncManifest(version: 1, entries: [:])
        }

        guard let manifest = try? JSONDecoder().decode(SyncManifest.self, from: data),
              manifest.version == 1 else {
            return SyncManifest(version: 1, entries: [:])
        }

        return manifest
    }

    private func saveManifest(_ manifest: SyncManifest, baseURL: URL, rootURL: URL) throws {
        let fileURL = manifestFileURL(baseURL: baseURL, rootURL: rootURL)
        let data = try JSONEncoder().encode(manifest)
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
