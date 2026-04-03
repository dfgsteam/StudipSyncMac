import SwiftUI

extension ContentView {
    var usesSingleDetailLayoutForSelectedPage: Bool {
        selectedSemesterID == nil && (selectedPage == .start || selectedPage == .profil)
    }

    var selectedPage: SidebarPage {
        selectedSidebarPage ?? .start
    }

    var filteredSemesterSidebarItems: [SemesterDTO] {
        let query = sidebarSemesterSearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return semesterViewModel.semesters
        }

        return semesterViewModel.semesters.filter { semester in
            semester.title.lowercased().contains(query)
                || semester.id.lowercased().contains(query)
        }
    }

    var pagesSidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("StudIP Sync")
                        .font(.headline.weight(.semibold))
                    HStack(spacing: 6) {
                        Image(systemName: statusController.syncState.symbolName)
                        Text(statusController.syncState.statusText)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.045))
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(appBorderColor.opacity(0.45), lineWidth: 1)
                        .allowsHitTesting(false)
                }

                HStack(spacing: 8) {
                    Text("Navigation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(SidebarPage.allCases) { page in
                        Button {
                            navigateToSidebarPage(page)
                        } label: {
                            Label(page.title, systemImage: page.systemImage)
                                .font(.body.weight(.medium))
                                .modifier(SidebarSelectionModifier(isActive: isSelectedMenuPage(page)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }

                Divider()

                semesterSidebar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .overlay {
            Rectangle()
                .fill(Color.accentColor.opacity(0.03))
                .allowsHitTesting(false)
        }
    }

    var contentForSelectedPage: some View {
        Group {
            if selectedSemesterID != nil {
                coursesColumn
            } else {
                switch selectedPage {
                case .start:
                    startContentColumn
                case .profil:
                    profilContentColumn
                case .benutzer:
                    benutzerContentColumn
                case .veranstaltungen:
                    veranstaltungenContentColumn
                case .einrichtungen:
                    einrichtungenContentColumn
                case .platzhalter:
                    platzhalterContentColumn
                }
            }
        }
    }

    var detailForSelectedPage: some View {
        Group {
            if selectedSemesterID != nil {
                detailColumn
            } else {
                switch selectedPage {
                case .start:
                    startDetailColumn
                case .profil:
                    profilDetailColumn
                case .benutzer:
                    benutzerDetailColumn
                case .veranstaltungen:
                    veranstaltungenDetailColumn
                case .einrichtungen:
                    einrichtungenDetailColumn
                case .platzhalter:
                    platzhalterDetailColumn
                }
            }
        }
    }

    var semesterSidebar: some View {
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

            HStack(spacing: 8) {
                TextField("Semester suchen (Titel oder ID)", text: $sidebarSemesterSearchQuery)
                    .textFieldStyle(.roundedBorder)

                if !sidebarSemesterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        sidebarSemesterSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Filter leeren")
                }
            }

            if filteredSemesterSidebarItems.isEmpty {
                uiEmptyState(
                    title: "Keine Semester gefunden",
                    message: sidebarSemesterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Lade die Semester neu, um Daten abzurufen."
                        : "Passe den Filter an oder leere die Suche.",
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredSemesterSidebarItems) { semester in
                        Button {
                            selectSidebarSemester(semester.id)
                        } label: {
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
                            .modifier(SidebarSelectionModifier(isActive: isSelectedSemester(semester.id)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(semesterSelectionStore.isActive(semesterID: semester.id) ? "Fuer Sync deaktivieren" : "Fuer Sync aktivieren") {
                                semesterSelectionStore.setActive(!semesterSelectionStore.isActive(semesterID: semester.id), semesterID: semester.id)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(filteredSemesterSidebarItems.count) von \(semesterViewModel.semesters.count) Semestern")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(semesterViewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.04))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appBorderColor.opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var platzhalterContentColumn: some View {
        staticMenuContentColumn(
            title: "Platzhalter",
            subtitle: "Diese Seite ist ein Platzhalter vor dem Veranstaltungsbereich."
        )
    }

    var platzhalterDetailColumn: some View {
        staticMenuDetailColumn(
            title: "Platzhalter",
            subtitle: "Statische Testseite: Detailbereich"
        )
    }

    func staticMenuContentColumn(title: String, subtitle: String) -> some View {
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

    func staticMenuDetailColumn(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox("Testdetails") {
                Text("Statischer Detailbereich fuer UI-Tests.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(24)
    }

}
