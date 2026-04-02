import SwiftUI

extension ContentView {
    var courseOverviewErrorMessage: String? {
        let trimmed = courseStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.lowercased().hasPrefix("fehler") else { return nil }
        return trimmed
    }

    var filteredCoursesForList: [CourseDTO] {
        let query = courseListSearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return courses
        }

        return courses.filter { course in
            let haystack = [
                nonEmpty(course.title),
                nonEmpty(course.subtitle),
                nonEmpty(course.courseNumber),
                nonEmpty(course.description),
                nonEmpty(course.location),
                nonEmpty(course.id)
            ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return haystack.contains(query)
        }
    }

    var coursesColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kurse im Semester")
                    .font(.headline.weight(.semibold))
                Spacer()
                if isLoadingCourses {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(filteredCoursesForList.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            HStack(spacing: 8) {
                TextField("Kurse filtern (Titel, Kursnummer, ID)", text: $courseListSearchQuery)
                    .textFieldStyle(.roundedBorder)

                if !courseListSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        courseListSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Filter leeren")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            if let errorMessage = courseOverviewErrorMessage {
                overviewMessageCard(errorMessage, isError: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
            }

            if filteredCoursesForList.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if courseOverviewErrorMessage != nil {
                        Text("Kursliste konnte nicht geladen werden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(courseListSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Keine Kurse fuer dieses Semester gefunden."
                            : "Keine Kurse fuer den aktuellen Filter gefunden."
                        )
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    if !courseListSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Tipp: Filter leeren oder Suchbegriff anpassen.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                List(filteredCoursesForList, selection: $selectedCourseID) { course in
                    courseRow(course)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Text(courseStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var detailColumn: some View {
        VStack(spacing: 0) {
            detailHeader

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            detailActions
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    var detailHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedSemester?.title ?? "Kein Semester ausgewaehlt")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(statusController.syncState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    func semesterStatusPlaceholder(for semester: SemesterDTO) -> some View {
        let entries = semesterScheduleEventsBySemesterID[semester.id] ?? []
        let errorText = semesterScheduleErrorsBySemesterID[semester.id]
        let isLoading = loadingSemesterScheduleIDs.contains(semester.id)
        let loadedAt = semesterScheduleLoadedAtBySemesterID[semester.id]

        return GroupBox("Semester-Status") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(semester.title)
                        .font(.title3.weight(.semibold))

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("Neu laden") {
                        Task {
                            await loadSemesterSchedule(for: semester, force: true)
                        }
                    }
                    .disabled(isLoading)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isLoading, entries.isEmpty {
                    ProgressView("Lade Stundenplan des Semesters ...")
                        .controlSize(.small)
                } else if entries.isEmpty {
                    Text("Keine Stundenplantermine fuer dieses Semester gefunden.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(entries) { event in
                                semesterScheduleRow(event)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 140, maxHeight: 320)
                }

                if let loadedAt {
                    Text("Stand: \(Self.fileDateFormatter.string(from: loadedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Waehle in der mittleren Spalte einen Kurs aus, um Kursdetails zu sehen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    var detailActions: some View {
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

    var selectedSemester: SemesterDTO? {
        guard let selectedSemesterID else { return nil }
        return semesterViewModel.semesters.first { $0.id == selectedSemesterID }
    }

    var selectedCourse: CourseDTO? {
        guard let selectedCourseID else { return nil }
        return courses.first { $0.id == selectedCourseID }
    }
}
