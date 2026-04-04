import AppKit
import Security
import SwiftUI

struct SettingsView: View {
    let settingsStore: SettingsStore
    let keychainService: KeychainService
    let metadataCache: MetadataCache
    let sharedCourseParticipationCache: SharedCourseParticipationCache

    @State private var baseURLText: String = ""
    @State private var apiKeyText: String = ""
    @State private var usernameText: String = ""
    @State private var passwordText: String = ""
    @State private var message: String = ""
    @State private var rootFolderAccessMessage: String = ""
    @State private var rootFolderAccessHasError = false
    @State private var isClearingCache = false
    @State private var semesterMinFilterDate: Date = Calendar.current.date(from: DateComponents(year: 2022, month: 4, day: 1)) ?? Date()
    @State private var semesterMaxFilterDate: Date = Date()

    var body: some View {
        Form {
            Section("Stud.IP") {
                TextField("https://studip.uni-goettingen.de", text: $baseURLText)

                Button("Base-URL speichern") {
                    saveBaseURL()
                }

                SecureField("API-Key", text: $apiKeyText)

                HStack {
                    Button("API-Key speichern") {
                        saveAPIKey()
                    }

                    Button("Zugangsdaten entfernen") {
                        deleteAllCredentials()
                    }
                }

                Divider()

                Text("Optionaler Fallback fuer Instanzen ohne API-Key-Auth:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Username", text: $usernameText)
                SecureField("Passwort", text: $passwordText)

                Button("Fallback-Login speichern") {
                    saveBasicCredentials()
                }
            }

            Section("Dateipfad") {
                Text(rootFolderDisplayText())
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Dateien aus der Dateiansicht werden hier bevorzugt geoeffnet, falls sie bereits synchronisiert wurden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Sync-Ordner auswaehlen") {
                    chooseRootFolder()
                }

                Button("Ordnerzugriff pruefen") {
                    refreshRootFolderAccessStatus()
                }

                if !rootFolderAccessMessage.isEmpty {
                    Text(rootFolderAccessMessage)
                        .font(.footnote)
                        .foregroundStyle(rootFolderAccessHasError ? .red : .secondary)
                }
            }

            Section("Synchronisierung") {
                Stepper(
                    "Intervall: \(settingsStore.configuration.syncIntervalMinutes) min",
                    value: Binding(
                        get: { settingsStore.configuration.syncIntervalMinutes },
                        set: { settingsStore.updateSyncInterval(minutes: $0) }
                    ),
                    in: 5...60
                )

                Stepper(
                    "Parallele Downloads: \(settingsStore.configuration.maxConcurrentFileDownloads)",
                    value: Binding(
                        get: { settingsStore.configuration.maxConcurrentFileDownloads },
                        set: { settingsStore.updateMaxConcurrentFileDownloads($0) }
                    ),
                    in: 2...4
                )

                Toggle(
                    "Sync bei Low Power pausieren",
                    isOn: Binding(
                        get: { settingsStore.configuration.pauseSyncOnLowPowerMode },
                        set: { settingsStore.updatePauseSyncOnLowPowerMode($0) }
                    )
                )

                Toggle(
                    "Nur bei WLAN synchronisieren",
                    isOn: Binding(
                        get: { settingsStore.configuration.syncOnlyOnWiFi },
                        set: { settingsStore.updateSyncOnlyOnWiFi($0) }
                    )
                )
            }

            Section("Semester") {
                Toggle("Nur Semester ab Datum laden", isOn: Binding(
                    get: { settingsStore.configuration.semesterSearchStartDate != nil },
                    set: { isEnabled in
                        if isEnabled {
                            let effectiveDate = settingsStore.configuration.semesterSearchStartDate ?? semesterMinFilterDate
                            settingsStore.updateSemesterSearchStartDate(effectiveDate)
                        } else {
                            settingsStore.updateSemesterSearchStartDate(nil)
                        }
                    }
                ))

                if settingsStore.configuration.semesterSearchStartDate != nil {
                    DatePicker(
                        "Startdatum",
                        selection: Binding(
                            get: { settingsStore.configuration.semesterSearchStartDate ?? semesterMinFilterDate },
                            set: { newDate in
                                semesterMinFilterDate = newDate
                                settingsStore.updateSemesterSearchStartDate(newDate)
                            }
                        ),
                        displayedComponents: [.date]
                    )
                }

                Toggle("Nur Semester bis Datum laden", isOn: Binding(
                    get: { settingsStore.configuration.semesterSearchEndDate != nil },
                    set: { isEnabled in
                        if isEnabled {
                            let effectiveDate = settingsStore.configuration.semesterSearchEndDate ?? semesterMaxFilterDate
                            settingsStore.updateSemesterSearchEndDate(effectiveDate)
                        } else {
                            settingsStore.updateSemesterSearchEndDate(nil)
                        }
                    }
                ))

                if settingsStore.configuration.semesterSearchEndDate != nil {
                    DatePicker(
                        "Enddatum",
                        selection: Binding(
                            get: { settingsStore.configuration.semesterSearchEndDate ?? semesterMaxFilterDate },
                            set: { newDate in
                                semesterMaxFilterDate = newDate
                                settingsStore.updateSemesterSearchEndDate(newDate)
                            }
                        ),
                        displayedComponents: [.date]
                    )
                }
            }

            Section("Cache") {
                Text("Leert lokale Cache-Daten (Metadaten + lokale Teilnehmer-Statistik).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(isClearingCache ? "Cache wird geleert ..." : "Cache leeren") {
                    clearLocalCaches()
                }
                .disabled(isClearingCache)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onAppear {
            baseURLText = settingsStore.configuration.baseURL.absoluteString
            if let configuredDate = settingsStore.configuration.semesterSearchStartDate {
                semesterMinFilterDate = configuredDate
            }
            if let configuredDate = settingsStore.configuration.semesterSearchEndDate {
                semesterMaxFilterDate = configuredDate
            }
            loadCredentials()
            refreshRootFolderAccessStatus()
        }
    }

    private func saveBaseURL() {
        guard let normalized = BaseURLNormalizer.normalizeHTTPSURL(baseURLText) else {
            message = "Ungueltige URL. Bitte HTTPS verwenden."
            return
        }

        settingsStore.updateBaseURL(normalized)
        message = "Base-URL gespeichert."
        loadCredentials()
    }

    private func saveAPIKey() {
        let apiKey = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            message = "Bitte API-Key eingeben."
            return
        }

        do {
            try keychainService.saveAPIKey(apiKey, for: settingsStore.configuration.baseURL)
            message = "API-Key sicher gespeichert."
            AppLogger.secretRedacted("API key updated")
        } catch {
            message = "API-Key konnte nicht gespeichert werden."
            AppLogger.error("Saving API key failed: \(error.localizedDescription)")
        }
    }

