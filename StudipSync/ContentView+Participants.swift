import AppKit
import SwiftUI

extension ContentView {
    static let participantNameColumnWidth: CGFloat = 250
    static let participantEmailColumnWidth: CGFloat = 220
    static let participantLabelColumnWidth: CGFloat = 170
    static let participantPositionColumnWidth: CGFloat = 56
    static let participantGroupColumnWidth: CGFloat = 56
    static let participantActionsColumnWidth: CGFloat = 88

    @ViewBuilder
    func participantsBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.participants.id)

        if isLoadingParticipants, participantsByCourseID[course.id] == nil {
            ProgressView("Lade Teilnehmer ...")
                .controlSize(.small)
        } else if let participants = participantsByCourseID[course.id], !participants.isEmpty {
            let filteredParticipants = query.isEmpty ? participants : participants.filter { participant in
                containsSearch(
                    [
                        participant.displayName,
                        nonEmpty(participant.email),
                        nonEmpty(participant.permission),
                        nonEmpty(participant.label),
                        participant.userID
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }
            let groupedParticipants = groupedParticipantsByRole(filteredParticipants)

            if filteredParticipants.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.participants.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if groupedParticipants.isEmpty {
                Text("Keine Teilnehmer mit Rolle root/admin/dozent/tutor/autor vorhanden.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.participantRoleOrder, id: \.self) { roleKey in
                        if let roleParticipants = groupedParticipants[roleKey], !roleParticipants.isEmpty {
                            participantRoleTable(
                                title: participantRoleTitle(for: roleKey),
                                participants: roleParticipants
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 140)
            }
        } else if let errorText = participantErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Teilnehmer gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func participantRoleTable(
        title: String,
        participants: [StudIPResourceRepository.CourseParticipant]
    ) -> some View {
        let tableWidth =
            Self.participantNameColumnWidth
            + Self.participantEmailColumnWidth
            + Self.participantLabelColumnWidth
            + Self.participantPositionColumnWidth
            + Self.participantGroupColumnWidth
            + Self.participantActionsColumnWidth
            + 12 * 5

        return VStack(alignment: .leading, spacing: 6) {
            Label("\(title) (\(participants.count))", systemImage: "person.3.sequence")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.participantNameColumnWidth, alignment: .leading)
                        Text("E-Mail")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.participantEmailColumnWidth, alignment: .leading)
                        Text("Label")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.participantLabelColumnWidth, alignment: .leading)
                        Text("Pos.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.participantPositionColumnWidth, alignment: .leading)
                        Text("Gr.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.participantGroupColumnWidth, alignment: .leading)
                        Text("Aktionen")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.participantActionsColumnWidth, alignment: .leading)
                    }

                    Divider()
                        .gridCellColumns(6)

                    ForEach(participants) { participant in
                        GridRow(alignment: .center) {
                            Text(participant.displayName)
                                .lineLimit(1)
                                .frame(width: Self.participantNameColumnWidth, alignment: .leading)
                                .help("User-ID: \(participant.userID)")

                            Text(nonEmpty(participant.email) ?? "—")
                                .foregroundStyle(nonEmpty(participant.email) == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .frame(width: Self.participantEmailColumnWidth, alignment: .leading)

                            Text(nonEmpty(participant.label) ?? "—")
                                .foregroundStyle(nonEmpty(participant.label) == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .frame(width: Self.participantLabelColumnWidth, alignment: .leading)

                            Text(participant.position.map(String.init) ?? "—")
                                .foregroundStyle(participant.position == nil ? .secondary : .primary)
                                .frame(width: Self.participantPositionColumnWidth, alignment: .leading)

                            Text(participant.group.map(String.init) ?? "—")
                                .foregroundStyle(participant.group == nil ? .secondary : .primary)
                                .frame(width: Self.participantGroupColumnWidth, alignment: .leading)

                            HStack(spacing: 8) {
                                Button {
                                    openParticipantInUserDetail(participant)
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Benutzerprofil anzeigen")

                                Button {
                                    openMail(for: participant)
                                } label: {
                                    Image(systemName: "envelope")
                                }
                                .buttonStyle(.borderless)
                                .disabled(nonEmpty(participant.email) == nil)
                                .help(nonEmpty(participant.email) == nil ? "Keine Mailadresse vorhanden" : "Mail senden")
                            }
                            .frame(width: Self.participantActionsColumnWidth, alignment: .leading)
                        }
                    }
                }
                .frame(width: tableWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    static let participantRoleOrder = ["root", "admin", "dozent", "tutor", "autor"]

    func groupedParticipantsByRole(
        _ participants: [StudIPResourceRepository.CourseParticipant]
    ) -> [String: [StudIPResourceRepository.CourseParticipant]] {
        var grouped: [String: [StudIPResourceRepository.CourseParticipant]] = [:]
        grouped.reserveCapacity(Self.participantRoleOrder.count)

        for participant in participants {
            guard let roleKey = participantRoleKey(for: participant.permission) else {
                continue
            }
            grouped[roleKey, default: []].append(participant)
        }

        for roleKey in grouped.keys {
            grouped[roleKey]?.sort { lhs, rhs in
                let lhsPosition = lhs.position ?? Int.max
                let rhsPosition = rhs.position ?? Int.max
                if lhsPosition != rhsPosition {
                    return lhsPosition < rhsPosition
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }

        return grouped
    }

    func participantRoleKey(for permission: String?) -> String? {
        guard let normalized = nonEmpty(permission)?.lowercased() else {
            return nil
        }
        guard Self.participantRoleOrder.contains(normalized) else {
            return nil
        }
        return normalized
    }

    func participantRoleTitle(for roleKey: String) -> String {
        switch roleKey {
        case "root":
            return "Root"
        case "admin":
            return "Admin"
        case "dozent":
            return "Dozent"
        case "tutor":
            return "Tutor"
        case "autor":
            return "Autor"
        default:
            return roleKey.capitalized
        }
    }

    func openMail(for participant: StudIPResourceRepository.CourseParticipant) {
        guard let email = nonEmpty(participant.email) else {
            return
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email

        guard let url = components.url else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openParticipantInUserDetail(_ participant: StudIPResourceRepository.CourseParticipant) {
        navigateToSidebarPage(.benutzer)
        selectUserForDetail(participant.userID)

        Task {
            await ensureUserDetailsLoaded(userID: participant.userID, force: false)
        }
    }

    func participantInfoSheet(for participant: StudIPResourceRepository.CourseParticipant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(participant.displayName)
                .font(.title3.weight(.semibold))

            Divider()

            participantInfoRow("User-ID", participant.userID)
            participantInfoRow("E-Mail", nonEmpty(participant.email))
            participantInfoRow("Rolle", nonEmpty(participant.permission))
            participantInfoRow("Label", nonEmpty(participant.label))
            participantInfoRow("Position", participant.position.map(String.init))
            participantInfoRow("Gruppe", participant.group.map(String.init))
            participantInfoRow("Erstellt", nonEmpty(participant.mkdate))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 260)
    }

    @ViewBuilder
    func participantInfoRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            if let value {
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Text("-")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
