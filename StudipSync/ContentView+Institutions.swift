import SwiftUI

extension ContentView {
    var filteredInstitutions: [InstituteDTO] {
        let query = institutionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = institutions.sorted {
            instituteDisplayName($0).localizedCaseInsensitiveCompare(instituteDisplayName($1)) == .orderedAscending
        }
        guard !query.isEmpty else { return base }
        return base.filter { institute in
            let haystack = [
                instituteDisplayName(institute),
                institute.shortName,
                institute.description,
                institute.email,
                institute.address
            ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return haystack.contains(query)
        }
    }

    var selectedInstitute: InstituteDTO? {
        guard let selectedInstituteID else { return nil }
        return institutions.first { canonicalStudIPID($0.id) == canonicalStudIPID(selectedInstituteID) }
    }

    var selectedInstitutionCourseKey: String? {
        guard let selectedInstituteID, let selectedInstitutionSemesterID else { return nil }
        return "\(canonicalStudIPID(selectedInstituteID)):\(canonicalStudIPID(selectedInstitutionSemesterID))"
    }

    var filteredInstitutionCourses: [CourseDTO] {
        guard let key = selectedInstitutionCourseKey else { return [] }
        let courses = institutionCoursesByKey[key] ?? []
        let query = institutionCourseSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return courses }
        return courses.filter { course in
            let haystack = [
                course.title,
                course.subtitle,
                course.courseNumber,
                course.description,
                course.location
            ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return haystack.contains(query)
        }
    }

    var einrichtungenContentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Einrichtung suchen (Name, Kurzname, Beschreibung)", text: $institutionSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await loadInstitutions(force: true) }
                            }

