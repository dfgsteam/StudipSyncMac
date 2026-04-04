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

                        if hasSearchQuery(userSearchQuery) {
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
                    uiEmptyState(
                        title: "Keine Benutzer",
                        message: !hasSearchQuery(userSearchQuery)
                            ? "Starte oben eine Suche nach Name, Username oder E-Mail."
                            : "Keine Treffer fuer den aktuellen Suchbegriff. Tipp: mindestens 3 Zeichen.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
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
            await loadSharedCoursesFromLocalCacheIfNeeded()
        }
        .task(id: rememberedUserIDsCSV) {
            await loadRememberedUsers()
        }
        .task(id: selectedUserID ?? "none") {
            selectedUserCalendarDay = Calendar.current.startOfDay(for: Date())
            await loadSharedCoursesFromLocalCacheIfNeeded()
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
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(appHeaderFill)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedUserID {
                        userDetailView(userID: selectedUserID)
                    } else {
                        uiEmptyState(
                            title: "Kein Benutzer ausgewaehlt",
                            message: "Waehle links einen Benutzer aus der Treffer- oder Merkliste aus.",
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(appDetailPanelColor)
        }
    }

    @ViewBuilder
    func rememberedUserRow(userID: String) -> some View {
        let user = rememberedUsersByID[userID] ?? userDetailByID[userID]
        let isSelected = selectedUserID == userID

        HStack(alignment: .center, spacing: 10) {
            if let user {
                userAvatarView(user: user, size: 28)
            } else {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }

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
            userAvatarView(user: user, size: 30)

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
                    HStack(alignment: .top, spacing: 10) {
                        userAvatarView(user: user, size: 48)

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
                let sharedEntries = sharedCourseEntries(for: normalizedUserID)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(sharedEntries.count) gemeinsame Veranstaltungen")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if isLoadingSharedCourses {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Lokal aktualisieren") {
                            Task {
                                await rebuildSharedCoursesCache()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLoadingSharedCourses)
                    }

                    if let sharedCoursesUpdatedAt {
                        Text("Stand: \(Self.fileDateFormatter.string(from: sharedCoursesUpdatedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let message = nonEmpty(sharedCoursesError) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if sharedEntries.isEmpty {
                        Text("Noch keine lokalen Daten. Mit \"Lokal aktualisieren\" werden Teilnehmer aller deiner belegten Kurse ausgewertet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sharedEntries) { entry in
                            sharedCourseRow(entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Gemeinsame Veranstaltungen", systemImage: "person.2.badge.gearshape")
            }

            GroupBox {
                let events = userUpcomingEventsByID[normalizedUserID] ?? []
                let filteredEvents = eventsForCalendarDay(events, day: selectedUserCalendarDay)
                let undatedEvents = undatedEventsForCalendar(events)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(filteredEvents.count) Termine am Tag")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if !events.isEmpty {
                            Label("Kalender", systemImage: "calendar.badge.clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if events.isEmpty {
                        Text("Keine anstehenden Termine gefunden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        DatePicker(
                            "Tag",
                            selection: $selectedUserCalendarDay,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(maxWidth: 320, alignment: .leading)

                        Text(Self.calendarDayOnlyFormatter.string(from: selectedUserCalendarDay))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if filteredEvents.isEmpty {
                            Text("Keine Termine am ausgewaehlten Tag.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredEvents.prefix(30)) { event in
                                userEventCalendarRow(event)
                            }
                        }

                        if !undatedEvents.isEmpty {
                            Text("\(undatedEvents.count) Termine ohne Datum sind nicht tagbasiert filterbar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Termine", systemImage: "calendar")
            }

            GroupBox {
                let scheduleEntries = userScheduleByID[normalizedUserID] ?? []
                let filteredScheduleEntries = scheduleEntriesForCalendarDay(scheduleEntries, day: selectedUserCalendarDay)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(filteredScheduleEntries.count) Stundenplan-Eintraege am Tag")
                        .font(.subheadline.weight(.semibold))
                    if scheduleEntries.isEmpty {
                        Text("Keine Stundenplan-Eintraege gefunden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        DatePicker(
                            "Tag",
                            selection: $selectedUserCalendarDay,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(maxWidth: 320, alignment: .leading)

                        if filteredScheduleEntries.isEmpty {
                            Text("Keine Stundenplan-Eintraege am ausgewaehlten Tag.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredScheduleEntries.prefix(20)) { entry in
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
        let query = normalizedSearchQuery(userSearchQuery) ?? ""

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
            let debugCURL = await repository.debugUsersSearchCURL(search: query, offset: 0, limit: 100)
            recordSearchFailure(context: "Benutzersuche", query: query, curl: debugCURL, error: error)
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

        let shouldLoadMemberships = force || userInstituteMembershipsByID[id] == nil
        let shouldLoadCourses = force || userCoursesByID[id] == nil
        let shouldLoadEvents = force || userUpcomingEventsByID[id] == nil
        let shouldLoadSchedule = force || userScheduleByID[id] == nil
        let shouldLoadNews = force || userNewsByID[id] == nil

        guard shouldLoadMemberships || shouldLoadCourses || shouldLoadEvents || shouldLoadSchedule || shouldLoadNews else {
            return
        }

        let nowTimestamp = Int(Date().timeIntervalSince1970)

        async let membershipsResult: Result<[InstituteMembershipDTO], Error>? = shouldLoadMemberships
            ? loadUserExtrasResult { try await repository.fetchInstituteMemberships(userID: id, offset: 0, limit: 250) }
            : nil
        async let coursesResult: Result<[CourseDTO], Error>? = shouldLoadCourses
            ? loadUserExtrasResult { try await repository.fetchCoursesForUser(userID: id, offset: 0, limit: 200) }
            : nil
        async let eventsResult: Result<[EventDTO], Error>? = shouldLoadEvents
            ? loadUserExtrasResult { try await repository.fetchUserEvents(userID: id, timestamp: nowTimestamp) }
            : nil
        async let scheduleResult: Result<[ScheduleEntryDTO], Error>? = shouldLoadSchedule
            ? loadUserExtrasResult { try await repository.fetchUserSchedule(userID: id, timestamp: nowTimestamp) }
            : nil
        async let newsResult: Result<[NewsDTO], Error>? = shouldLoadNews
            ? loadUserExtrasResult { try await repository.fetchUserNews(userID: id, offset: 0, limit: 20) }
            : nil

        if let membershipsResult = await membershipsResult {
            switch membershipsResult {
            case .success(let memberships):
                userInstituteMembershipsByID[id] = memberships
            case .failure(let error):
                appendUserExtrasError(userID: id, message: "Institute: \(error.localizedDescription)")
            }
        }

        if let coursesResult = await coursesResult {
            switch coursesResult {
            case .success(let courses):
                userCoursesByID[id] = sortUserCoursesForDisplay(courses)
            case .failure(let error):
                appendUserExtrasError(userID: id, message: "Veranstaltungen: \(error.localizedDescription)")
            }
        }

        if let eventsResult = await eventsResult {
            switch eventsResult {
            case .success(let events):
                userUpcomingEventsByID[id] = sortUserEventsForDisplay(events)
            case .failure(let error):
                appendUserExtrasError(userID: id, message: "Termine: \(error.localizedDescription)")
            }
        }

        if let scheduleResult = await scheduleResult {
            switch scheduleResult {
            case .success(let schedule):
                userScheduleByID[id] = sortUserScheduleForDisplay(schedule)
            case .failure(let error):
                appendUserExtrasError(userID: id, message: "Stundenplan: \(error.localizedDescription)")
            }
        }

        if let newsResult = await newsResult {
            switch newsResult {
            case .success(let news):
                userNewsByID[id] = sortUserNewsForDisplay(news)
            case .failure(let error):
                appendUserExtrasError(userID: id, message: "News: \(error.localizedDescription)")
            }
        }
    }

    func loadUserExtrasResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    func sortUserCoursesForDisplay(_ courses: [CourseDTO]) -> [CourseDTO] {
        courses.sorted { lhs, rhs in
            let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
            let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
    }

    func sortUserEventsForDisplay(_ events: [EventDTO]) -> [EventDTO] {
        events.sorted { lhs, rhs in
            let lhsStart = parseAPIDate(lhs.start) ?? .distantFuture
            let rhsStart = parseAPIDate(rhs.start) ?? .distantFuture
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
            let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
            let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
    }

    func userEventCalendarTemplate(events: [EventDTO]) -> some View {
        let groupedEvents = groupedUserEventsByDay(events)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(groupedEvents.indices, id: \.self) { index in
                let section = groupedEvents[index]

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(userEventDayHeader(for: section.day))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(section.events.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    ForEach(section.events) { event in
                        userEventCalendarRow(event)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    func groupedUserEventsByDay(_ events: [EventDTO]) -> [(day: Date?, events: [EventDTO])] {
        let sortedEvents = sortUserEventsForDisplay(events)
        let calendar = Calendar.current
        let grouped: [Date?: [EventDTO]] = Dictionary(grouping: sortedEvents) { event in
            guard let start = parseAPIDate(event.start) else { return nil }
            return calendar.startOfDay(for: start)
        }

        var datedSections: [(day: Date?, events: [EventDTO])] = []
        datedSections.reserveCapacity(grouped.count)

        for (key, value) in grouped {
            if let key {
                datedSections.append((day: key, events: value))
            }
        }

        datedSections.sort { lhs, rhs in
            guard let lhsDay = lhs.day, let rhsDay = rhs.day else { return false }
            return lhsDay < rhsDay
        }

        if let undatedEvents = grouped[nil], !undatedEvents.isEmpty {
            datedSections.append((day: nil, events: undatedEvents))
        }

        return datedSections
    }

    func userEventCalendarRow(_ event: EventDTO) -> some View {
        let startDate = parseAPIDate(event.start)
        let endDate = parseAPIDate(event.end)

        return HStack(alignment: .top, spacing: 10) {
            Text(userEventTimeRange(startDate: startDate, endDate: endDate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(nonEmpty(event.title) ?? "Termin \(event.id)")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)

                if let details = nonEmpty(event.details) {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func userEventDayHeader(for day: Date?) -> String {
        guard let day else { return "Ohne Datum" }
        return Self.userEventDayFormatter.string(from: day)
    }

    func userEventTimeRange(startDate: Date?, endDate: Date?) -> String {
        if let startDate, let endDate {
            let calendar = Calendar.current
            if calendar.isDate(startDate, inSameDayAs: endDate) {
                return "\(Self.userEventTimeFormatter.string(from: startDate)) - \(Self.userEventTimeFormatter.string(from: endDate))"
            }
            return "\(Self.fileDateFormatter.string(from: startDate)) - \(Self.fileDateFormatter.string(from: endDate))"
        }

        if let startDate {
            return "Ab \(Self.userEventTimeFormatter.string(from: startDate))"
        }

        if let endDate {
            return "Bis \(Self.userEventTimeFormatter.string(from: endDate))"
        }

        return "Keine Zeitangabe"
    }

    func sortUserScheduleForDisplay(_ scheduleEntries: [ScheduleEntryDTO]) -> [ScheduleEntryDTO] {
        scheduleEntries.sorted { lhs, rhs in
            let lhsStart = parseAPIDate(lhs.start) ?? .distantFuture
            let rhsStart = parseAPIDate(rhs.start) ?? .distantFuture
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
            let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
            let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
    }

    func sortUserNewsForDisplay(_ news: [NewsDTO]) -> [NewsDTO] {
        news.sorted { lhs, rhs in
            let lhsDate = parseAPIDate(lhs.chdate) ?? parseAPIDate(lhs.mkdate) ?? .distantPast
            let rhsDate = parseAPIDate(rhs.chdate) ?? parseAPIDate(rhs.mkdate) ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            let lhsTitle = nonEmpty(lhs.title) ?? lhs.id
            let rhsTitle = nonEmpty(rhs.title) ?? rhs.id
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
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

    func sharedCourseEntries(for userID: String) -> [SharedCourseParticipationCache.SharedCourseEntry] {
        let normalizedID = canonicalStudIPID(userID)
        let entries = sharedCoursesByUserID[normalizedID] ?? []
        return entries.sorted { lhs, rhs in
            let lhsSemester = nonEmpty(lhs.semesterTitle) ?? nonEmpty(lhs.semesterID) ?? ""
            let rhsSemester = nonEmpty(rhs.semesterTitle) ?? nonEmpty(rhs.semesterID) ?? ""
            if lhsSemester.localizedCaseInsensitiveCompare(rhsSemester) != .orderedSame {
                return lhsSemester.localizedCaseInsensitiveCompare(rhsSemester) == .orderedAscending
            }
            return lhs.courseTitle.localizedCaseInsensitiveCompare(rhs.courseTitle) == .orderedAscending
        }
    }

    @ViewBuilder
    func sharedCourseRow(_ entry: SharedCourseParticipationCache.SharedCourseEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let semesterTitle = nonEmpty(entry.semesterTitle) ?? nonEmpty(entry.semesterID) {
                Text(semesterTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if nonEmpty(entry.semesterID) != nil {
                Button(entry.courseTitle) {
                    Task {
                        await openSharedCourseInApp(entry)
                    }
                }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(entry.courseTitle)
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func loadSharedCoursesFromLocalCacheIfNeeded() async {
        guard selectedPage == .benutzer, selectedSemesterID == nil else { return }
        if isLoadingSharedCourses { return }

        do {
            let baseURL = await repository.currentBaseURL()
            let ownerID = try await currentUserIDForSharedCourseCache()
            let namespaceKey = makeSharedCoursesNamespaceKey(baseURL: baseURL, ownerUserID: ownerID)

            if sharedCoursesNamespaceKey == namespaceKey, !sharedCoursesByUserID.isEmpty {
                return
            }

            if let snapshot = try await sharedCourseParticipationCache.load(baseURL: baseURL, ownerUserID: ownerID) {
                applySharedCourseSnapshot(snapshot, namespaceKey: namespaceKey)
            } else {
                sharedCoursesByUserID = [:]
                sharedCoursesUpdatedAt = nil
                sharedCoursesNamespaceKey = namespaceKey
            }
        } catch {
            sharedCoursesError = "Lokaler Shared-Course-Cache konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    func rebuildSharedCoursesCache() async {
        guard selectedPage == .benutzer, selectedSemesterID == nil else { return }
        if isLoadingSharedCourses { return }

        isLoadingSharedCourses = true
        sharedCoursesError = nil
        defer { isLoadingSharedCourses = false }

        do {
            let baseURL = await repository.currentBaseURL()
            let ownerID = try await currentUserIDForSharedCourseCache()
            let semesterResult = try await repository.loadSemestersStaleWhileRevalidate()
            let semesterTitleByID = Dictionary(
                uniqueKeysWithValues: semesterResult.semesters.map { (canonicalStudIPID($0.id), $0.title) }
            )

            let myCourses = try await repository.fetchCoursesForUser(
                userID: ownerID,
                semesterID: nil,
                offset: 0,
                limit: 1000
            )

            var map: [String: [SharedCourseParticipationCache.SharedCourseEntry]] = [:]
            map.reserveCapacity(512)

            for course in myCourses {
                let semesterID = nonEmpty(course.semesterID)
                    ?? nonEmpty(course.startSemesterRef)
                    ?? nonEmpty(course.endSemesterRef)
                let canonicalSemesterID = semesterID.map(canonicalStudIPID)

                let entry = SharedCourseParticipationCache.SharedCourseEntry(
                    courseID: canonicalStudIPID(course.id),
                    courseTitle: nonEmpty(course.title) ?? "Kurs \(course.id)",
                    semesterID: canonicalSemesterID,
                    semesterTitle: canonicalSemesterID.flatMap { semesterTitleByID[$0] }
                )

                let participants = try await repository.fetchCourseParticipants(
                    courseID: course.id,
                    offset: 0,
                    limit: 1000
                )

                for participant in participants {
                    let participantID = canonicalStudIPID(participant.userID)
                    if participantID == ownerID {
                        continue
                    }
                    map[participantID, default: []].append(entry)
                }
            }

            for (userID, entries) in map {
                var dedupByCourseID: [String: SharedCourseParticipationCache.SharedCourseEntry] = [:]
                dedupByCourseID.reserveCapacity(entries.count)
                for entry in entries {
                    dedupByCourseID[entry.courseID] = entry
                }
                map[userID] = Array(dedupByCourseID.values)
            }

            let snapshot = SharedCourseParticipationCache.Snapshot(
                ownerUserID: ownerID,
                updatedAt: Date(),
                version: 1,
                entriesByUserID: map
            )
            try await sharedCourseParticipationCache.save(baseURL: baseURL, snapshot: snapshot)
            applySharedCourseSnapshot(
                snapshot,
                namespaceKey: makeSharedCoursesNamespaceKey(baseURL: baseURL, ownerUserID: ownerID)
            )
        } catch {
            sharedCoursesError = "Shared-Course-Cache konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func currentUserIDForSharedCourseCache() async throws -> String {
        if let meUserID, !meUserID.isEmpty {
            return canonicalStudIPID(meUserID)
        }
        let me = try await repository.fetchMe()
        let canonicalID = canonicalStudIPID(me.id)
        meUserID = canonicalID
        return canonicalID
    }

    func applySharedCourseSnapshot(_ snapshot: SharedCourseParticipationCache.Snapshot, namespaceKey: String) {
        sharedCoursesByUserID = snapshot.entriesByUserID
        sharedCoursesUpdatedAt = snapshot.updatedAt
        sharedCoursesNamespaceKey = namespaceKey
    }

    func makeSharedCoursesNamespaceKey(baseURL: URL, ownerUserID: String) -> String {
        "\(baseURL.absoluteString.lowercased())|\(canonicalStudIPID(ownerUserID))"
    }

    func openSharedCourseInApp(_ entry: SharedCourseParticipationCache.SharedCourseEntry) async {
        guard let semesterID = nonEmpty(entry.semesterID) else { return }

        navigateToSidebarState(
            SidebarNavigationState(
                page: selectedSidebarPage ?? .start,
                semesterID: semesterID,
                courseID: nil
            )
        )

        await loadCoursesForSelectedSemester()

        if courses.contains(where: { canonicalStudIPID($0.id) == canonicalStudIPID(entry.courseID) }) {
            selectSidebarCourse(entry.courseID)
        }
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

    func userAvatarURL(_ user: UserDTO) -> URL? {
        absoluteAssetURL(user.preferredAvatarPath)
    }

    func absoluteAssetURL(_ rawPath: String?) -> URL? {
        guard let rawPath = nonEmpty(rawPath) else { return nil }

        if let absolute = URL(string: rawPath), absolute.scheme != nil {
            return absolute
        }

        guard let baseURL = apiBaseURLForAssets else {
            return nil
        }

        let normalizedPath = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        return URL(string: normalizedPath, relativeTo: baseURL)?.absoluteURL
    }

    @ViewBuilder
    func userAvatarView(user: UserDTO, size: CGFloat) -> some View {
        if let avatarURL = userAvatarURL(user) {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                case .failure:
                    avatarInitialsFallback(user: user, size: size)
                @unknown default:
                    avatarInitialsFallback(user: user, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        } else {
            avatarInitialsFallback(user: user, size: size)
        }
    }

    func avatarInitialsFallback(user: UserDTO, size: CGFloat) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.18))
            .overlay {
                Text(userInitials(user))
                    .font(.system(size: max(11, size * 0.34), weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: size, height: size)
    }

    func userNewsPreviewText(_ newsItem: NewsDTO) -> String? {
        guard let content = nonEmpty(newsItem.content) else { return nil }
        if content.contains("<"), content.contains(">") {
            return plainText(fromHTML: content)
        }
        return content
    }

    static let userEventDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM"
        return formatter
    }()

    static let userEventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

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
