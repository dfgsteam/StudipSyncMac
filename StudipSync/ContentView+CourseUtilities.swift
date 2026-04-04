import AppKit
import Security
import SwiftUI

extension ContentView {
    func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedSearchQuery(_ rawQuery: String?) -> String? {
        nonEmpty(rawQuery)
    }

    func hasSearchQuery(_ rawQuery: String?) -> Bool {
        normalizedSearchQuery(rawQuery) != nil
    }

    func fieldMatchesSearchQuery(_ rawQuery: String?, fields: [String?]) -> Bool {
        guard let query = normalizedSearchQuery(rawQuery)?.localizedLowercase else {
            return true
        }
        let haystack = fields
            .compactMap { nonEmpty($0)?.localizedLowercase }
            .joined(separator: " ")
        return haystack.contains(query)
    }

    func recordSearchFailure(
        context: String,
        query: String?,
        curl: String?,
        error: Error
    ) {
        debugWindowState.recordSearchFailure(
            context: context,
            query: query,
            curl: curl,
            errorMessage: error.localizedDescription
        )
    }

    func normalizedUserID(_ rawID: String?) -> String? {
        guard let id = nonEmpty(rawID) else { return nil }
        return canonicalStudIPID(id)
    }

    func displayName(forUserID rawUserID: String?) -> String? {
        guard let userID = normalizedUserID(rawUserID) else { return nil }
        return nonEmpty(userDisplayNameByID[userID])
    }

    func resolveDisplayNamesIfNeeded(for rawUserIDs: [String]) async {
        let requestedIDs = Set(rawUserIDs.compactMap { normalizedUserID($0) })
        guard !requestedIDs.isEmpty else { return }

        let idsToLoad = requestedIDs.filter { userID in
            userDisplayNameByID[userID] == nil
                && !loadingUserNameIDs.contains(userID)
        }
        guard !idsToLoad.isEmpty else { return }

        loadingUserNameIDs.formUnion(idsToLoad)
        defer { loadingUserNameIDs.subtract(idsToLoad) }

        let loadedUsersByID = await repository.fetchUsersByIDs(Array(idsToLoad))

        for userID in idsToLoad {
            if let user = loadedUsersByID[userID],
               let preferredDisplayName = nonEmpty(user.preferredDisplayName) {
                userDisplayNameByID[userID] = preferredDisplayName
            }
        }
    }

    func activeFileFolderID(for courseID: String) -> String? {
        fileFolderPathByCourseID[courseID]?.last?.id
    }

    func fileContextKey(courseID: String, folderID: String?) -> String {
        "\(courseID)::\(folderID ?? "root")"
    }

    func activeFileContextKey(for courseID: String) -> String {
        fileContextKey(courseID: courseID, folderID: activeFileFolderID(for: courseID))
    }

    func folderBreadcrumbText(for courseID: String) -> String? {
        let trail = fileFolderPathByCourseID[courseID] ?? []
        guard !trail.isEmpty else { return nil }

        let names = trail.map { nonEmpty($0.name) ?? $0.id }
        return "Pfad: \(names.joined(separator: " / "))"
    }

    func openFolder(_ folder: FolderDTO, for courseID: String) {
        var trail = fileFolderPathByCourseID[courseID] ?? []
        trail.append(folder)
        fileFolderPathByCourseID[courseID] = trail
    }

    func openParentFolder(for courseID: String) {
        var trail = fileFolderPathByCourseID[courseID] ?? []
        guard !trail.isEmpty else { return }
        _ = trail.removeLast()
        fileFolderPathByCourseID[courseID] = trail
    }

    func openRootFolder(for courseID: String) {
        fileFolderPathByCourseID[courseID] = []
    }

    func fileMetadataLine(_ fileRef: CourseFileRefDTO) -> String {
        var components: [String] = []

        if let owner = nonEmpty(fileRef.ownerName) {
            components.append(owner)
        }

        if let size = fileRef.fileSize {
            components.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }

        if let downloads = fileRef.downloads {
            components.append("\(downloads) Downloads")
        }

        if let mimeType = nonEmpty(fileRef.mimeType) {
            components.append(mimeType)
        }

        if let date = parseAPIDate(fileRef.chdate) ?? parseAPIDate(fileRef.mkdate) {
            components.append(Self.fileDateFormatter.string(from: date))
        }

        return components.isEmpty ? "Keine Dateidetails" : components.joined(separator: " • ")
    }

