import SwiftUI

extension ContentView {
    private var courseSearchFieldsForAPI: String {
        "title_lecturer_number"
    }

    var veranstaltungenContentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Veranstaltung suchen (Name oder ID)", text: $courseCatalogQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await loadCatalogCourses(force: true) }
                            }

                        Button("Suchen") {
                            Task { await loadCatalogCourses(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoadingCatalogCourses)

                        if hasSearchQuery(courseCatalogQuery) {
                            Button {
                                courseCatalogQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Suche leeren")
                        }
                    }

                    Picker("Semester", selection: $selectedCatalogSemesterID) {
                        Text("Alle Semester").tag(Optional<String>.none)
                        ForEach(semesterViewModel.semesters) { semester in
                            Text(semester.title).tag(Optional(semester.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    HStack(spacing: 8) {
                        if isLoadingCatalogCourses {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("\(catalogCourses.count) Veranstaltungen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let catalogCoursesLoadedDate {
                            Text("Stand: \(Self.fileDateFormatter.string(from: catalogCoursesLoadedDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Label("Veranstaltungssuche", systemImage: "magnifyingglass")
            }

            GroupBox {
                if let message = nonEmpty(catalogCoursesError) {
                    overviewMessageCard(message, isError: message.lowercased().hasPrefix("fehler"))
                }

                if catalogCourses.isEmpty {
                    uiEmptyState(
                        title: nonEmpty(catalogCoursesError)?.lowercased().hasPrefix("fehler") == true
                            ? "Trefferliste nicht verfuegbar"
                            : "Keine Veranstaltungen",
                        message: !hasSearchQuery(courseCatalogQuery)
                            ? "Starte eine Suche, um Veranstaltungen vom Server zu laden."
                            : "Keine Treffer fuer den aktuellen Filter. Passe den Suchbegriff an.",
                        systemImage: "book.closed"
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(catalogCourses) { course in
                                katalogCourseRow(course)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                Label("Trefferliste", systemImage: "list.bullet.rectangle")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .task {
            await ensureCatalogInitialLoad()
        }
        .task(id: selectedCatalogSemesterID ?? "all") {
            await loadCatalogCourses(force: false)
        }
        .task(id: selectedCatalogCourseID ?? "none") {
            await loadSelectedCatalogCourseDetailIfNeeded()
        }
    }

    var veranstaltungenDetailColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Veranstaltungen")
                        .font(.title2.weight(.bold))
                    Text("Suche Veranstaltungen, sieh Detailinfos und schreibe dich ein.")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(appHeaderFill)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let course = selectedCatalogCourseDetail ?? selectedCatalogCourse {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(course.title)
                                            .font(.title3.weight(.semibold))
                                        if let subtitle = nonEmpty(course.subtitle) {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    enrollmentBadge(for: course.id)
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        Task { await enrollInCourse(courseID: course.id) }
                                    } label: {
                                        Label(isEnrolledInCatalogCourse(course.id) ? "Bereits eingeschrieben" : "Einschreiben", systemImage: "person.badge.plus")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isEnrolledInCatalogCourse(course.id) || enrollmentInFlightCourseIDs.contains(course.id))

                                    if enrollmentInFlightCourseIDs.contains(course.id) {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }

                                if let enrollmentError = enrollmentErrorByCourseID[course.id], nonEmpty(enrollmentError) != nil {
                                    Text(enrollmentError)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Kursprofil", systemImage: "book.closed")
                        }

                        GroupBox {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                catalogInfoRow("ID", course.id)
                                catalogInfoRow("Titel", nonEmpty(course.title))
                                catalogInfoRow("Untertitel", nonEmpty(course.subtitle))
                                catalogInfoRow("Kursnummer", nonEmpty(course.courseNumber))
                                catalogInfoRow("Kurstyp", course.courseType.map(String.init))
                                catalogInfoRow("Kurstyp-ID", nonEmpty(course.courseTypeID))
                                catalogInfoRow("Semester-ID", nonEmpty(course.semesterID))
                                catalogInfoRow("Startsemester", nonEmpty(course.startSemesterRef))
                                catalogInfoRow("Endsemester", nonEmpty(course.endSemesterRef))
                                catalogInfoRow("Institut-ID", nonEmpty(course.instituteID))
                                catalogInfoRow("Sem-Klasse", nonEmpty(course.semClassID))
                                catalogInfoRow("Sem-Typ", nonEmpty(course.semTypeID))
                                catalogInfoRow("Ort", nonEmpty(course.location))
                                catalogInfoRow("Zusatz", nonEmpty(course.miscellaneous))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Metadaten", systemImage: "square.text.square")
                        }

                        if let description = nonEmpty(course.description) {
                            GroupBox {
                                Text(description)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                Label("Beschreibung", systemImage: "text.alignleft")
                            }
                        }
                    } else if isLoadingCatalogCourseDetail {
                        ProgressView("Lade Kursdetails ...")
                            .controlSize(.small)
                    } else if let selectedCatalogCourseDetailError, nonEmpty(selectedCatalogCourseDetailError) != nil {
                        Text(selectedCatalogCourseDetailError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        uiEmptyState(
                            title: "Keine Veranstaltung ausgewaehlt",
                            message: "Waehle links eine Veranstaltung aus, um Details und Einschreibung zu sehen.",
                            systemImage: "book.closed.circle"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(appDetailPanelColor)
        }
    }

    var selectedCatalogCourse: CourseDTO? {
        guard let selectedCatalogCourseID else { return nil }
        return catalogCourses.first { canonicalStudIPID($0.id) == canonicalStudIPID(selectedCatalogCourseID) }
    }

    func katalogCourseRow(_ course: CourseDTO) -> some View {
        let isSelected = canonicalStudIPID(selectedCatalogCourseID ?? "") == canonicalStudIPID(course.id)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "book")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(course.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(catalogCourseListLine(course))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("ID: \(course.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEnrolledInCatalogCourse(course.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Bereits eingeschrieben")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCatalogCourseID = course.id
        }
    }

    @ViewBuilder
    func enrollmentBadge(for courseID: String) -> some View {
        if isEnrolledInCatalogCourse(courseID) {
            Label("Eingeschrieben", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("Nicht eingeschrieben", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func catalogInfoRow(_ label: String, _ value: String?) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value ?? "—")
                .font(.callout)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func ensureCatalogInitialLoad() async {
        guard selectedPage == .veranstaltungen, selectedSemesterID == nil else { return }

        if selectedCatalogSemesterID == nil {
            selectedCatalogSemesterID = semesterViewModel.semesters.first?.id
        }

        await loadEnrolledCourses(force: false)
        await loadCatalogCourses(force: false)
    }

    func loadCatalogCourses(force: Bool) async {
        guard selectedPage == .veranstaltungen, selectedSemesterID == nil else { return }
        if isLoadingCatalogCourses { return }

        let search = normalizedSearchQuery(courseCatalogQuery)
        let requestKey = catalogCourseRequestKey(semesterID: selectedCatalogSemesterID, query: search)
        if !force, requestKey == lastCatalogLoadRequestKey {
            return
        }

        isLoadingCatalogCourses = true
        catalogCoursesError = nil
        defer { isLoadingCatalogCourses = false }

        do {
            let fetched = try await repository.fetchCoursesCollection(
                semesterID: selectedCatalogSemesterID,
                userID: nil,
                search: search,
                searchFields: courseSearchFieldsForAPI,
                offset: 0,
                limit: 1000
            )
            let locallyFiltered = applyCatalogFilters(
                courses: fetched,
                semesterID: selectedCatalogSemesterID,
                query: search
            )
            catalogCourses = sortCoursesForDisplay(locallyFiltered)
            selectedCatalogCourseID = catalogCourses.first?.id
            selectedCatalogCourseDetail = nil
            selectedCatalogCourseDetailError = nil
            catalogCoursesLoadedDate = Date()
            lastCatalogLoadRequestKey = requestKey
        } catch {
            let debugCURL = await repository.debugCoursesSearchCURL(
                semesterID: selectedCatalogSemesterID,
                userID: nil,
                search: search,
                searchFields: courseSearchFieldsForAPI,
                offset: 0,
                limit: 1000
            )
            recordSearchFailure(context: "Veranstaltungssuche", query: search, curl: debugCURL, error: error)

            if let fallback = try? await repository.fetchCoursesCollection(
                semesterID: selectedCatalogSemesterID,
                userID: nil,
                search: nil,
                offset: 0,
                limit: 1000
            ) {
                let localFiltered = applyCatalogFilters(
                    courses: fallback,
                    semesterID: selectedCatalogSemesterID,
                    query: search
                )
                catalogCourses = sortCoursesForDisplay(localFiltered)
                selectedCatalogCourseID = catalogCourses.first?.id
                selectedCatalogCourseDetail = nil
                selectedCatalogCourseDetailError = nil
                catalogCoursesLoadedDate = Date()
                catalogCoursesError = "Server-Suche nicht verfuegbar (\(error.localizedDescription)). Lokal gefiltert."
                lastCatalogLoadRequestKey = requestKey
            } else {
                catalogCourses = []
                selectedCatalogCourseID = nil
                catalogCoursesError = "Fehler beim Laden der Veranstaltungen: \(error.localizedDescription)"
            }
        }
    }

    func applyCatalogFilters(courses: [CourseDTO], semesterID: String?, query: String?) -> [CourseDTO] {
        let normalizedSemesterID = semesterID.map(canonicalStudIPID)

        return courses.filter { course in
            if let normalizedSemesterID, !course.matches(semesterID: normalizedSemesterID) {
                return false
            }

            if hasSearchQuery(query) {
                return fieldMatchesSearchQuery(query, fields: [
                    course.id,
                    course.title,
                    course.subtitle,
                    course.courseNumber,
                    course.description,
                    course.location
                ])
            }

            return true
        }
    }

    func catalogCourseRequestKey(semesterID: String?, query: String?) -> String {
        let semesterPart = semesterID.map(canonicalStudIPID) ?? "all"
        let queryPart = normalizedSearchQuery(query)?.lowercased() ?? ""
        return "\(semesterPart)|\(queryPart)"
    }

    func loadSelectedCatalogCourseDetailIfNeeded() async {
        guard selectedPage == .veranstaltungen, selectedSemesterID == nil else { return }
        guard selectedCatalogCourseID != nil else {
            selectedCatalogCourseDetail = nil
            selectedCatalogCourseDetailError = nil
            return
        }
        await loadSelectedCatalogCourseDetail(force: false)
    }

    func loadSelectedCatalogCourseDetail(force: Bool) async {
        guard selectedPage == .veranstaltungen, selectedSemesterID == nil else { return }
        guard let selectedCatalogCourseID else { return }
        if isLoadingCatalogCourseDetail { return }
        if !force, selectedCatalogCourseDetail?.id == selectedCatalogCourseID { return }

        isLoadingCatalogCourseDetail = true
        selectedCatalogCourseDetailError = nil
        defer { isLoadingCatalogCourseDetail = false }

        do {
            selectedCatalogCourseDetail = try await repository.fetchCourse(id: selectedCatalogCourseID)
        } catch {
            selectedCatalogCourseDetail = selectedCatalogCourse
            selectedCatalogCourseDetailError = "Fehler beim Laden der Kursdetails: \(error.localizedDescription)"
        }
    }

    func loadEnrolledCourses(force: Bool) async {
        guard selectedPage == .veranstaltungen, selectedSemesterID == nil else { return }
        if isLoadingEnrolledCourses { return }
        if !force, !enrolledCourseIDs.isEmpty { return }

        isLoadingEnrolledCourses = true
        defer { isLoadingEnrolledCourses = false }

        do {
            let me = try await repository.fetchMe()
            let myCourses = try await repository.fetchCoursesForUser(
                userID: me.id,
                semesterID: nil,
                offset: 0,
                limit: 2000
            )
            enrolledCourseIDs = Set(myCourses.map { canonicalStudIPID($0.id) })
        } catch {
            // fail silently: enrollment state can be unknown for some instances
        }
    }

    func isEnrolledInCatalogCourse(_ courseID: String) -> Bool {
        enrolledCourseIDs.contains(canonicalStudIPID(courseID))
    }

    func enrollInCourse(courseID: String) async {
        let normalizedCourseID = canonicalStudIPID(courseID)
        guard !enrollmentInFlightCourseIDs.contains(normalizedCourseID) else { return }
        if isEnrolledInCatalogCourse(normalizedCourseID) { return }

        enrollmentInFlightCourseIDs.insert(normalizedCourseID)
        enrollmentErrorByCourseID[normalizedCourseID] = nil
        defer { enrollmentInFlightCourseIDs.remove(normalizedCourseID) }

        do {
            try await repository.enrollCurrentUser(courseID: normalizedCourseID)
            enrolledCourseIDs.insert(normalizedCourseID)
            await loadEnrolledCourses(force: true)
        } catch {
            enrollmentErrorByCourseID[normalizedCourseID] = "Einschreiben fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func catalogCourseListLine(_ course: CourseDTO) -> String {
        var parts: [String] = []
        if let number = nonEmpty(course.courseNumber) {
            parts.append("Kursnr. \(number)")
        }
        if let subtitle = nonEmpty(course.subtitle) {
            parts.append(subtitle)
        }
        if let semesterID = nonEmpty(course.semesterID) {
            parts.append("Semester: \(semesterID)")
        }
        return parts.isEmpty ? "Keine Zusatzinfos" : parts.joined(separator: " • ")
    }
}
