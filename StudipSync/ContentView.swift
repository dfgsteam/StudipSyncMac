import AppKit
import SwiftUI

struct ContentView: View {
    let statusController: MenuBarStatusController
    let syncScheduler: SyncScheduler
    let semesterSelectionStore: SemesterSelectionStore
    let repository: StudIPResourceRepository

    @State private var semesterViewModel: SemesterListViewModel
    @State private var selectedSemesterID: String?
    @State private var selectedCourseID: String?
    @State private var courses: [CourseDTO] = []
    @State private var isLoadingCourses = false
    @State private var isLoadingCourseDetail = false
    @State private var courseStatusMessage = "Waehle ein Semester aus"
    @State private var curlCommandsText = ""
    @State private var isLoadingCurlCommands = false

    init(
        statusController: MenuBarStatusController,
        syncScheduler: SyncScheduler,
        semesterSelectionStore: SemesterSelectionStore,
        repository: StudIPResourceRepository
    ) {
        self.statusController = statusController
        self.syncScheduler = syncScheduler
        self.semesterSelectionStore = semesterSelectionStore
        self.repository = repository
        self._semesterViewModel = State(initialValue: SemesterListViewModel(repository: repository))
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Semester")
                        .font(.headline)
                    Spacer()
                    Button("Neu laden") {
                        semesterViewModel.loadSemesters()
                    }
                    .disabled(semesterViewModel.isLoading)
                }

                List(semesterViewModel.semesters, selection: $selectedSemesterID) { semester in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(semester.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help("Semester-ID: \(semester.id)")
                        }
                        Spacer()
                        Image(systemName: semesterSelectionStore.isActive(semesterID: semester.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(semesterSelectionStore.isActive(semesterID: semester.id) ? .green : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSemesterID = semester.id
                        selectedCourseID = nil
                    }
                    .contextMenu {
                        Button(semesterSelectionStore.isActive(semesterID: semester.id) ? "Fuer Sync deaktivieren" : "Fuer Sync aktivieren") {
                            semesterSelectionStore.setActive(!semesterSelectionStore.isActive(semesterID: semester.id), semesterID: semester.id)
                        }
                    }
                }

                Text(semesterViewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Kurse")
                        .font(.headline)
                    Spacer()
                    if isLoadingCourses {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                List(courses, selection: $selectedCourseID) { course in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.title)
                        Text(course.id)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCourseID = course.id
                    }
                }

                Text(courseStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                Text("Kursansicht")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("App-Status: \(statusController.syncState.statusText)")
                    .foregroundStyle(.secondary)

                if let selectedSemester = selectedSemester {
                    Text("Semester: \(selectedSemester.title)")
                }

                if let selectedCourse = selectedCourse {
                    Text("Kurs: \(selectedCourse.title)")
                    Text("Kurs-ID: \(selectedCourse.id)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isLoadingCourseDetail {
                        ProgressView("Lade Kursdetail ...")
                            .controlSize(.small)
                    }
                } else {
                    Text("Waehle links ein Semester und in der Mitte einen Kurs aus.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Button("Jetzt synchronisieren") {
                        syncScheduler.triggerManualSync()
                    }
                    SettingsLink {
                        Text("Einstellungen")
                    }
                }

                Divider()

                HStack {
                    Text("Debug cURL")
                        .font(.headline)
                    Spacer()
                    if isLoadingCurlCommands {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("cURL aktualisieren") {
                        Task { await loadCurlCommands() }
                    }
                }

                if !curlCommandsText.isEmpty {
                    TextEditor(text: $curlCommandsText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 160)

                    Button("cURL kopieren") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curlCommandsText, forType: .string)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 560)
        .task {
            if semesterViewModel.semesters.isEmpty {
                semesterViewModel.loadSemesters()
            }
        }
        .task(id: selectedSemesterID) {
            await loadCoursesForSelectedSemester()
            await loadCurlCommands()
        }
        .task(id: selectedCourseID) {
            await loadCourseDetailForSelectedCourse()
            await loadCurlCommands()
        }
    }

    private var selectedSemester: SemesterDTO? {
        guard let selectedSemesterID else { return nil }
        return semesterViewModel.semesters.first { $0.id == selectedSemesterID }
    }

    private var selectedCourse: CourseDTO? {
        guard let selectedCourseID else { return nil }
        return courses.first { $0.id == selectedCourseID }
    }

    private func loadCoursesForSelectedSemester() async {
        guard let selectedSemesterID else {
            courses = []
            selectedCourseID = nil
            courseStatusMessage = "Waehle ein Semester aus"
            return
        }

        isLoadingCourses = true
        selectedCourseID = nil

        do {
            let fetched = try await repository.fetchCourses(for: selectedSemesterID)
            courses = fetched.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            courseStatusMessage = fetched.isEmpty ? "Keine Kurse gefunden" : "\(fetched.count) Kurse geladen"
        } catch {
            courses = []
            courseStatusMessage = "Fehler beim Laden der Kurse: \(error.localizedDescription)"
        }

        isLoadingCourses = false
    }

    private func loadCurlCommands() async {
        isLoadingCurlCommands = true

        do {
            let commands = try await repository.debugCurlCommands(for: selectedSemesterID, courseID: selectedCourseID)
            curlCommandsText = commands.joined(separator: "\n\n")
        } catch {
            curlCommandsText = "Konnte cURL nicht erzeugen: \(error.localizedDescription)"
        }

        isLoadingCurlCommands = false
    }

    private func loadCourseDetailForSelectedCourse() async {
        guard let selectedCourseID else {
            return
        }

        isLoadingCourseDetail = true
        defer { isLoadingCourseDetail = false }

        do {
            let detailedCourse = try await repository.fetchCourse(id: selectedCourseID)
            if let index = courses.firstIndex(where: { $0.id == selectedCourseID }) {
                courses[index] = detailedCourse
            }
        } catch {
            AppLogger.error("Failed to load course detail: \(error.localizedDescription)")
        }
    }
}

#Preview {
    let container = AppContainer()
    ContentView(
        statusController: container.statusController,
        syncScheduler: container.syncScheduler,
        semesterSelectionStore: container.semesterSelectionStore,
        repository: container.resourceRepository
    )
}
