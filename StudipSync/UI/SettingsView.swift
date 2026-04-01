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
        .frame(width: 500)
        .padding()
        .onAppear {
            baseURLText = settingsStore.configuration.baseURL.absoluteString
            loadAPIKey()
        }
    }

    private func saveBaseURL() {
        guard let normalized = normalizeHTTPSURL(baseURLText) else {
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

    private func normalizeHTTPSURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "),
              let url = URL(string: trimmed),
              let scheme = url.scheme,
              scheme.lowercased() == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = normalizedPath
        return components.url
    }
}