    func iconName(forMIMEType mimeType: String?) -> String {
        guard let mimeType = nonEmpty(mimeType)?.lowercased() else {
            return "doc"
        }
        if mimeType.contains("pdf") {
            return "doc.richtext"
        }
        if mimeType.contains("image") {
            return "photo"
        }
        if mimeType.contains("zip") || mimeType.contains("compressed") {
            return "archivebox"
        }
        if mimeType.contains("word") || mimeType.contains("officedocument.wordprocessingml") {
            return "doc.text"
        }
        if mimeType.contains("excel") || mimeType.contains("spreadsheet") {
            return "tablecells"
        }
        if mimeType.contains("powerpoint") || mimeType.contains("presentation") {
            return "rectangle.on.rectangle"
        }
        return "doc"
    }

    func downloadFileViaAPI(_ fileRef: CourseFileRefDTO, contextKey: String) {
        guard !downloadingFileIDs.contains(fileRef.id) else {
            return
        }
        downloadingFileIDs.insert(fileRef.id)
        fileDownloadErrorsByFileID[fileRef.id] = nil

        Task {
            do {
                if let syncedURL = await repository.findSyncedLocalFileURL(
                    fileRefID: fileRef.id,
                    fileName: nonEmpty(fileRef.name)
                ) {
                    let opened = await openSyncedURLForDownload(
                        syncedURL,
                        fileID: fileRef.id,
                        contextKey: contextKey
                    )
                    if opened {
                        return
                    }

                    if await repository.ensureRootFolderAccessByPromptingUserIfNeeded(),
                       let refreshedURL = await repository.findSyncedLocalFileURL(
                           fileRefID: fileRef.id,
                           fileName: nonEmpty(fileRef.name)
                       ),
                       await openSyncedURLForDownload(
                           refreshedURL,
                           fileID: fileRef.id,
                           contextKey: contextKey
                       ) {
                        return
                    }
                }

                let data = try await repository.fetchFileContent(
                    fileRefID: fileRef.id,
                    fallbackDownloadPath: fileRef.downloadURLPath
                )
                let targetURL = try makeDownloadURL(for: fileRef)
                try data.write(to: targetURL, options: [.atomic])

                await MainActor.run {
                    downloadingFileIDs.remove(fileRef.id)
                    NSWorkspace.shared.open(targetURL)
                    fileDownloadErrorsByFileID[fileRef.id] = nil
                    fileErrorsByContextKey[contextKey] = nil
                }
            } catch {
                await MainActor.run {
                    downloadingFileIDs.remove(fileRef.id)
                    fileDownloadErrorsByFileID[fileRef.id] = error.localizedDescription
                    fileErrorsByContextKey[contextKey] = "Fehler beim API-Download: \(error.localizedDescription)"
                }
            }
        }
    }

    func previewFileViaApplePreview(_ fileRef: CourseFileRefDTO, contextKey: String) {
        guard !previewingFileIDs.contains(fileRef.id) else {
            return
        }
        previewingFileIDs.insert(fileRef.id)
        filePreviewErrorsByFileID[fileRef.id] = nil

        Task {
            do {
                if let syncedURL = await repository.findSyncedLocalFileURL(
                    fileRefID: fileRef.id,
                    fileName: nonEmpty(fileRef.name)
                ) {
                    let opened = await openSyncedURLForPreview(
                        syncedURL,
                        fileID: fileRef.id,
                        fileName: nonEmpty(fileRef.name),
                        contextKey: contextKey
                    )
                    if opened {
                        return
                    }

                    if await repository.ensureRootFolderAccessByPromptingUserIfNeeded(),
                       let refreshedURL = await repository.findSyncedLocalFileURL(
                           fileRefID: fileRef.id,
                           fileName: nonEmpty(fileRef.name)
                       ),
                       await openSyncedURLForPreview(
                           refreshedURL,
                           fileID: fileRef.id,
                           fileName: nonEmpty(fileRef.name),
                           contextKey: contextKey
                       ) {
                        return
                    }
                }

                let data = try await repository.fetchFileContent(
                    fileRefID: fileRef.id,
                    fallbackDownloadPath: fileRef.downloadURLPath
                )
                let targetURL = try makeQuickLookURL(for: fileRef)
                try data.write(to: targetURL, options: [.atomic])

                await MainActor.run {
                    previewingFileIDs.remove(fileRef.id)
                    selectedQuickLookFile = QuickLookPreviewFile(
                        id: "\(fileRef.id)-\(targetURL.path)",
                        title: nonEmpty(fileRef.name) ?? "Datei \(fileRef.id)",
                        url: targetURL
                    )
                    filePreviewErrorsByFileID[fileRef.id] = nil
                    fileErrorsByContextKey[contextKey] = nil
                }
            } catch {
                await MainActor.run {
                    previewingFileIDs.remove(fileRef.id)
                    filePreviewErrorsByFileID[fileRef.id] = error.localizedDescription
                    fileErrorsByContextKey[contextKey] = "Fehler bei der Vorschau: \(error.localizedDescription)"
                }
            }
        }
    }

