import AppKit
import SwiftUI

struct SettingsView: View {
    let settingsStore: SettingsStore
    let keychainService: KeychainService

    @State private var baseURLText: String = ""
    @State private var usernameText: String = ""
    @State private var passwordText: String = ""
    @State private var message: String = ""

    var body: some View {
        Form {
            Section("Stud.IP") {
                TextField("https://studip.uni-goettingen.de", text: $baseURLText)

                Button("Base-URL speichern") {
                    saveBaseURL()
                }

                TextField("Username", text: $usernameText)
                SecureField("Passwort", text: $passwordText)

                HStack {
                    Button("Login speichern") {
                        saveCredentials()
                    }

                    Button("Login entfernen") {
                        deleteCredentials()
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
            loadCredentials()
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

    private func saveCredentials() {
        let username = usernameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !passwordText.isEmpty else {
            message = "Bitte Username und Passwort eingeben."
            return
        }

        do {
            let credentials = HTTPBasicCredentials(username: username, password: passwordText)
            try keychainService.saveCredentials(credentials, for: settingsStore.configuration.baseURL)
            message = "Login sicher gespeichert."
            AppLogger.secretRedacted("Credentials updated")
        } catch {
            message = "Login konnte nicht gespeichert werden."
            AppLogger.error("Saving credentials failed: \(error.localizedDescription)")
        }
    }

    private func deleteCredentials() {
        do {
            try keychainService.deleteCredentials(for: settingsStore.configuration.baseURL)
            usernameText = ""
            passwordText = ""
            message = "Login entfernt."
        } catch {
            message = "Login konnte nicht entfernt werden."
            AppLogger.error("Deleting credentials failed: \(error.localizedDescription)")
        }
    }

    private func loadCredentials() {
        do {
            if let credentials = try keychainService.readCredentials(for: settingsStore.configuration.baseURL) {
                usernameText = credentials.username
                passwordText = credentials.password
            } else {
                usernameText = ""
                passwordText = ""
            }
        } catch {
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
