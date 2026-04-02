import AppKit
import SwiftUI

extension ContentView {
    var canNavigateUserBackward: Bool {
        userNavigationHistoryIndex > 0
            && userNavigationHistoryIndex < userNavigationHistory.count
    }

    var canNavigateUserForward: Bool {
        userNavigationHistoryIndex >= 0
            && userNavigationHistoryIndex < userNavigationHistory.count - 1
    }

    func selectUserForDetail(_ userID: String, addToHistory: Bool = true) {
        let normalizedID = canonicalStudIPID(userID)
        guard !normalizedID.isEmpty else { return }

        if addToHistory {
            if userNavigationHistoryIndex >= 0,
               userNavigationHistoryIndex < userNavigationHistory.count,
               userNavigationHistory[userNavigationHistoryIndex] == normalizedID {
                selectedUserID = normalizedID
                return
            }

            var history = userNavigationHistory
            if userNavigationHistoryIndex >= 0,
               userNavigationHistoryIndex < history.count - 1 {
                history.removeSubrange((userNavigationHistoryIndex + 1)..<history.count)
            }

            history.append(normalizedID)
            userNavigationHistory = history
            userNavigationHistoryIndex = history.count - 1
        }

        selectedUserID = normalizedID
    }

    func navigateUserBackward() {
        guard canNavigateUserBackward else { return }
        userNavigationHistoryIndex -= 1
        selectedUserID = userNavigationHistory[userNavigationHistoryIndex]
    }

    func navigateUserForward() {
        guard canNavigateUserForward else { return }
        userNavigationHistoryIndex += 1
        selectedUserID = userNavigationHistory[userNavigationHistoryIndex]
    }