    func openSyncedURLForDownload(_ url: URL, fileID: String, contextKey: String) async -> Bool {
        await MainActor.run {
            downloadingFileIDs.remove(fileID)

            let didAccessScope = url.startAccessingSecurityScopedResource()
            defer {
                if didAccessScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if isAppSandboxed() && !didAccessScope {
                let message = "Kein Zugriff auf lokale Sync-Datei. Ordnerzugriff wird angefordert ..."
                fileDownloadErrorsByFileID[fileID] = message
                fileErrorsByContextKey[contextKey] = message
                return false
            }

            guard NSWorkspace.shared.open(url) else {
                let message = "Datei konnte lokal nicht geoeffnet werden."
                fileDownloadErrorsByFileID[fileID] = message
                fileErrorsByContextKey[contextKey] = message
                return false
            }

            fileDownloadErrorsByFileID[fileID] = nil
            fileErrorsByContextKey[contextKey] = nil
            return true
        }
    }

    func openSyncedURLForPreview(_ url: URL, fileID: String, fileName: String?, contextKey: String) async -> Bool {
        await MainActor.run {
            if let previous = quickLookSecurityScopedURL {
                previous.stopAccessingSecurityScopedResource()
                quickLookSecurityScopedURL = nil
            }

            let didAccessScope = url.startAccessingSecurityScopedResource()
            if didAccessScope {
                quickLookSecurityScopedURL = url
            } else if isAppSandboxed() {
                previewingFileIDs.remove(fileID)
                let message = "Kein Zugriff auf lokale Sync-Datei. Ordnerzugriff wird angefordert ..."
                filePreviewErrorsByFileID[fileID] = message
                fileErrorsByContextKey[contextKey] = message
                return false
            }

            previewingFileIDs.remove(fileID)
            selectedQuickLookFile = QuickLookPreviewFile(
                id: "\(fileID)-\(url.path)",
                title: fileName ?? "Datei \(fileID)",
                url: url
            )
            filePreviewErrorsByFileID[fileID] = nil
            fileErrorsByContextKey[contextKey] = nil
            return true
        }
    }

    func isAppSandboxed() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }

