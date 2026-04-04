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
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Kurse lokal filtern (Titel, Kursnummer, ID)", text: $courseListSearchQuery)
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

                    HStack(spacing: 8) {
                        if isLoadingCourses {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("\(filteredCoursesForList.count) von \(courses.count) Kursen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let selectedSemester {
                            Text(selectedSemester.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let errorMessage = courseOverviewErrorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label("Semesteransicht", systemImage: "books.vertical")
            }

            GroupBox {
                if filteredCoursesForList.isEmpty {
                    uiEmptyState(
                        title: courseOverviewErrorMessage == nil ? "Keine Kurse gefunden" : "Kursliste nicht verfuegbar",
                        message: courseListSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Fuer dieses Semester wurden keine Kurse gefunden."
                            : "Der aktuelle Filter liefert keine Treffer. Passe den Suchbegriff an.",
                        systemImage: "book.closed"
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredCoursesForList) { course in
                                courseRow(course, isSelected: selectedCourseID == course.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                Label("Kurse", systemImage: "list.bullet.rectangle")
            }

            Text("Status: \(courseStatusMessage)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(12)
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
            .background(appDetailPanelColor)
        }
    }

    var detailHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(detailHeaderTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(statusController.syncState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let subtitle = detailHeaderSubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(appHeaderFill)
    }

    var detailHeaderTitle: String {
        if let selectedCourse {
            return selectedCourse.title
        }
        if let selectedSemester {
            return selectedSemester.title
        }
        return "Kein Semester ausgewaehlt"
    }

    var detailHeaderSubtitle: String? {
        if let selectedCourse {
            return nonEmpty(selectedCourse.courseNumber).map { "Kursnr. \($0)" }
        }
        if let selectedSemester {
            return "Kurse: \(coursesBySemesterID[selectedSemester.id]?.count ?? courses.count)"
        }
        return nil
    }

    func semesterStatusPlaceholder(for semester: SemesterDTO) -> some View {
        let entries = semesterScheduleEventsBySemesterID[semester.id] ?? []
        let filteredEntries = eventsForCalendarDay(entries, day: selectedSemesterCalendarDay)
        let undatedCount = undatedEventsForCalendar(entries).count
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
                    DatePicker(
                        "Tag",
                        selection: $selectedSemesterCalendarDay,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)

                    Text("\(filteredEntries.count) Termine am \(Self.calendarDayOnlyFormatter.string(from: selectedSemesterCalendarDay))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if filteredEntries.isEmpty {
                        Text("Keine Termine am ausgewaehlten Tag.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(filteredEntries) { event in
                                    semesterScheduleRow(event)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 140, maxHeight: 320)
                    }

                    if undatedCount > 0 {
                        Text("\(undatedCount) Termine ohne Datum werden hier nicht im Tagesfilter gezeigt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    var selectedSemester: SemesterDTO? {
        guard let selectedSemesterID else { return nil }
        return semesterViewModel.semesters.first { $0.id == selectedSemesterID }
    }

    var selectedCourse: CourseDTO? {
        guard let selectedCourseID else { return nil }
        return courses.first { $0.id == selectedCourseID }
    }
}
