import AppKit
import SwiftUI

struct DebugWindowView: View {
    let repository: StudIPResourceRepository
    let state: DebugWindowState

    @State private var commandsText = ""
    @State private var isLoading = false
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Debug cURL")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Aktualisieren") {
                    Task { await loadCommands() }
                }

                Button("Kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commandsText, forType: .string)
                }
                .disabled(commandsText.isEmpty)
            }

            Text(selectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !state.searchDebugEntries.isEmpty {
                GroupBox {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(state.searchDebugEntries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(Self.debugDateFormatter.string(from: entry.timestamp)) • \(entry.context)")
                                        .font(.caption.weight(.semibold))

                                    if !entry.query.isEmpty {
                                        Text("Query: \(entry.query)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Text("Fehler: \(entry.errorMessage)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    Text(entry.curl)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if entry.id != state.searchDebugEntries.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 240)
                } label: {
                    HStack {
                        Label("Suchfehler (cURL + API-Fehler)", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Leeren") {
                            state.clearSearchFailures()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }

            TextEditor(text: $commandsText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 300)
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 420)
        .task(id: state.requestKey) {
            await loadCommands()
        }
    }

    private var selectionSummary: String {
        let semester = state.semesterID ?? "-"
        let course = state.courseID ?? "-"
        return "Semester-ID: \(semester) | Kurs-ID: \(course)"
    }

    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    private func loadCommands() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let commands = try await repository.debugCurlCommands(for: state.semesterID, courseID: state.courseID)
            commandsText = commands.joined(separator: "\n\n")
            statusMessage = "\(commands.count) Kommando(s) geladen"
        } catch {
            commandsText = ""
            statusMessage = "Fehler: \(error.localizedDescription)"
        }
    }
}
