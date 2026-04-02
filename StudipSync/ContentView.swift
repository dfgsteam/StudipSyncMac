import AppKit
import SwiftUI

struct ContentView: View {
    private enum SidebarPage: String, CaseIterable, Hashable, Identifiable {
        case start
        case benutzer
        case einrichtungen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .start: return "Start"
            case .benutzer: return "Benutzer"
            case .einrichtungen: return "Einrichtungen"
            }
        }

        var systemImage: String {
            switch self {
            case .start: return "house"
            case .benutzer: return "person.2"
            case .einrichtungen: return "building.2"
            }
        }
    }

    private struct CourseDetailSection: Identifiable, Hashable {
        let id: String
        let title: String

        static let description = CourseDetailSection(id: "description", title: "Beschreibung")
        static let files = CourseDetailSection(id: "files", title: "Dateien")
        static let chat = CourseDetailSection(id: "chat", title: "Chat")
        static let wiki = CourseDetailSection(id: "wiki", title: "Wiki")
        static let participants = CourseDetailSection(id: "participants", title: "Teilnehmer")
        static let forum = CourseDetailSection(id: "forum", title: "Forum")
    }

    let statusController: MenuBarStatusController
    let syncScheduler: SyncScheduler
    let semesterSelectionStore: SemesterSelectionStore
    let repository: StudIPResourceRepository
    let debugWindowState: DebugWindowState

    @Environment(\.openWindow) private var openWindow

    @State private var semesterViewModel: SemesterListViewModel
    @State private var selectedSidebarPage: SidebarPage? = .start
    @State private var selectedSemesterID: String?
    @State private var selectedCourseID: String?
    @State private var courses: [CourseDTO] = []
    @State private var isLoadingCourses = false
    @State private var isLoadingCourseDetail = false
    @State private var courseStatusMessage = "Waehle ein Semester aus"
    @State private var selectedCourseDetailSectionID = CourseDetailSection.description.id
    @State private var rawSectionResponses: [String: String] = [:]
    @State private var isLoadingRawSectionResponse = false
    @State private var rawSectionResponseErrors: [String: String] = [:]
    @State private var filesByCourseID: [String: [StudIPResourceRepository.CourseFileRef]] = [:]
    @State private var fileErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingFiles = false
    @State private var chatsByCourseID: [String: [StudIPResourceRepository.CourseChatThread]] = [:]
    @State private var chatErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingChats = false
    @State private var wikisByCourseID: [String: [StudIPResourceRepository.CourseWikiPage]] = [:]
    @State private var wikiErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingWikis = false
    @State private var participantsByCourseID: [String: [StudIPResourceRepository.CourseParticipant]] = [:]
    @State private var participantErrorsByCourseID: [String: String] = [:]
    @State private var isLoadingParticipants = false
    @State private var selectedParticipantForInfo: StudIPResourceRepository.CourseParticipant?

    init(
        statusController: MenuBarStatusController,
        syncScheduler: SyncScheduler,
        semesterSelectionStore: SemesterSelectionStore,
        repository: StudIPResourceRepository,
        debugWindowState: DebugWindowState
    ) {
        self.statusController = statusController
        self.syncScheduler = syncScheduler
        self.semesterSelectionStore = semesterSelectionStore
        self.repository = repository
        self.debugWindowState = debugWindowState
        self._semesterViewModel = State(initialValue: SemesterListViewModel(repository: repository))
    }

    var body: some View {
        NavigationSplitView {
            pagesSidebar
        } content: {
            contentForSelectedPage
        } detail: {
            detailForSelectedPage
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 560)
        .task {
            if semesterViewModel.semesters.isEmpty {
                semesterViewModel.loadSemesters()
            }
        }
        .task(id: selectedSemesterID) {
            debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
            await loadCoursesForSelectedSemester()
        }
        .task(id: selectedCourseID) {
            debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
            await loadCourseDetailForSelectedCourse()
        }
        .task(id: rawResponseTaskID) {
            await loadRawResponseForSelectedSection()
        }
        .task(id: fileListTaskID) {
            await loadFilesForSelectedSection()
        }
        .task(id: chatListTaskID) {
            await loadChatsForSelectedSection()
        }
        .task(id: wikiListTaskID) {
            await loadWikisForSelectedSection()
        }
        .task(id: participantTaskID) {
            await loadParticipantsForSelectedSection()
        }
        .task(id: semesterIDsSignature) {
            selectFirstSemesterIfNeeded()
        }
        .sheet(item: $selectedParticipantForInfo) { participant in
            participantInfoSheet(for: participant)
        }
    }

    private var selectedPage: SidebarPage {
        selectedSidebarPage ?? .start
    }

    private var pagesSidebar: some View {
        VStack(spacing: 0) {
            List(SidebarPage.allCases) { page in
                Button {
                    selectedSidebarPage = page
                    selectedSemesterID = nil
                    selectedCourseID = nil
                } label: {
                    Label(page.title, systemImage: page.systemImage)
                        .foregroundStyle(isSelectedMenuPage(page) ? Color.accentColor : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isSelectedMenuPage(page) ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
            .frame(minHeight: 150, maxHeight: 170)

            Divider()
            semesterSidebar
        }
    }

    private var contentForSelectedPage: some View {
        Group {
            if selectedSemesterID != nil {
                coursesColumn
            } else {
                switch selectedPage {
                case .start:
                    startContentColumn
                case .benutzer:
                    benutzerContentColumn
                case .einrichtungen:
                    einrichtungenContentColumn
                }
            }
        }
    }

    private var detailForSelectedPage: some View {
        Group {
            if selectedSemesterID != nil {
                detailColumn
            } else {
                switch selectedPage {
                case .start:
                    startDetailColumn
                case .benutzer:
                    benutzerDetailColumn
                case .einrichtungen:
                    einrichtungenDetailColumn
                }
            }
        }
    }

    private var semesterSidebar: some View {
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
    }

    private var startContentColumn: some View {
        staticMenuContentColumn(
            title: "Start",
            subtitle: "Statische Testseite: Inhaltsbereich"
        )
    }

    private var startDetailColumn: some View {
        staticMenuDetailColumn(
            title: "Start",
            subtitle: "Statische Testseite: Detailbereich"
        )
    }

    private var benutzerContentColumn: some View {
        staticMenuContentColumn(
            title: "Benutzer",
            subtitle: "Statische Testseite: Inhaltsbereich"
        )
    }

    private var benutzerDetailColumn: some View {
        staticMenuDetailColumn(
            title: "Benutzer",
            subtitle: "Statische Testseite: Detailbereich"
        )
    }

    private var einrichtungenContentColumn: some View {
        staticMenuContentColumn(
            title: "Einrichtungen",
            subtitle: "Statische Testseite: Inhaltsbereich"
        )
    }

    private var einrichtungenDetailColumn: some View {
        staticMenuDetailColumn(
            title: "Einrichtungen",
            subtitle: "Statische Testseite: Detailbereich"
        )
    }

    private func staticMenuContentColumn(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            GroupBox("Testinhalt") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subtitle)
                    Text("Diese Seite ist bewusst statisch und dient als Platzhalter.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(12)
    }

    private func staticMenuDetailColumn(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
            GroupBox("Testdetails") {
                Text("Statischer Detailbereich fuer UI-Tests.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            Divider()
            detailActions
        }
        .padding(24)
    }

    private var coursesColumn: some View {
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    if let subtitle = nonEmpty(course.subtitle) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let number = nonEmpty(course.courseNumber) {
                        Text("Kursnr. \(number)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let type = courseTypeLabel(for: course) {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedCourseID = course.id
                }
            }
            .listStyle(.inset)

            Text(courseStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedCourse = selectedCourse {
                        courseDetailCard(for: selectedCourse)
                        if isLoadingCourseDetail {
                            ProgressView("Lade Kursdetail ...")
                                .controlSize(.small)
                        }
                    } else if let selectedSemester {
                        semesterStatusPlaceholder(for: selectedSemester)
                    } else {
                        Text("Waehle links ein Semester aus.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            detailActions
        }
        .padding(24)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kursansicht")
                .font(.title2.weight(.semibold))

            Text("App-Status: \(statusController.syncState.statusText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let selectedSemester = selectedSemester {
                Text(selectedSemester.title)
                    .font(.headline)
            }
        }
    }

    private func semesterStatusPlaceholder(for semester: SemesterDTO) -> some View {
        GroupBox("Semester-Status") {
            VStack(alignment: .leading, spacing: 10) {
                Text(semester.title)
                    .font(.title3.weight(.semibold))
                Text("Dies ist eine Platzhalter-Statusseite fuer das Semester.")
                    .foregroundStyle(.secondary)
                Text("Waehle in der mittleren Spalte einen Kurs aus, um Kursdetails zu sehen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var detailActions: some View {
        HStack {
            Button("Jetzt synchronisieren") {
                syncScheduler.triggerManualSync()
            }

            SettingsLink {
                Text("Einstellungen")
            }

            Button("Debug öffnen") {
                debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
                openWindow(id: "debugWindow")
            }
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

    private var defaultCourseDetailSections: [CourseDetailSection] {
        [
            .description,
            .files,
            .chat,
            .wiki,
            .participants,
            .forum
        ]
    }

    private var rawResponseTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var participantTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var fileListTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var chatListTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var wikiListTaskID: String {
        "\(selectedCourseID ?? "none"):\(selectedCourseDetailSectionID)"
    }

    private var semesterIDsSignature: String {
        semesterViewModel.semesters.map(\.id).joined(separator: ",")
    }

    private func isSelectedMenuPage(_ page: SidebarPage) -> Bool {
        selectedSidebarPage == page
    }

    private func selectFirstSemesterIfNeeded() {
        guard selectedSemesterID == nil else { return }
        guard let firstSemester = semesterViewModel.semesters.first else { return }
        selectedSemesterID = firstSemester.id
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

    private func loadCourseDetailForSelectedCourse() async {
        guard let selectedCourseID else {
            return
        }

        selectedCourseDetailSectionID = CourseDetailSection.description.id
        rawSectionResponses = [:]
        rawSectionResponseErrors = [:]
        selectedParticipantForInfo = nil
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

    @ViewBuilder
    private func courseDetailCard(for course: CourseDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(course.title)
                        .font(.title3.weight(.semibold))
                    if let subtitle = nonEmpty(course.subtitle) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let summary = courseMetaSummary(for: course) {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Uebersicht", systemImage: "info.circle")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Ort", nonEmpty(course.location))
                    detailRow("Startsemester", nonEmpty(course.startSemesterRef))
                    detailRow("Institut", nonEmpty(course.instituteID))
                    detailRow("Sem-Klasse", nonEmpty(course.semClassID))
                    detailRow("Sem-Typ", nonEmpty(course.semTypeID))
                    detailRow("Zusatz", nonEmpty(course.miscellaneous))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Metadaten", systemImage: "square.text.square")
                    .font(.headline)
            }

            Text("Kursbereich")
                .font(.headline)
            Picker("Kursbereich", selection: $selectedCourseDetailSectionID) {
                ForEach(defaultCourseDetailSections) { section in
                    Text(section.title).tag(section.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            GroupBox {
                courseDetailSectionContent(for: course, sectionID: selectedCourseDetailSectionID)
            } label: {
                Text(sectionTitle(for: selectedCourseDetailSectionID))
                    .font(.headline)
            }
        }
    }

    private func courseMetaSummary(for course: CourseDTO) -> String? {
        var parts: [String] = []
        if let number = nonEmpty(course.courseNumber) {
            parts.append("Kursnr. \(number)")
        }
        if let type = courseTypeLabel(for: course) {
            parts.append(type)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func courseTypeLabel(for course: CourseDTO) -> String? {
        if let type = course.courseType {
            return "Typ \(type)"
        }
        return nonEmpty(course.courseTypeID)
    }

    @ViewBuilder
    private func courseDetailSectionContent(for course: CourseDTO, sectionID: String) -> some View {
        switch sectionID {
        case CourseDetailSection.description.id:
            if let description = nonEmpty(course.description) {
                ScrollView {
                    Text(description)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 220)
            } else {
                emptySectionText("Keine Beschreibung vorhanden.")
            }

        case CourseDetailSection.files.id:
            VStack(alignment: .leading, spacing: 8) {
                Text("Dateien fuer diesen Kurs:")
                filesBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.chat.id:
            VStack(alignment: .leading, spacing: 8) {
                Text("Chat/Threads fuer diesen Kurs:")
                chatsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.wiki.id:
            VStack(alignment: .leading, spacing: 8) {
                Text("Wiki-Seiten fuer diesen Kurs:")
                wikisBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.participants.id:
            VStack(alignment: .leading, spacing: 8) {
                Text("Teilnehmer in diesem Kurs:")
                participantsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.forum.id:
            VStack(alignment: .leading, spacing: 8) {
                Text("Forum-Kategorien fuer diesen Kurs:")
                rawResponseBlock(for: course, sectionID: sectionID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            emptySectionText("Dieser Bereich ist noch nicht belegt.")
        }
    }

    private func sectionTitle(for sectionID: String) -> String {
        defaultCourseDetailSections.first(where: { $0.id == sectionID })?.title ?? "Bereich"
    }

    private func emptySectionText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func rawResponseBlock(for course: CourseDTO, sectionID: String) -> some View {
        if let endpointPath = sectionEndpointPath(for: sectionID, courseID: course.id) {
            Text(endpointPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if isLoadingRawSectionResponse, rawSectionResponses[sectionID] == nil {
            ProgressView("Lade Response ...")
                .controlSize(.small)
        } else if let response = rawSectionResponses[sectionID] {
            ScrollView {
                Text(response)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 240)
            .padding(10)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let rawSectionResponseError = rawSectionResponseErrors[sectionID] {
            Text(rawSectionResponseError)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Noch keine Response geladen.")
                .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func filesBlock(for course: CourseDTO) -> some View {
        if let endpointPath = sectionEndpointPath(for: CourseDetailSection.files.id, courseID: course.id) {
            Text(endpointPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if isLoadingFiles, filesByCourseID[course.id] == nil {
            ProgressView("Lade Dateien ...")
                .controlSize(.small)
        } else if let files = filesByCourseID[course.id], !files.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(files) { fileRef in
                        fileRow(fileRef)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140, maxHeight: 300)
        } else if let errorText = fileErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Dateien gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fileRow(_ fileRef: StudIPResourceRepository.CourseFileRef) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(forMIMEType: fileRef.mimeType))
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(fileRef.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Text(fileMetadataLine(fileRef))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let description = nonEmpty(fileRef.description) {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button {
                openFile(fileRef)
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .disabled(fileRef.downloadURL == nil)
            .help(fileRef.downloadURL == nil ? "Kein Download-Link" : "Datei herunterladen/oeffnen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func chatsBlock(for course: CourseDTO) -> some View {
        if let endpointPath = sectionEndpointPath(for: CourseDetailSection.chat.id, courseID: course.id) {
            Text(endpointPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if isLoadingChats, chatsByCourseID[course.id] == nil {
            ProgressView("Lade Chat ...")
                .controlSize(.small)
        } else if let threads = chatsByCourseID[course.id], !threads.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(threads) { thread in
                        chatRow(thread)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 280)
        } else if let errorText = chatErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Chat-Threads gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chatRow(_ thread: StudIPResourceRepository.CourseChatThread) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: thread.isFollowed == true ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    if let preview = chatPreviewText(thread) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if let unseen = thread.unseenComments, unseen > 0 {
                    Text("\(unseen)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            Text(chatMetadataLine(thread))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if thread.isCommentable == true { smallBadge("Kommentierbar") }
                if thread.isWritable == true { smallBadge("Schreibbar") }
                if thread.isReadable == true { smallBadge("Lesbar") }
                if thread.isFollowed == true { smallBadge("Abonniert") }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func smallBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.18))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func wikisBlock(for course: CourseDTO) -> some View {
        if let endpointPath = sectionEndpointPath(for: CourseDetailSection.wiki.id, courseID: course.id) {
            Text(endpointPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if isLoadingWikis, wikisByCourseID[course.id] == nil {
            ProgressView("Lade Wiki ...")
                .controlSize(.small)
        } else if let pages = wikisByCourseID[course.id], !pages.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(pages) { page in
                        wikiRow(page)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 280)
        } else if let errorText = wikiErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Wiki-Seiten gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wikiRow(_ page: StudIPResourceRepository.CourseWikiPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "book.pages")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(page.keyword)
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    if let preview = wikiPreviewText(page) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }

            Text(wikiMetadataLine(page))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func participantsBlock(for course: CourseDTO) -> some View {
        if let endpointPath = sectionEndpointPath(for: CourseDetailSection.participants.id, courseID: course.id) {
            Text(endpointPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if isLoadingParticipants, participantsByCourseID[course.id] == nil {
            ProgressView("Lade Teilnehmer ...")
                .controlSize(.small)
        } else if let participants = participantsByCourseID[course.id], !participants.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(participants) { participant in
                        participantRow(participant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140, maxHeight: 280)
        } else if let errorText = participantErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Teilnehmer gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func participantRow(_ participant: StudIPResourceRepository.CourseParticipant) -> some View {
        let initial = participant.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() } ?? "?"

        return HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .overlay {
                    Text(initial)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(participant.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(participantMetadataLine(participant))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                selectedParticipantForInfo = participant
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Personeninfos")

            Button {
                openMail(for: participant)
            } label: {
                Image(systemName: "envelope")
            }
            .buttonStyle(.borderless)
            .disabled(nonEmpty(participant.email) == nil)
            .help(nonEmpty(participant.email) == nil ? "Keine Mailadresse vorhanden" : "Mail senden")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func loadRawResponseForSelectedSection() async {
        guard let selectedCourseID else { return }
        guard let section = repositorySection(for: selectedCourseDetailSectionID) else {
            return
        }
        guard rawSectionResponses[selectedCourseDetailSectionID] == nil else {
            return
        }

        let requestCourseID = selectedCourseID
        let requestSectionID = selectedCourseDetailSectionID

        isLoadingRawSectionResponse = true
        rawSectionResponseErrors[requestSectionID] = nil
        defer {
            if selectedCourseID == requestCourseID, selectedCourseDetailSectionID == requestSectionID {
                isLoadingRawSectionResponse = false
            }
        }

        do {
            let response = try await repository.fetchRawCourseSectionResponse(
                courseID: requestCourseID,
                section: section
            )
            if selectedCourseID == requestCourseID {
                rawSectionResponses[requestSectionID] = response
            }
        } catch {
            if selectedCourseID == requestCourseID {
                rawSectionResponseErrors[requestSectionID] = error.localizedDescription
            }
        }
    }

    private func loadFilesForSelectedSection() async {
        guard selectedCourseDetailSectionID == CourseDetailSection.files.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        guard filesByCourseID[selectedCourseID] == nil else {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingFiles = true
        fileErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingFiles = false
            }
        }

        do {
            let files = try await repository.fetchCourseFiles(courseID: requestCourseID)
            if selectedCourseID == requestCourseID {
                filesByCourseID[requestCourseID] = files
            }
        } catch {
            if selectedCourseID == requestCourseID {
                fileErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Dateien: \(error.localizedDescription)"
            }
        }
    }

    private func loadChatsForSelectedSection() async {
        guard selectedCourseDetailSectionID == CourseDetailSection.chat.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        guard chatsByCourseID[selectedCourseID] == nil else {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingChats = true
        chatErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingChats = false
            }
        }

        do {
            let threads = try await repository.fetchCourseChatThreads(courseID: requestCourseID)
            if selectedCourseID == requestCourseID {
                chatsByCourseID[requestCourseID] = threads
            }
        } catch {
            if selectedCourseID == requestCourseID {
                chatErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Chat-Threads: \(error.localizedDescription)"
            }
        }
    }

    private func loadWikisForSelectedSection() async {
        guard selectedCourseDetailSectionID == CourseDetailSection.wiki.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        guard wikisByCourseID[selectedCourseID] == nil else {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingWikis = true
        wikiErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingWikis = false
            }
        }

        do {
            let pages = try await repository.fetchCourseWikiPages(courseID: requestCourseID)
            if selectedCourseID == requestCourseID {
                wikisByCourseID[requestCourseID] = pages
            }
        } catch {
            if selectedCourseID == requestCourseID {
                wikiErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Wiki-Seiten: \(error.localizedDescription)"
            }
        }
    }

    private func loadParticipantsForSelectedSection() async {
        guard selectedCourseDetailSectionID == CourseDetailSection.participants.id else {
            return
        }
        guard let selectedCourseID else {
            return
        }
        guard participantsByCourseID[selectedCourseID] == nil else {
            return
        }

        let requestCourseID = selectedCourseID
        isLoadingParticipants = true
        participantErrorsByCourseID[requestCourseID] = nil
        defer {
            if selectedCourseID == requestCourseID {
                isLoadingParticipants = false
            }
        }

        do {
            let participants = try await repository.fetchCourseParticipants(courseID: requestCourseID)
            if selectedCourseID == requestCourseID {
                participantsByCourseID[requestCourseID] = participants
            }
        } catch {
            if selectedCourseID == requestCourseID {
                participantErrorsByCourseID[requestCourseID] = "Fehler beim Laden der Teilnehmer: \(error.localizedDescription)"
            }
        }
    }

    private func repositorySection(for sectionID: String) -> StudIPResourceRepository.CourseRawSection? {
        switch sectionID {
        case CourseDetailSection.forum.id:
            return .forum
        default:
            return nil
        }
    }

    private func sectionEndpointPath(for sectionID: String, courseID: String) -> String? {
        switch sectionID {
        case CourseDetailSection.files.id:
            return "/courses/\(courseID)/file-refs"
        case CourseDetailSection.chat.id:
            return "/courses/\(courseID)/blubber-threads"
        case CourseDetailSection.wiki.id:
            return "/courses/\(courseID)/wiki-pages"
        case CourseDetailSection.participants.id:
            return "/courses/\(courseID)/memberships"
        case CourseDetailSection.forum.id:
            return "/courses/\(courseID)/forum-categories"
        default:
            return nil
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fileMetadataLine(_ fileRef: StudIPResourceRepository.CourseFileRef) -> String {
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

        if let date = fileRef.changedAt ?? fileRef.createdAt {
            components.append(Self.fileDateFormatter.string(from: date))
        }

        return components.isEmpty ? "Keine Dateidetails" : components.joined(separator: " • ")
    }

    private func iconName(forMIMEType mimeType: String?) -> String {
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

    private func openFile(_ fileRef: StudIPResourceRepository.CourseFileRef) {
        guard let url = fileRef.downloadURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func chatPreviewText(_ thread: StudIPResourceRepository.CourseChatThread) -> String? {
        if let content = nonEmpty(thread.previewText) {
            if content.contains("<"), content.contains(">") {
                return plainText(fromHTML: content)
            }
            return content
        }
        return nil
    }

    private func chatMetadataLine(_ thread: StudIPResourceRepository.CourseChatThread) -> String {
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

    private func wikiPreviewText(_ page: StudIPResourceRepository.CourseWikiPage) -> String? {
        guard let content = nonEmpty(page.content) else {
            return nil
        }

        let normalized = content.replacingOccurrences(of: "<!--HTML-->", with: "")
        if normalized.contains("<"), normalized.contains(">") {
            return plainText(fromHTML: normalized)
        }
        return nonEmpty(normalized)
    }

    private func wikiMetadataLine(_ page: StudIPResourceRepository.CourseWikiPage) -> String {
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

    private func plainText(fromHTML html: String) -> String? {
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

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func participantMetadataLine(_ participant: StudIPResourceRepository.CourseParticipant) -> String {
        var components: [String] = []

        if let permission = nonEmpty(participant.permission) {
            components.append(permission.capitalized)
        }

        if let label = nonEmpty(participant.label) {
            components.append(label)
        }

        if let position = participant.position {
            components.append("Pos \(position)")
        }

        if let group = participant.group {
            components.append("Gruppe \(group)")
        }

        if let email = nonEmpty(participant.email) {
            components.append(email)
        }

        return components.isEmpty ? "Keine Zusatzinfos" : components.joined(separator: " • ")
    }

    private func openMail(for participant: StudIPResourceRepository.CourseParticipant) {
        guard let email = nonEmpty(participant.email) else {
            return
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email

        guard let url = components.url else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func participantInfoSheet(for participant: StudIPResourceRepository.CourseParticipant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(participant.displayName)
                .font(.title3.weight(.semibold))

            Divider()

            participantInfoRow("User-ID", participant.userID)
            participantInfoRow("E-Mail", nonEmpty(participant.email))
            participantInfoRow("Rolle", nonEmpty(participant.permission))
            participantInfoRow("Label", nonEmpty(participant.label))
            participantInfoRow("Position", participant.position.map(String.init))
            participantInfoRow("Gruppe", participant.group.map(String.init))
            participantInfoRow("Erstellt", nonEmpty(participant.mkdate))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 260)
    }

    @ViewBuilder
    private func participantInfoRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            if let value {
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Text("-")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let container = AppContainer()
    ContentView(
        statusController: container.statusController,
        syncScheduler: container.syncScheduler,
        semesterSelectionStore: container.semesterSelectionStore,
        repository: container.resourceRepository,
        debugWindowState: container.debugWindowState
    )
}
