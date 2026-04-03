import SwiftUI

extension ContentView {
    var startContentColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                startHeroBanner
                startStatsGrid
                startScheduleWidget(limit: 5)
                startSemesterOverviewWidget
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    var startDetailColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StudIP Dashboard")
                        .font(.title2.weight(.bold))
                    Text(startSubtitleText)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: statusController.syncState.symbolName)
                    Text(statusController.syncState.statusText)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(appHeaderFill)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    startHeroBanner
                    startStatsGrid
                    startScheduleWidget(limit: 8)
                    startSemesterOverviewWidget
                    startQuickActionsWidget
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(appDetailPanelColor)

            Divider()
            detailActions
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(appHeaderFill)
        }
    }

    var startSubtitleText: String {
        if let current = currentSemesterForDashboard {
            return "Aktives Semester: \(current.title)"
        }
        return "Uebersicht ueber Synchronisation, Semester und Termine"
    }

    var startHeroBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Uebersicht")
                    .font(.headline.weight(.semibold))
                Text("Schneller Zugriff auf Semester, Termine und Sync-Status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var currentSemesterForDashboard: SemesterDTO? {
        semesterViewModel.semesters.first(where: { $0.isCurrent == true }) ?? semesterViewModel.semesters.first
    }

    var visibleSemesterCount: Int {
        semesterViewModel.semesters.filter { $0.visible != false }.count
    }

    var cachedCourseCount: Int {
        coursesBySemesterID.values.reduce(0) { partial, items in partial + items.count }
    }

    var upcomingStartEntries: [ScheduleEntryDTO] {
        let now = Date()
        let upcoming = startScheduleEntries.filter { entry in
            guard let start = parseAPIDate(entry.start) else { return false }
            return start >= now
        }
        return upcoming.isEmpty ? startScheduleEntries : upcoming
    }

    var startStatsGrid: some View {
        let columns = [
            GridItem(.flexible(minimum: 150)),
            GridItem(.flexible(minimum: 150))
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            dashboardStatTile(
                title: "Semester",
                value: "\(semesterViewModel.semesters.count)",
                systemImage: "graduationcap"
            )
            dashboardStatTile(
                title: "Aktiv fuer Sync",
                value: "\(semesterSelectionStore.activeSemesterIDs.count)",
                systemImage: "checkmark.seal",
                footnote: "\(visibleSemesterCount) sichtbar"
            )
            dashboardStatTile(
                title: "Kurse im Cache",
                value: "\(cachedCourseCount)",
                systemImage: "books.vertical"
            )
            dashboardStatTile(
                title: "Termine heute",
                value: "\(startScheduleEntries.count)",
                systemImage: "calendar.badge.clock",
                footnote: startScheduleLoadedDate.map { "Stand: \(Self.fileDateFormatter.string(from: $0))" }
            )
        }
    }

    @ViewBuilder
    func dashboardStatTile(title: String, value: String, systemImage: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    func startScheduleWidget(limit: Int) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Heute", systemImage: "sun.max")
                        .font(.headline)
                    Spacer()
                    if isLoadingStartSchedule {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Neu laden") {
                        Task { await loadStartSchedule(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoadingStartSchedule)
                }

                if isLoadingStartSchedule, startScheduleEntries.isEmpty {
                    ProgressView("Lade Stundenplan ...")
                        .controlSize(.small)
                } else if let startScheduleError {
                    Text(startScheduleError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if upcomingStartEntries.isEmpty {
                    Text("Heute sind keine Termine im Stundenplan.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(upcomingStartEntries.prefix(limit))) { entry in
                            startScheduleRow(entry)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Tagesagenda", systemImage: "clock")
        }
    }

    var startSemesterOverviewWidget: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if semesterViewModel.semesters.isEmpty {
                    Text("Noch keine Semester geladen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(semesterViewModel.semesters.prefix(6))) { semester in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(semester.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(semesterDateRangeText(semester))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if semesterSelectionStore.isActive(semesterID: semester.id) {
                                Text("Aktiv")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Semesterueberblick", systemImage: "calendar")
        }
    }

    var startQuickActionsWidget: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Schnellaktionen")
                    .font(.headline)

                HStack(spacing: 8) {
                    Button("Semester neu laden") {
                        semesterViewModel.loadSemesters()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Erstes Semester oeffnen") {
                        if let first = semesterViewModel.semesters.first {
                            selectSidebarSemester(first.id)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(semesterViewModel.semesters.isEmpty)

                    Button("Debug oeffnen") {
                        debugWindowState.updateSelection(semesterID: selectedSemesterID, courseID: selectedCourseID)
                        openWindow(id: "debugWindow")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func semesterDateRangeText(_ semester: SemesterDTO) -> String {
        let start = semester.begin ?? semester.startOfLectures
        let end = semester.end ?? semester.endOfLectures

        switch (start, end) {
        case (.some(let start), .some(let end)):
            return "\(Self.fileDateFormatter.string(from: start)) - \(Self.fileDateFormatter.string(from: end))"
        case (.some(let start), .none):
            return "Start: \(Self.fileDateFormatter.string(from: start))"
        case (.none, .some(let end)):
            return "Ende: \(Self.fileDateFormatter.string(from: end))"
        default:
            return "Kein Zeitraum hinterlegt"
        }
    }
}
