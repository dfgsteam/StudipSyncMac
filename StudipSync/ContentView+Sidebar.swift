import SwiftUI

extension ContentView {
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
                HStack(spacing: 8) {
                    Text("Navigation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        goBackInSidebarNavigation()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoBackInSidebarNavigation)
                    .help("Zurück")

                    Button {
                        goForwardInSidebarNavigation()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoForwardInSidebarNavigation)
                    .help("Vor")
                }

                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(SidebarPage.allCases) { page in
                        Button {
                            navigateToSidebarPage(page)
                        } label: {
                            Label(page.title, systemImage: page.systemImage)
                                .font(.body.weight(.medium))
                                .modifier(SidebarSelectionModifier(isActive: isSelectedMenuPage(page)))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                semesterSidebar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keine Semester fuer den aktuellen Filter gefunden.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !sidebarSemesterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Tipp: Filter leeren oder 'Neu laden' verwenden.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredSemesterSidebarItems) { semester in
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectSidebarSemester(semester.id)
                        }
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

}
