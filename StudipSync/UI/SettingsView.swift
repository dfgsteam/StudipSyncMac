import AppKit
import SwiftUI

struct SettingsView: View {
    let settingsStore: SettingsStore
    let keychainService: KeychainService

    @State private var baseURLText: String = ""
    @State private var apiKeyText: String = ""
    @State private var message: String = ""

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

                    Button("API-Key entfernen") {
                        deleteAPIKey()
                    }
                }
            }

            Section("Speicherort") {
                Text(rootFolderDisplayText())
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Root-Ordner auswählen") {
                    chooseRootFolder()
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
            loadAPIKey()
        }
    }

    private func saveBaseURL() {
        guard let normalized = BaseURLNormalizer.normalizeHTTPSURL(baseURLText) else {
            message = "Ungueltige URL. Bitte HTTPS verwenden."
            return
        }

        settingsStore.updateBaseURL(normalized)
        message = "Base-URL gespeichert."
    }

    private func saveAPIKey() {
        do {
            try keychainService.saveAPIKey(apiKeyText, for: settingsStore.configuration.baseURL)
            message = "API-Key sicher gespeichert."
            AppLogger.secretRedacted("API key updated")
        } catch {
            message = "API-Key konnte nicht gespeichert werden."
            AppLogger.error("Saving API key failed: \(error.localizedDescription)")
        }
    }

    private func deleteAPIKey() {
        do {
            try keychainService.deleteAPIKey(for: settingsStore.configuration.baseURL)
            apiKeyText = ""
            message = "API-Key entfernt."
        } catch {
            message = "API-Key konnte nicht entfernt werden."
            AppLogger.error("Deleting API key failed: \(error.localizedDescription)")
        }
    }

    private func loadAPIKey() {
        do {
            apiKeyText = try keychainService.readAPIKey(for: settingsStore.configuration.baseURL) ?? ""
        } catch {
            apiKeyText = ""
            AppLogger.error("Reading API key failed: \(error.localizedDescription)")
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
                message = "Root-Ordner gespeichert."
            } catch {
                message = "Root-Ordner konnte nicht gespeichert werden."
                AppLogger.error("Storing root folder bookmark failed: \(error.localizedDescription)")
            }
        }
    }

    private func rootFolderDisplayText() -> String {
        guard let bookmark = settingsStore.configuration.rootFolderBookmark else {
            return "Kein Root-Ordner ausgewaehlt"
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return isStale ? "Ordnerpfad veraltet: \(url.path)" : "Aktueller Root-Ordner: \(url.path)"
        } catch {
            return "Root-Ordner konnte nicht gelesen werden"
        }
    }
}