    private func saveBasicCredentials() {
        let username = usernameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !passwordText.isEmpty else {
            message = "Bitte Username und Passwort eingeben."
            return
        }

        do {
            let credentials = HTTPBasicCredentials(username: username, password: passwordText)
            try keychainService.saveCredentials(credentials, for: settingsStore.configuration.baseURL)
            message = "Fallback-Login sicher gespeichert."
            AppLogger.secretRedacted("Credentials updated")
        } catch {
            message = "Login konnte nicht gespeichert werden."
            AppLogger.error("Saving credentials failed: \(error.localizedDescription)")
        }
    }

    private func deleteAllCredentials() {
        do {
            try keychainService.deleteCredentials(for: settingsStore.configuration.baseURL)
            apiKeyText = ""
            usernameText = ""
            passwordText = ""
            message = "Zugangsdaten entfernt."
        } catch {
            message = "Zugangsdaten konnten nicht entfernt werden."
            AppLogger.error("Deleting credentials failed: \(error.localizedDescription)")
        }
    }

    private func loadCredentials() {
        do {
            let stored = try keychainService.readStoredCredentials(for: settingsStore.configuration.baseURL)
            apiKeyText = stored?.apiKey ?? ""
            usernameText = stored?.username ?? ""
            passwordText = stored?.password ?? ""
        } catch {
            apiKeyText = ""
            usernameText = ""
            passwordText = ""
            AppLogger.error("Reading credentials failed: \(error.localizedDescription)")
        }
    }

