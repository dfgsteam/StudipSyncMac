import Foundation
import Observation

@MainActor
@Observable
final class SemesterListViewModel {
    private(set) var semesters: [SemesterDTO] = []
    private(set) var isLoading = false
    private(set) var statusMessage = "Noch nicht geladen"

    private let repository: StudIPResourceRepository

    init(repository: StudIPResourceRepository) {
        self.repository = repository
    }

    func loadSemesters() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = "Lade Semester ..."

        Task {
            do {
                let result = try await repository.loadSemestersStaleWhileRevalidate { [weak self] refreshed in
                    self?.semesters = SemesterListViewModel.sortedForDisplay(refreshed)
                    self?.statusMessage = "Remote aktualisiert"
                }

                semesters = SemesterListViewModel.sortedForDisplay(result.semesters)
                statusMessage = result.source == .cache ? "Aus Cache geladen" : "Remote geladen"
                isLoading = false
            } catch let apiError as StudIPAPIClient.APIClientError {
                statusMessage = apiError.localizedDescription
                isLoading = false
            } catch {
                statusMessage = "Fehler beim Abruf: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private static func sortedForDisplay(_ semesters: [SemesterDTO]) -> [SemesterDTO] {
        semesters.sorted { lhs, rhs in
            let lhsStart = lhs.begin ?? lhs.startOfLectures ?? .distantPast
            let rhsStart = rhs.begin ?? rhs.startOfLectures ?? .distantPast

            if lhsStart != rhsStart {
                return lhsStart > rhsStart
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