                        Button("Suchen") {
                            Task { await loadInstitutions(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoadingInstitutions)

                        Button("Neu laden") {
                            Task { await loadInstitutions(force: true, resetSelection: false) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingInstitutions)

                        if !institutionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                institutionSearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Suche leeren")
                        }
                    }

                    HStack(spacing: 8) {
                        if isLoadingInstitutions {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("\(filteredInstitutions.count) Einrichtungen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let institutionsLoadedDate {
                            Text("Stand: \(Self.fileDateFormatter.string(from: institutionsLoadedDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let institutionsError, nonEmpty(institutionsError) != nil {
                        Text(institutionsError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label("Einrichtungssuche", systemImage: "building.2.crop.circle")
            }

            GroupBox {
                if filteredInstitutions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(institutionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "Noch keine Einrichtungen geladen. Starte eine Suche oder druecke 'Neu laden'."
                             : "Keine Einrichtungen fuer den aktuellen Filter gefunden."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        if !institutionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Tipp: Suchbegriff anpassen oder leeren.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredInstitutions) { institute in
                                instituteSearchRow(institute)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                Label("Einrichtungen", systemImage: "building.columns")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .task {
            await ensureInstitutionInitialLoad()
        }
    }

    var einrichtungenDetailColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Einrichtungen")
                        .font(.title2.weight(.bold))
                    Text("Einrichtung waehlen und danach Veranstaltungen pro Semester laden.")
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button("Neu laden") {
                    Task { await loadCoursesForSelectedInstitutionSemester(force: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedInstitute == nil || selectedInstitutionSemesterID == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let institute = selectedInstitute {
                        GroupBox {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                institutionInfoRow("Name", instituteDisplayName(institute))
                                institutionInfoRow("Kurzname", nonEmpty(institute.shortName))
                                institutionInfoRow("E-Mail", nonEmpty(institute.email))
                                institutionInfoRow("Telefon", nonEmpty(institute.phone))
                                institutionInfoRow("Adresse", nonEmpty(institute.address))
                                institutionInfoRow("Homepage", nonEmpty(institute.homepage))
                                institutionInfoRow("Erstellt", formattedAPIDate(institute.mkdate))
                                institutionInfoRow("Aktualisiert", formattedAPIDate(institute.chdate))
                                institutionInfoRow("ID", institute.id)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if let description = nonEmpty(institute.description) {
                                Divider()
                                Text(description)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } label: {
                            Label("Einrichtungsprofil", systemImage: "building.columns.fill")
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Semester", selection: $selectedInstitutionSemesterID) {
                                    Text("Semester waehlen").tag(Optional<String>.none)
                                    ForEach(semesterViewModel.semesters) { semester in
                                        Text(semester.title).tag(Optional(semester.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()

                                TextField("Veranstaltung in Ergebnisliste suchen", text: $institutionCourseSearchQuery)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Veranstaltungen nach Semester", systemImage: "book.closed")
                        }

                        GroupBox {
                            if let key = selectedInstitutionCourseKey,
                               loadingInstitutionCourseKeys.contains(key),
                               (institutionCoursesByKey[key] ?? []).isEmpty {
                                ProgressView("Lade Veranstaltungen ...")
                                    .controlSize(.small)
                            } else {
                                if let key = selectedInstitutionCourseKey,
                                   let error = institutionCourseErrorsByKey[key],
                                   nonEmpty(error) != nil {
                                    overviewMessageCard(error, isError: true)
                                }

                                Text("\(filteredInstitutionCourses.count) Veranstaltungen")
                                    .font(.subheadline.weight(.semibold))

                                if filteredInstitutionCourses.isEmpty {
                                    if let key = selectedInstitutionCourseKey,
                                       let error = nonEmpty(institutionCourseErrorsByKey[key]),
                                       error.lowercased().hasPrefix("fehler") {
                                        Text("Die Veranstaltungsuebersicht konnte nicht geladen werden.")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Keine Veranstaltungen fuer diese Einrichtung in dem Semester gefunden.")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    ForEach(filteredInstitutionCourses) { course in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(course.title)
                                                .font(.callout.weight(.medium))
                                                .lineLimit(2)
                                            Text(institutionCourseMetadataLine(course))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        } label: {
                            Label("Veranstaltungsergebnis", systemImage: "list.bullet.rectangle")
                        }
                    } else {
                        Text("Waehle links eine Einrichtung aus.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .task(id: selectedInstitutionCourseKey ?? "none") {
                await loadCoursesForSelectedInstitutionSemester(force: false)
            }
            .task(id: semesterIDsSignature) {
                if selectedInstitutionSemesterID == nil {
                    selectedInstitutionSemesterID = semesterViewModel.semesters.first?.id
                }
            }

            Divider()
            detailActions
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    func instituteSearchRow(_ institute: InstituteDTO) -> some View {
        let instituteID = canonicalStudIPID(institute.id)
        let isSelected = canonicalStudIPID(selectedInstituteID ?? "") == instituteID

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "building.columns")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(instituteDisplayName(institute))
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(instituteSecondaryLine(institute))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("ID: \(institute.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedInstituteID = instituteID
            if selectedInstitutionSemesterID == nil {
                selectedInstitutionSemesterID = semesterViewModel.semesters.first?.id
            }
        }
    }

    @ViewBuilder
    func institutionInfoRow(_ label: String, _ value: String?) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value ?? "—")
                .font(.callout)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func ensureInstitutionInitialLoad() async {
        guard selectedPage == .einrichtungen, selectedSemesterID == nil else { return }
        if institutions.isEmpty {
            await loadInstitutions(force: false)
        }
        if selectedInstitutionSemesterID == nil {
            selectedInstitutionSemesterID = semesterViewModel.semesters.first?.id
        }
    }

    func loadInstitutions(force: Bool, resetSelection: Bool = false) async {
        guard selectedPage == .einrichtungen, selectedSemesterID == nil else { return }
        if isLoadingInstitutions { return }
        if !force, !institutions.isEmpty { return }

        isLoadingInstitutions = true
        institutionsError = nil
        defer { isLoadingInstitutions = false }

        do {
            let query = institutionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let search = query.isEmpty ? nil : query
            let fetched = try await repository.fetchInstitutes(offset: 0, limit: 1000, search: search)
            institutions = fetched.sorted {
                instituteDisplayName($0).localizedCaseInsensitiveCompare(instituteDisplayName($1)) == .orderedAscending
            }
            institutionsLoadedDate = Date()

            if resetSelection {
                selectedInstituteID = nil
            }
            if selectedInstituteID == nil || !institutions.contains(where: { canonicalStudIPID($0.id) == canonicalStudIPID(selectedInstituteID ?? "") }) {
                selectedInstituteID = institutions.first?.id
            }
        } catch {
            institutionsError = "Fehler beim Laden der Einrichtungen: \(error.localizedDescription)"
        }
    }

    func loadCoursesForSelectedInstitutionSemester(force: Bool) async {
        guard selectedPage == .einrichtungen, selectedSemesterID == nil else { return }
        guard let instituteID = selectedInstituteID, let semesterID = selectedInstitutionSemesterID else { return }

        let key = "\(canonicalStudIPID(instituteID)):\(canonicalStudIPID(semesterID))"
        if loadingInstitutionCourseKeys.contains(key) { return }
        if !force, institutionCoursesByKey[key] != nil { return }

        loadingInstitutionCourseKeys.insert(key)
        institutionCourseErrorsByKey[key] = nil
        defer { loadingInstitutionCourseKeys.remove(key) }

        do {
            let fetched = try await repository.fetchInstituteCourses(
                instituteID: instituteID,
                semesterID: semesterID,
                offset: 0,
                limit: 1000
            )
            let sorted = fetched.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            institutionCoursesByKey[key] = sorted
        } catch {
            institutionCourseErrorsByKey[key] = "Fehler beim Laden der Veranstaltungen: \(error.localizedDescription)"
            institutionCoursesByKey[key] = []
        }
    }

    func instituteDisplayName(_ institute: InstituteDTO) -> String {
        institute.displayName
    }

    func instituteSecondaryLine(_ institute: InstituteDTO) -> String {
        let parts = [
            nonEmpty(institute.shortName),
            nonEmpty(institute.email),
            nonEmpty(institute.phone),
            nonEmpty(institute.address)
        ]
            .compactMap { $0 }
        return parts.isEmpty ? "Keine Zusatzinfos" : parts.joined(separator: " • ")
    }

    func institutionCourseMetadataLine(_ course: CourseDTO) -> String {
        var parts: [String] = []
        if let number = nonEmpty(course.courseNumber) {
            parts.append("Kursnr. \(number)")
        }
        if let subtitle = nonEmpty(course.subtitle) {
            parts.append(subtitle)
        }
        if let location = nonEmpty(course.location) {
            parts.append(location)
        }
        return parts.isEmpty ? course.id : parts.joined(separator: " • ")
    }
}