        let sandboxEntitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        return (sandboxEntitlement as? Bool) == true
    }

    func makeDownloadURL(for fileRef: CourseFileRefDTO) throws -> URL {
        let fileManager = FileManager.default
        let baseName = sanitizedFilename(nonEmpty(fileRef.name) ?? "datei-\(fileRef.id)")
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("StudipSyncDownloads", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return uniqueFileURL(in: tempDirectory, preferredName: baseName)
    }

    func makeQuickLookURL(for fileRef: CourseFileRefDTO) throws -> URL {
        let fileManager = FileManager.default
        let previewDirectory = fileManager.temporaryDirectory.appendingPathComponent("StudipSyncQuickLook", isDirectory: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)

        let baseName = sanitizedFilename(nonEmpty(fileRef.name) ?? "datei-\(fileRef.id)")
        let previewName = sanitizedFilename("\(fileRef.id)-\(baseName)")
        return previewDirectory.appendingPathComponent(previewName, isDirectory: false)
    }

    func quickLookSheet(for previewFile: QuickLookPreviewFile) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(previewFile.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(previewFile.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Im Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([previewFile.url])
                }
                .buttonStyle(.bordered)

                Button("Extern oeffnen") {
                    NSWorkspace.shared.open(previewFile.url)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(appHeaderFill)

            QuickLookPreviewContainer(url: previewFile.url)
                .frame(minWidth: 760, minHeight: 520)
        }
        .onDisappear {
            if let scopedURL = quickLookSecurityScopedURL {
                scopedURL.stopAccessingSecurityScopedResource()
                quickLookSecurityScopedURL = nil
            }
        }
    }

    func uniqueFileURL(in directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        let cleanName = sanitizedFilename(preferredName)
        let baseURL = directory.appendingPathComponent(cleanName)

        if !fileManager.fileExists(atPath: baseURL.path) {
            return baseURL
        }

        let ext = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    func sanitizedFilename(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = raw.components(separatedBy: invalid)
        let joined = parts.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "datei" : joined
    }

    func scheduleTimeLine(for entry: ScheduleEntryDTO) -> String {
        let startDate = parseAPIDate(entry.start)
        let endDate = parseAPIDate(entry.end)

        if let startDate, let endDate {
            return "\(Self.scheduleTimeFormatter.string(from: startDate)) - \(Self.scheduleTimeFormatter.string(from: endDate))"
        }
        if let startDate {
            return "Ab \(Self.scheduleTimeFormatter.string(from: startDate))"
        }
        if let endDate {
            return "Bis \(Self.scheduleTimeFormatter.string(from: endDate))"
        }
        return "Keine Zeitangabe"
    }

    func eventTimeLine(for event: EventDTO) -> String {
        let startDate = parseAPIDate(event.start)
        let endDate = parseAPIDate(event.end)

        if let startDate, let endDate {
            return "\(Self.eventDateTimeFormatter.string(from: startDate)) - \(Self.eventDateTimeFormatter.string(from: endDate))"
        }
        if let startDate {
            return "Ab \(Self.eventDateTimeFormatter.string(from: startDate))"
        }
        if let endDate {
            return "Bis \(Self.eventDateTimeFormatter.string(from: endDate))"
        }
        return "Keine Zeitangabe"
    }

    func deduplicatedEvents(_ events: [EventDTO]) -> [EventDTO] {
        var seen: Set<String> = []
        var deduped: [EventDTO] = []
        deduped.reserveCapacity(events.count)

        for event in events {
            if seen.insert(event.id).inserted {
                deduped.append(event)
            }
        }

        return deduped
    }

    func eventsForCalendarDay(_ events: [EventDTO], day: Date) -> [EventDTO] {
        let calendar = Calendar.current
        return sortUserEventsForDisplay(events).filter { event in
            guard let start = parseAPIDate(event.start) else { return false }
            return calendar.isDate(start, inSameDayAs: day)
        }
    }

    func undatedEventsForCalendar(_ events: [EventDTO]) -> [EventDTO] {
        events.filter { parseAPIDate($0.start) == nil }
    }

    func scheduleEntriesForCalendarDay(_ entries: [ScheduleEntryDTO], day: Date) -> [ScheduleEntryDTO] {
        let calendar = Calendar.current
        return sortUserScheduleForDisplay(entries).filter { entry in
            guard let start = parseAPIDate(entry.start) else { return false }
            return calendar.isDate(start, inSameDayAs: day)
        }
    }

    func filterEventsToSemester(_ events: [EventDTO], semester: SemesterDTO) -> [EventDTO] {
        guard let semesterStart = semester.begin ?? semester.startOfLectures,
              let semesterEnd = semester.end ?? semester.endOfLectures else {
            return events
        }

        return events.filter { event in
            guard let eventStart = parseAPIDate(event.start) else {
                return true
            }
            return eventStart >= semesterStart && eventStart <= semesterEnd
        }
    }

    func isScheduleEntryNow(_ entry: ScheduleEntryDTO) -> Bool {
        guard let startDate = parseAPIDate(entry.start), let endDate = parseAPIDate(entry.end) else {
            return false
        }
        let now = Date()
        return now >= startDate && now <= endDate
    }

    func chatPreviewText(_ thread: StudIPResourceRepository.CourseChatThread) -> String? {
        if let content = nonEmpty(thread.previewText) {
            if content.contains("<"), content.contains(">") {
                return plainText(fromHTML: content)
            }
            return content
        }
        return nil
    }

    func chatMessageText(_ message: BlubberPostingDTO) -> String {
        if let content = nonEmpty(message.content) {
            return content
        }
        if let contentHTML = nonEmpty(message.contentHTML) {
            return plainText(fromHTML: contentHTML) ?? contentHTML
        }
        return "(keine Nachricht)"
    }

    func chatMessageMetadataLine(_ message: BlubberPostingDTO) -> String {
        var components: [String] = []

        if let discussionTime = parseAPIDate(message.discussionTime) {
            components.append(Self.fileDateFormatter.string(from: discussionTime))
        } else if let createdAt = parseAPIDate(message.mkdate) {
            components.append(Self.fileDateFormatter.string(from: createdAt))
        }

        if let authorName = displayName(forUserID: message.authorID) {
            components.append(authorName)
        } else if let authorID = normalizedUserID(message.authorID) {
            components.append("Autor \(authorID)")
        }

        return components.isEmpty ? "Nachricht \(message.id)" : components.joined(separator: " • ")
    }

    func chatMetadataLine(_ thread: StudIPResourceRepository.CourseChatThread) -> String {
        var components: [String] = []

        if let contextType = nonEmpty(thread.contextType) {
            components.append(contextType.capitalized)
        }

        if let unseen = thread.unseenComments, unseen > 0 {
            components.append("\(unseen) ungelesen")
        }

        if let latest = thread.latestActivity {
            components.append("Aktiv: \(Self.fileDateFormatter.string(from: latest))")
        } else if let changed = thread.changedAt {
            components.append("Aktualisiert: \(Self.fileDateFormatter.string(from: changed))")
        }

        if let visited = thread.visitedAt {
            components.append("Zuletzt besucht: \(Self.fileDateFormatter.string(from: visited))")
        }

        return components.isEmpty ? "Keine Chat-Metadaten" : components.joined(separator: " • ")
    }

    func wikiPreviewText(_ page: StudIPResourceRepository.CourseWikiPage) -> String? {
        guard let content = nonEmpty(page.content) else {
            return nil
        }

        let normalized = content.replacingOccurrences(of: "<!--HTML-->", with: "")
        if normalized.contains("<"), normalized.contains(">") {
            return plainText(fromHTML: normalized)
        }
        return nonEmpty(normalized)
    }

    func selectedWikiPage(
        for courseID: String,
        pages: [StudIPResourceRepository.CourseWikiPage]
    ) -> StudIPResourceRepository.CourseWikiPage? {
        if let selectedID = selectedWikiPageIDByCourseID[courseID],
           let selected = pages.first(where: { $0.id == selectedID }) {
            return selected
        }
        return pages.first
    }

    func wikiContentText(_ page: StudIPResourceRepository.CourseWikiPage) -> String {
        guard let raw = nonEmpty(page.content) else {
            return "Kein Inhalt vorhanden."
        }

        let normalized = raw.replacingOccurrences(of: "<!--HTML-->", with: "")
        guard normalized.contains("<"), normalized.contains(">"),
              let data = normalized.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return normalized
        }

        let parsed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return parsed.isEmpty ? normalized : parsed
    }

    func wikiMetadataLine(_ page: StudIPResourceRepository.CourseWikiPage) -> String {
        var components: [String] = []

        if let authorName = nonEmpty(page.authorName) {
            components.append(authorName)
        } else if let authorID = nonEmpty(page.authorID) {
            components.append("Autor \(authorID)")
        }

        if let version = page.version {
            components.append("Version \(version)")
        }

        if let changedAt = page.changedAt {
            components.append("Geaendert: \(Self.fileDateFormatter.string(from: changedAt))")
        }

        return components.isEmpty ? "Keine Wiki-Metadaten" : components.joined(separator: " • ")
    }

    func forumMetadataLine(_ category: StudIPResourceRepository.CourseForumCategory) -> String {
        var components: [String] = []

        if let position = category.position {
            components.append("Position \(position)")
        }
        components.append("ID \(category.id)")

        return components.joined(separator: " • ")
    }

    func forumEntryMetadataLine(_ entry: ForumEntryDTO) -> String {
        var components: [String] = []

        if let authorName = displayName(forUserID: entry.authorID) {
            components.append(authorName)
        } else if let authorID = normalizedUserID(entry.authorID) {
            components.append("Autor \(authorID)")
        }

        if let area = entry.area {
            components.append("Bereich \(area)")
        }
        components.append("ID \(entry.id)")

        return components.joined(separator: " • ")
    }

    func newsMetadataLine(_ newsItem: NewsDTO) -> String {
        var components: [String] = []

        if let updatedAt = parseAPIDate(newsItem.chdate) {
            components.append("Aktualisiert: \(Self.fileDateFormatter.string(from: updatedAt))")
        } else if let createdAt = parseAPIDate(newsItem.mkdate) {
            components.append("Erstellt: \(Self.fileDateFormatter.string(from: createdAt))")
        }

        if newsItem.commentsAllowed == true {
            components.append("Kommentare aktiv")
        }

        return components.isEmpty ? "ID \(newsItem.id)" : components.joined(separator: " • ")
    }

    func parseAPIDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let seconds = TimeInterval(trimmed) {
            return Date(timeIntervalSince1970: seconds)
        }

        if let date = Self.apiISO8601WithFractionalSeconds.date(from: trimmed) ?? Self.apiISO8601.date(from: trimmed) {
            return date
        }

        return nil
    }

    func plainText(fromHTML html: String) -> String? {
        guard let data = html.data(using: .utf8) else { return nil }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            let normalized = attributed.string
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return nonEmpty(normalized)
        }
        return nonEmpty(html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
    }

    static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let apiISO8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let apiISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let scheduleDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let scheduleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let eventDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let calendarDayOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}
