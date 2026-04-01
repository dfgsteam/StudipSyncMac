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
                    self?.semesters = refreshed
                    self?.statusMessage = "Remote aktualisiert"
                }

                semesters = result.semesters
                statusMessage = result.source == .cache ? "Aus Cache geladen" : "Remote geladen"
                isLoading = false
            } catch {
                statusMessage = "Fehler: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
