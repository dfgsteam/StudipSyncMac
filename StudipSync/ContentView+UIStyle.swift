import SwiftUI

private enum StudipUITheme {
    static let headerGradient = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.18),
            Color.accentColor.opacity(0.08),
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sidebarPanel = Color(nsColor: .controlBackgroundColor).opacity(0.82)
    static let panel = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let detailPanel = Color(nsColor: .windowBackgroundColor).opacity(0.86)
    static let mutedPanel = Color.accentColor.opacity(0.08)
    static let border = Color.accentColor.opacity(0.18)
}

struct StudipSoftGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(StudipUITheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudipUITheme.border, lineWidth: 1)
        )
    }
}

extension ContentView {
    var appHeaderFill: AnyShapeStyle {
        AnyShapeStyle(StudipUITheme.headerGradient)
    }

    var appSidebarPanelColor: Color {
        StudipUITheme.sidebarPanel
    }

    var appPanelColor: Color {
        StudipUITheme.panel
    }

    var appDetailPanelColor: Color {
        StudipUITheme.detailPanel
    }

    var appMutedPanelColor: Color {
        StudipUITheme.mutedPanel
    }

    var appBorderColor: Color {
        StudipUITheme.border
    }

    var appBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.16),
                Color.accentColor.opacity(0.05),
                Color(nsColor: .windowBackgroundColor).opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func uiEmptyState(title: String, message: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(appMutedPanelColor)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(appBorderColor.opacity(0.6), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func uiSectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(appPanelColor)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(appBorderColor.opacity(0.75), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var headerNavigationAndActions: some View {
        let usesUserHistory = selectedSemesterID == nil
            && selectedPage == .benutzer
            && !userNavigationHistory.isEmpty

        return HStack(spacing: 8) {
            Button {
                if usesUserHistory {
                    navigateUserBackward()
                } else {
                    goBackInSidebarNavigation()
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(usesUserHistory ? !canNavigateUserBackward : !canGoBackInSidebarNavigation)
            .help("Zurueck")

            Button {
                if usesUserHistory {
                    navigateUserForward()
                } else {
                    goForwardInSidebarNavigation()
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(usesUserHistory ? !canNavigateUserForward : !canGoForwardInSidebarNavigation)
            .help("Vor")

            Button {
                Task {
                    await reloadCurrentHeaderContext()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Neu laden")

            Button {
                syncScheduler.triggerManualSync()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Jetzt synchronisieren")
        }
    }

    func reloadCurrentHeaderContext() async {
        if let selectedCourseID {
            await forceReloadAllDetailContent(for: selectedCourseID)
            return
        }

        if let semester = selectedSemester {
            coursesBySemesterID[semester.id] = nil
            coursePrefetchErrorsBySemesterID[semester.id] = nil
            await loadCoursesForSelectedSemester()
            await loadSemesterSchedule(for: semester, force: true)
            return
        }

        switch selectedPage {
        case .start:
            semesterViewModel.loadSemesters()
            await loadStartSchedule(force: true)

        case .profil:
            await loadMyProfile(force: true)
            await loadMyProfileRaw(force: true)

        case .benutzer:
            if !userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await runUserSearch(force: true)
            }
            if let selectedUserID {
                await ensureUserDetailsLoaded(userID: selectedUserID, force: true)
            } else {
                await ensureBenutzerInitialLoad()
            }

        case .veranstaltungen:
            await loadEnrolledCourses(force: true)
            await loadCatalogCourses(force: true)
            await loadSelectedCatalogCourseDetail(force: true)

        case .einrichtungen:
            await loadInstitutions(force: true)
            await loadCoursesForSelectedInstitutionSemester(force: true)

        case .platzhalter:
            semesterViewModel.loadSemesters()
        }
    }
}