    private func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswaehlen"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                settingsStore.updateRootFolderBookmark(bookmark)
                message = "Sync-Ordner gespeichert."
                refreshRootFolderAccessStatus()
            } catch {
                message = "Sync-Ordner konnte nicht gespeichert werden."
                AppLogger.error("Storing root folder bookmark failed: \(error.localizedDescription)")
            }
        }
    }

    private func clearLocalCaches() {
        let baseURL = settingsStore.configuration.baseURL
        isClearingCache = true

        Task {
            do {
                try await metadataCache.clear(baseURL: baseURL)
                try await sharedCourseParticipationCache.clearAll()
                await MainActor.run {
                    NotificationCenter.default.post(name: .studipCachesCleared, object: nil)
                    isClearingCache = false
                    message = "Lokale Cache-Daten wurden geleert."
                }
            } catch {
                await MainActor.run {
                    isClearingCache = false
                    message = "Cache konnte nicht geleert werden."
                }
                AppLogger.error("Clearing local caches failed: \(error.localizedDescription)")
            }
        }
    }

    private func rootFolderDisplayText() -> String {
        guard let bookmark = settingsStore.configuration.rootFolderBookmark else {
            return "Kein Sync-Ordner ausgewaehlt"
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return isStale ? "Ordnerpfad veraltet: \(url.path)" : "Aktueller Sync-Ordner: \(url.path)"
        } catch {
            return "Sync-Ordner konnte nicht gelesen werden"
        }
    }

    private func refreshRootFolderAccessStatus() {
        let result = evaluateRootFolderAccess()
        rootFolderAccessMessage = result.message
        rootFolderAccessHasError = !result.ok
    }

    private func evaluateRootFolderAccess() -> (ok: Bool, message: String) {
        guard let bookmark = settingsStore.configuration.rootFolderBookmark else {
            return (false, "Kein Sync-Ordner ausgewaehlt.")
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                let refreshedBookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                settingsStore.updateRootFolderBookmark(refreshedBookmark)
            }

            let didAccessScope = url.startAccessingSecurityScopedResource()
            defer {
                if didAccessScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if isAppSandboxed() && !didAccessScope {
                return (false, "Kein Ordnerzugriff. Bitte Sync-Ordner erneut auswaehlen.")
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return (false, "Sync-Ordner existiert nicht mehr.")
            }

            do {
                _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch {
                return (false, "Sync-Ordner kann nicht gelesen werden (Verzeichniszugriff fehlgeschlagen).")
            }

            let probeURL = url.appendingPathComponent("studipsync-access-\(UUID().uuidString).tmp", isDirectory: false)
            let created = FileManager.default.createFile(atPath: probeURL.path, contents: Data(), attributes: nil)
            guard created else {
                return (false, "Sync-Ordner ist nur teilweise autorisiert (Schreibtest fehlgeschlagen). Bitte Ordner erneut auswaehlen.")
            }

            do {
                let handle = try FileHandle(forWritingTo: probeURL)
                defer { try? handle.close() }
                try handle.write(contentsOf: Data("probe".utf8))
                try FileManager.default.removeItem(at: probeURL)
            } catch {
                try? FileManager.default.removeItem(at: probeURL)
                return (false, "Sync-Ordner ist nur teilweise autorisiert (Schreibtest fehlgeschlagen). Bitte Ordner erneut auswaehlen.")
            }

            return (true, "Ordnerzugriff aktiv.")
        } catch {
            return (false, "Sync-Ordner konnte nicht gelesen werden: \(error.localizedDescription)")
        }
    }

    private func isAppSandboxed() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }

        let sandboxEntitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        return (sandboxEntitlement as? Bool) == true
    }
}
