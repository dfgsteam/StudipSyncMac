import SwiftUI

extension ContentView {
    var profilContentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if isLoadingMeProfile {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Mein Profil (/users/me)")
                            .font(.headline)
                    }

                    if let profile = meProfile {
                        HStack(alignment: .top, spacing: 10) {
                            userAvatarView(user: profile, size: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(userDisplayName(profile))
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
                                Text(userSecondaryLine(profile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    } else if let meProfileError, nonEmpty(meProfileError) != nil {
                        Text(meProfileError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        uiEmptyState(
                            title: "Profil noch nicht geladen",
                            message: "Lade oben dein Profil aus /users/me.",
                            systemImage: "person.crop.circle.badge.clock"
                        )
                    }

                    if let meProfileLoadedDate {
                        Text("Stand: \(Self.fileDateFormatter.string(from: meProfileLoadedDate))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Profil", systemImage: "person.crop.circle")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Profil neu laden") {
                        Task { await loadMyProfile(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoadingMeProfile || isLoadingMeProfileRaw)

                    Button("Rohdaten neu laden") {
                        Task { await loadMyProfileRaw(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingMeProfileRaw)

                    Toggle("Rohantwort einblenden", isOn: $isShowingMeProfileRawJSON)
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Aktionen", systemImage: "arrow.clockwise")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .task {
            await ensureProfileInitialLoad()
        }
    }

    var profilDetailColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mein Profil")
                        .font(.title2.weight(.bold))
                    Text("Detailansicht der Daten aus /users/me")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(isShowingMeProfileRawJSON ? "Rohdaten ausblenden" : "Rohdaten zeigen") {
                        isShowingMeProfileRawJSON.toggle()
                        if isShowingMeProfileRawJSON {
                            Task { await loadMyProfileRaw(force: false) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Neu laden") {
                        Task {
                            await loadMyProfile(force: true)
                            await loadMyProfileRaw(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoadingMeProfile || isLoadingMeProfileRaw)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(appHeaderFill)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let profile = meProfile {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    userAvatarView(user: profile, size: 52)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(userDisplayName(profile))
                                            .font(.title3.weight(.semibold))
                                        Text(userSecondaryLine(profile))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        openMailAddress(profile.email)
                                    } label: {
                                        Label("Mail", systemImage: "envelope")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(nonEmpty(profile.email) == nil)

                                    Button {
                                        openHomepage(profile.homepage)
                                    } label: {
                                        Label("Homepage", systemImage: "link")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(nonEmpty(profile.homepage) == nil)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Uebersicht", systemImage: "person.text.rectangle")
                        }

                        GroupBox {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                userInfoRow("ID", profile.id)
                                userInfoRow("Username", nonEmpty(profile.username))
                                userInfoRow("Display Name", nonEmpty(profile.displayName))
                                userInfoRow("Full Name", nonEmpty(profile.fullName))
                                userInfoRow("Titel (vor)", nonEmpty(profile.namePrefix))
                                userInfoRow("Vorname", nonEmpty(profile.givenName))
                                userInfoRow("Nachname", nonEmpty(profile.familyName))
                                userInfoRow("Titel (nach)", nonEmpty(profile.nameSuffix))
                                userInfoRow("Rolle", nonEmpty(profile.permission))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Basisdaten", systemImage: "text.below.photo")
                        }

                        GroupBox {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                userInfoRow("Auth-Plugin", nonEmpty(profile.authPlugin))
                                userInfoRow("Sichtbar", userBooleanText(profile.visible))
                                userInfoRow("Gesperrt", userBooleanText(profile.locked))
                                userInfoRow("Sperrhinweis", nonEmpty(profile.lockComment))
                                userInfoRow("Matrikelnummer", nonEmpty(profile.matriculationNumber))
                                userInfoRow("Geschlecht", nonEmpty(profile.gender))
                                userInfoRow("Sprache", nonEmpty(profile.preferredLanguage))
                                userInfoRow("Erstellt", formattedAPIDate(profile.mkdate))
                                userInfoRow("Aktualisiert", formattedAPIDate(profile.chdate))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Account", systemImage: "lock.shield")
                        }

                        GroupBox {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                userInfoRow("E-Mail", nonEmpty(profile.email))
                                userInfoRow("Telefon", nonEmpty(profile.phone))
                                userInfoRow("Mobil", nonEmpty(profile.cellphone))
                                userInfoRow("Adresse", nonEmpty(profile.address))
                                userInfoRow("Homepage", nonEmpty(profile.homepage))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Kontakt", systemImage: "phone")
                        }

                        if nonEmpty(profile.hobby) != nil || nonEmpty(profile.cv) != nil || nonEmpty(profile.publication) != nil || nonEmpty(profile.focus) != nil || nonEmpty(profile.motto) != nil {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    userLongTextRow("Hobby", profile.hobby)
                                    userLongTextRow("Schwerpunkte", profile.focus)
                                    userLongTextRow("Motto", profile.motto)
                                    userLongTextRow("Publikationen", profile.publication)
                                    userLongTextRow("Lebenslauf", profile.cv)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                Label("Profiltexte", systemImage: "doc.text")
                            }
                        }
                    } else if isLoadingMeProfile {
                        ProgressView("Lade /users/me ...")
                            .controlSize(.small)
                    } else if let meProfileError, nonEmpty(meProfileError) != nil {
                        Text(meProfileError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if isShowingMeProfileRawJSON {
                        GroupBox {
                            if isLoadingMeProfileRaw, meProfileRawJSON == nil {
                                ProgressView("Lade Rohdaten ...")
                                    .controlSize(.small)
                            } else if let meProfileRawJSON, nonEmpty(meProfileRawJSON) != nil {
                                ScrollView(.horizontal) {
                                    Text(meProfileRawJSON)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 360)
                            } else if let meProfileRawError, nonEmpty(meProfileRawError) != nil {
                                Text(meProfileRawError)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                    } else {
                        uiEmptyState(
                            title: "Keine Rohdaten",
                            message: "Es sind noch keine JSON-Rohdaten fuer /users/me geladen.",
                            systemImage: "curlybraces.square"
                        )
                    }
                } label: {
                    Label("Rohantwort /users/me", systemImage: "curlybraces")
                        }
                    }
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

    func ensureProfileInitialLoad() async {
        guard selectedPage == .profil, selectedSemesterID == nil else { return }
        await loadMyProfile(force: false)
        await loadMyProfileRaw(force: false)
    }

    func loadMyProfile(force: Bool) async {
        guard selectedPage == .profil, selectedSemesterID == nil else { return }
        if isLoadingMeProfile { return }
        if !force, meProfile != nil { return }

        isLoadingMeProfile = true
        meProfileError = nil
        defer { isLoadingMeProfile = false }

        do {
            let me = try await repository.fetchMe()
            meProfile = me
            meProfileLoadedDate = Date()
            meUserID = canonicalStudIPID(me.id)
            userDetailByID[canonicalStudIPID(me.id)] = me
        } catch {
            meProfileError = "Fehler bei /users/me: \(error.localizedDescription)"
        }
    }

    func loadMyProfileRaw(force: Bool) async {
        guard selectedPage == .profil, selectedSemesterID == nil else { return }
        if isLoadingMeProfileRaw { return }
        if !force, meProfileRawJSON != nil { return }

        isLoadingMeProfileRaw = true
        meProfileRawError = nil
        defer { isLoadingMeProfileRaw = false }

        do {
            meProfileRawJSON = try await repository.fetchMeRawJSON()
        } catch {
            meProfileRawError = "Fehler bei Rohdaten /users/me: \(error.localizedDescription)"
        }
    }
}