    var rememberedUserIDs: [String] {
        let parts = rememberedUserIDsCSV
            .split(separator: ",")
            .map { canonicalStudIPID(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }

        var seen = Set<String>()
        var ordered: [String] = []
        ordered.reserveCapacity(parts.count)

        for id in parts where !id.isEmpty {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    func isRememberedUser(id: String) -> Bool {
        rememberedUserIDs.contains(canonicalStudIPID(id))
    }

    func persistRememberedUserIDs(_ ids: [String]) {
        rememberedUserIDsCSV = ids.joined(separator: ",")
    }

    func toggleRememberedUser(_ user: UserDTO) {
        let userID = canonicalStudIPID(user.id)
        var ids = rememberedUserIDs
        if let index = ids.firstIndex(of: userID) {
            ids.remove(at: index)
            rememberedUsersByID[userID] = nil
        } else {
            ids.insert(userID, at: 0)
            rememberedUsersByID[userID] = user
        }
        persistRememberedUserIDs(ids)
    }

    var benutzerContentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Benutzer suchen (Name, Username, E-Mail)", text: $userSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await runUserSearch(force: true) }
                            }

                        Button("Suchen") {
                            Task { await runUserSearch(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoadingUserSearch)

                        if !userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                userSearchQuery = ""
                                userSearchResults = []
                                userSearchError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Suche leeren")
                        }
                    }

                    HStack(spacing: 8) {
                        if isLoadingUserSearch {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("\(userSearchResults.count) Treffer")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let loaded = lastUserSearchDate {
                            Text("Stand: \(Self.fileDateFormatter.string(from: loaded))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let userSearchError, nonEmpty(userSearchError) != nil {
                        Text(userSearchError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label("Benutzersuche", systemImage: "magnifyingglass")
            }

            if !rememberedUserIDs.isEmpty {
                GroupBox {
                    if isLoadingRememberedUsers, rememberedUsersByID.isEmpty {
                        ProgressView("Lade gemerkte Benutzer ...")
                            .controlSize(.small)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(rememberedUserIDs, id: \.self) { userID in
                                    rememberedUserRow(userID: userID)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                    }
                } label: {
                    Label("Gemerkt (\(rememberedUserIDs.count))", systemImage: "bookmark.fill")
                }
            }

            GroupBox {
                if userSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "Noch keine Treffer. Suche oben nach einem Benutzer."
                             : "Keine Benutzer fuer den aktuellen Suchbegriff gefunden."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        if !userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Tipp: Mindestens 3 Zeichen verwenden oder den Begriff anpassen.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(userSearchResults) { user in
                                userSearchResultRow(user)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                Label("Trefferliste", systemImage: "person.3")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .task {
            await ensureBenutzerInitialLoad()
        }
        .task(id: rememberedUserIDsCSV) {
            await loadRememberedUsers()
        }
        .task(id: selectedUserID ?? "none") {
            await loadSelectedUserDetailsIfNeeded()
        }
    }

    var benutzerDetailColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Benutzerprofil")
                        .font(.title2.weight(.bold))
                    Text("Suche nach Benutzern, markiere Favoriten und sieh Detaildaten.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        navigateUserBackward()
                    } label: {
                        Label("Zurueck", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canNavigateUserBackward)

                    Button {
                        navigateUserForward()
                    } label: {
                        Label("Vor", systemImage: "chevron.forward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canNavigateUserForward)

                    if let selectedUserID {
                        Button("Neu laden") {
                            Task { await ensureUserDetailsLoaded(userID: selectedUserID, force: true) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedUserID {
                        userDetailView(userID: selectedUserID)
                    } else {
                        Text("Waehle einen Benutzer aus der Treffer- oder Merkliste aus.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            detailActions
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    @ViewBuilder
    func rememberedUserRow(userID: String) -> some View {
        let user = rememberedUsersByID[userID] ?? userDetailByID[userID]
        let isSelected = selectedUserID == userID

        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.yellow)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.map(userDisplayName) ?? "User \(userID)")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(userID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                if let user {
                    toggleRememberedUser(user)
                } else {
                    persistRememberedUserIDs(rememberedUserIDs.filter { $0 != userID })
                }
            } label: {
                Image(systemName: "bookmark.slash")
            }
            .buttonStyle(.borderless)
            .help("Aus Merkliste entfernen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            selectUserForDetail(userID)
        }
    }

    func userSearchResultRow(_ user: UserDTO) -> some View {
        let isSelected = selectedUserID == user.id
        let remembered = isRememberedUser(id: user.id)

        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .overlay {
                    Text(userInitials(user))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(userDisplayName(user))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(userSecondaryLine(user))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("ID: \(user.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                toggleRememberedUser(user)
            } label: {
                Image(systemName: remembered ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(remembered ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(remembered ? "Nicht mehr merken" : "Benutzer merken")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            selectUserForDetail(user.id)
        }
    }

    @ViewBuilder
    func userDetailView(userID: String) -> some View {
        let normalizedUserID = canonicalStudIPID(userID)
        let user = userDetailByID[normalizedUserID]
            ?? userSearchResults.first(where: { $0.id == normalizedUserID })
            ?? rememberedUsersByID[normalizedUserID]
        let isLoading = loadingUserDetailIDs.contains(normalizedUserID)
        let detailError = userDetailErrorByID[normalizedUserID]
        let extrasError = userExtrasErrorByID[normalizedUserID]

        if isLoading, user == nil {
            ProgressView("Lade Benutzerdaten ...")
                .controlSize(.small)
        } else if let detailError, user == nil {
            Text(detailError)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let user {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(userDisplayName(user))
                                .font(.title3.weight(.semibold))
                            Text(userSecondaryLine(user))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isRememberedUser(id: user.id) {
                            Label("Gemerkt", systemImage: "bookmark.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            toggleRememberedUser(user)
                        } label: {
                            Label(isRememberedUser(id: user.id) ? "Nicht mehr merken" : "Merken", systemImage: isRememberedUser(id: user.id) ? "bookmark.slash" : "bookmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            openMailAddress(user.email)
                        } label: {
                            Label("Mail", systemImage: "envelope")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(nonEmpty(user.email) == nil)

                        Button {
                            openHomepage(user.homepage)
                        } label: {
                            Label("Homepage", systemImage: "link")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(nonEmpty(user.homepage) == nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Profil", systemImage: "person.crop.circle")
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    userInfoRow("ID", user.id)
                    userInfoRow("Username", nonEmpty(user.username))
                    userInfoRow("Display Name", nonEmpty(user.displayName))
                    userInfoRow("Full Name", nonEmpty(user.fullName))
                    userInfoRow("Titel (vor)", nonEmpty(user.namePrefix))
                    userInfoRow("Vorname", nonEmpty(user.givenName))
                    userInfoRow("Nachname", nonEmpty(user.familyName))
                    userInfoRow("Titel (nach)", nonEmpty(user.nameSuffix))
                    userInfoRow("Rolle", nonEmpty(user.permission))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Basisdaten", systemImage: "text.below.photo")
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    userInfoRow("Auth-Plugin", nonEmpty(user.authPlugin))
                    userInfoRow("Sichtbar", userBooleanText(user.visible))
                    userInfoRow("Gesperrt", userBooleanText(user.locked))
                    userInfoRow("Sperrhinweis", nonEmpty(user.lockComment))
                    userInfoRow("Matrikelnummer", nonEmpty(user.matriculationNumber))
                    userInfoRow("Geschlecht", nonEmpty(user.gender))
                    userInfoRow("Sprache", nonEmpty(user.preferredLanguage))
                    userInfoRow("Erstellt", formattedAPIDate(user.mkdate))
                    userInfoRow("Aktualisiert", formattedAPIDate(user.chdate))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Account", systemImage: "person.text.rectangle")
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    userInfoRow("E-Mail", nonEmpty(user.email))
                    userInfoRow("Telefon", nonEmpty(user.phone))
                    userInfoRow("Mobil", nonEmpty(user.cellphone))
                    userInfoRow("Adresse", nonEmpty(user.address))
                    userInfoRow("Homepage", nonEmpty(user.homepage))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Kontakt", systemImage: "phone")
            }

            if nonEmpty(user.hobby) != nil || nonEmpty(user.cv) != nil || nonEmpty(user.publication) != nil || nonEmpty(user.focus) != nil || nonEmpty(user.motto) != nil {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        userLongTextRow("Hobby", user.hobby)
                        userLongTextRow("Schwerpunkte", user.focus)
                        userLongTextRow("Motto", user.motto)
                        userLongTextRow("Publikationen", user.publication)
                        userLongTextRow("Lebenslauf", user.cv)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Profiltexte", systemImage: "doc.text")
                }
            }

            GroupBox {
                let memberships = userInstituteMembershipsByID[normalizedUserID] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(memberships.count) Institute-Mitgliedschaften")
                        .font(.subheadline.weight(.semibold))
                    if memberships.isEmpty {
                        Text("Keine Institute-Mitgliedschaften gefunden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(memberships.prefix(25)) { membership in
                            Text("• \(membership.id)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        if memberships.count > 25 {
                            Text("… und \(memberships.count - 25) weitere")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Institute", systemImage: "building.columns")
            }

            GroupBox {
                let courses = userCoursesByID[normalizedUserID] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(courses.count) Veranstaltungen")
                        .font(.subheadline.weight(.semibold))
                    if courses.isEmpty {
                        Text("Keine Veranstaltungen gefunden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(courses.prefix(30)) { course in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(nonEmpty(course.title) ?? "Kurs \(course.id)")
                                    .font(.callout.weight(.medium))
                                    .lineLimit(2)
                                Text(courseUserMetadataLine(course))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if courses.count > 30 {
                            Text("… und \(courses.count - 30) weitere")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Veranstaltungen", systemImage: "book.closed")
            }

            GroupBox {
                let events = userUpcomingEventsByID[normalizedUserID] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(events.count) naechste Termine")
                        .font(.subheadline.weight(.semibold))
                    if events.isEmpty {
                        Text("Keine anstehenden Termine gefunden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events.prefix(20)) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(nonEmpty(event.title) ?? "Termin \(event.id)")
                                    .font(.callout.weight(.medium))
                                    .lineLimit(2)
                                Text(eventTimeLine(for: event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if let details = nonEmpty(event.details) {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Termine", systemImage: "calendar")
            }

            GroupBox {
                let scheduleEntries = userScheduleByID[normalizedUserID] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(scheduleEntries.count) Stundenplan-Eintraege")
                        .font(.subheadline.weight(.semibold))
                    if scheduleEntries.isEmpty {
                        Text("Keine Stundenplan-Eintraege gefunden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(scheduleEntries.prefix(20)) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(nonEmpty(entry.title) ?? "Eintrag \(entry.id)")
                                    .font(.callout.weight(.medium))
                                    .lineLimit(2)
                                Text(scheduleTimeLine(for: entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Stundenplan", systemImage: "clock.badge.checkmark")
            }

            GroupBox {
                let news = userNewsByID[normalizedUserID] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(news.count) News-Eintraege (neueste zuerst)")
                        .font(.subheadline.weight(.semibold))
                    if news.isEmpty {
                        Text("Keine News fuer diesen Benutzer gefunden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(news.prefix(15)) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(nonEmpty(item.title) ?? "News \(item.id)")
                                    .font(.callout.weight(.medium))
                                    .lineLimit(2)
                                if let preview = userNewsPreviewText(item) {
                                    Text(preview)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                Text(newsMetadataLine(item))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("News", systemImage: "newspaper")
            }

            if let detailError, nonEmpty(detailError) != nil {
                Text(detailError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let extrasError, nonEmpty(extrasError) != nil {
                Text(extrasError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Waehle einen Benutzer aus der Treffer- oder Merkliste aus.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func userInfoRow(_ label: String, _ value: String?) -> some View {
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

    @ViewBuilder
    func userLongTextRow(_ label: String, _ value: String?) -> some View {
        if let text = nonEmpty(value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func userBooleanText(_ value: Bool?) -> String? {
        guard let value else { return nil }
        return value ? "Ja" : "Nein"
    }

    func formattedAPIDate(_ raw: String?) -> String? {
        guard let date = parseAPIDate(raw) else { return nonEmpty(raw) }
        return Self.fileDateFormatter.string(from: date)
    }

    func courseUserMetadataLine(_ course: CourseDTO) -> String {
        var parts: [String] = []
        if let number = nonEmpty(course.courseNumber) {
            parts.append("Kursnr. \(number)")
        }
        if let subtitle = nonEmpty(course.subtitle) {
            parts.append(subtitle)
        }
        if let semester = nonEmpty(course.semesterID) {
            parts.append("Semester: \(semester)")
        }
        return parts.isEmpty ? course.id : parts.joined(separator: " • ")
    }

    func ensureBenutzerInitialLoad() async {
        guard selectedPage == .benutzer, selectedSemesterID == nil else { return }

        if meUserID == nil {
            do {
                let me = try await repository.fetchMe()
                let id = canonicalStudIPID(me.id)
                meUserID = id
                userDetailByID[id] = me
                if selectedUserID == nil {
                    selectUserForDetail(id)
                }
            } catch {
                userSearchError = "Fehler beim Laden von /users/me: \(error.localizedDescription)"
            }
        }

        await loadRememberedUsers()
    }

    func loadRememberedUsers() async {
        let ids = rememberedUserIDs
        guard !ids.isEmpty else {
            rememberedUsersByID = [:]
            return
        }

        isLoadingRememberedUsers = true
        defer { isLoadingRememberedUsers = false }

        var resolved = rememberedUsersByID.filter { ids.contains($0.key) }
        for id in ids {
            if let detail = userDetailByID[id] {
                resolved[id] = detail
            } else if let inSearch = userSearchResults.first(where: { $0.id == id }) {
                resolved[id] = inSearch
            }
        }

        let missingIDs = ids.filter { resolved[$0] == nil }
        if !missingIDs.isEmpty {
            let loaded = await repository.fetchUsersByIDs(missingIDs)
            for (id, user) in loaded {
                resolved[id] = user
                userDetailByID[id] = user
            }
        }

        rememberedUsersByID = resolved
        if selectedUserID == nil {
            if let fallbackID = ids.first ?? meUserID {
                selectUserForDetail(fallbackID)
            }
        }
    }

    func runUserSearch(force: Bool = false) async {
        let query = userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            userSearchResults = []
            if force {
                userSearchError = "Bitte einen Suchbegriff eingeben."
            } else {
                userSearchError = nil
            }
            return
        }

        guard query.count >= 3 else {
            userSearchResults = []
            userSearchError = "Bitte mindestens 3 Zeichen eingeben."
            return
        }

        isLoadingUserSearch = true
        userSearchError = nil
        defer { isLoadingUserSearch = false }

        do {
            let fetched = try await repository.fetchUsers(offset: 0, limit: 100, search: query)
            let sorted = fetched.sorted { lhs, rhs in
                let lhsName = userDisplayName(lhs)
                let rhsName = userDisplayName(rhs)
                if lhsName.caseInsensitiveCompare(rhsName) != .orderedSame {
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }
                let lhsUser = nonEmpty(lhs.username) ?? lhs.id
                let rhsUser = nonEmpty(rhs.username) ?? rhs.id
                return lhsUser.localizedCaseInsensitiveCompare(rhsUser) == .orderedAscending
            }

            userSearchResults = sorted
            for user in sorted {
                userDetailByID[user.id] = user
            }
            if selectedUserID == nil {
                if let firstID = sorted.first?.id {
                    selectUserForDetail(firstID)
                }
            }
            lastUserSearchDate = Date()
        } catch {
            userSearchError = "Fehler bei der Benutzersuche: \(error.localizedDescription)"
        }
    }

    func loadSelectedUserDetailsIfNeeded() async {
        guard selectedPage == .benutzer, selectedSemesterID == nil else { return }
        guard let selectedUserID else { return }
        await ensureUserDetailsLoaded(userID: selectedUserID, force: false)
    }

    func ensureUserDetailsLoaded(userID: String, force: Bool) async {
        let id = canonicalStudIPID(userID)
        guard !loadingUserDetailIDs.contains(id) else { return }
        loadingUserDetailIDs.insert(id)
        defer { loadingUserDetailIDs.remove(id) }

        userDetailErrorByID[id] = nil
        userExtrasErrorByID[id] = nil

        if force || userDetailByID[id] == nil {
            do {
                let detail = try await repository.fetchUser(id: id)
                userDetailByID[id] = detail
                if isRememberedUser(id: id) {
                    rememberedUsersByID[id] = detail
                }
            } catch {
                userDetailErrorByID[id] = "Fehler beim Laden des Profils: \(error.localizedDescription)"
            }
        }

        do {
            let memberships = try await repository.fetchInstituteMemberships(userID: id, offset: 0, limit: 250)
            userInstituteMembershipsByID[id] = memberships
        } catch {
            appendUserExtrasError(userID: id, message: "Institute: \(error.localizedDescription)")
        }

        do {
            let courses = try await repository.fetchCoursesForUser(userID: id, offset: 0, limit: 200)
            let sortedCourses = courses.sorted { lhs, rhs in
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            userCoursesByID[id] = sortedCourses
        } catch {
            appendUserExtrasError(userID: id, message: "Veranstaltungen: \(error.localizedDescription)")
        }

        do {
            let nowTimestamp = Int(Date().timeIntervalSince1970)
            let events = try await repository.fetchUserEvents(userID: id, timestamp: nowTimestamp)
            let sortedEvents = events.sorted { lhs, rhs in
                let lhsStart = parseAPIDate(lhs.start) ?? .distantFuture
                let rhsStart = parseAPIDate(rhs.start) ?? .distantFuture
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            userUpcomingEventsByID[id] = sortedEvents
        } catch {
            appendUserExtrasError(userID: id, message: "Termine: \(error.localizedDescription)")
        }

        do {
            let nowTimestamp = Int(Date().timeIntervalSince1970)
            let schedule = try await repository.fetchUserSchedule(userID: id, timestamp: nowTimestamp)
            let sortedSchedule = schedule.sorted { lhs, rhs in
                let lhsStart = parseAPIDate(lhs.start) ?? .distantFuture
                let rhsStart = parseAPIDate(rhs.start) ?? .distantFuture
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            userScheduleByID[id] = sortedSchedule
        } catch {
            appendUserExtrasError(userID: id, message: "Stundenplan: \(error.localizedDescription)")
        }

        do {
            let news = try await repository.fetchUserNews(userID: id, offset: 0, limit: 20)
            let sortedNews = news.sorted { lhs, rhs in
                let lhsDate = parseAPIDate(lhs.chdate) ?? parseAPIDate(lhs.mkdate) ?? .distantPast
                let rhsDate = parseAPIDate(rhs.chdate) ?? parseAPIDate(rhs.mkdate) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
                let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            userNewsByID[id] = sortedNews
        } catch {
            appendUserExtrasError(userID: id, message: "News: \(error.localizedDescription)")
        }
    }

    func appendUserExtrasError(userID: String, message: String) {
        if let existing = userExtrasErrorByID[userID], !existing.isEmpty {
            userExtrasErrorByID[userID] = "\(existing) | \(message)"
        } else {
            userExtrasErrorByID[userID] = message
        }
    }

    func userDisplayName(_ user: UserDTO) -> String {
        nonEmpty(user.preferredDisplayName) ?? "User \(user.id)"
    }

    func userSecondaryLine(_ user: UserDTO) -> String {
        let username = nonEmpty(user.username).map { "@\($0)" }
        let permission = nonEmpty(user.permission).map { "Rolle: \($0)" }
        let email = nonEmpty(user.email)
        let phone = nonEmpty(user.phone)
        let parts = [username, permission, email, phone].compactMap { $0 }
        return parts.isEmpty ? "Keine Zusatzinfos" : parts.joined(separator: " • ")
    }

    func userInitials(_ user: UserDTO) -> String {
        if let given = nonEmpty(user.givenName), let family = nonEmpty(user.familyName) {
            let g = given.prefix(1).uppercased()
            let f = family.prefix(1).uppercased()
            return "\(g)\(f)"
        }

        let name = userDisplayName(user)
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        return letters.isEmpty ? "?" : letters
    }

    func userNewsPreviewText(_ newsItem: NewsDTO) -> String? {
        guard let content = nonEmpty(newsItem.content) else { return nil }
        if content.contains("<"), content.contains(">") {
            return plainText(fromHTML: content)
        }
        return content
    }

    func openMailAddress(_ address: String?) {
        guard let email = nonEmpty(address) else { return }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    func openHomepage(_ homepage: String?) {
        guard let raw = nonEmpty(homepage) else { return }

        let prefixed = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: prefixed) else { return }
        NSWorkspace.shared.open(url)
    }
}
