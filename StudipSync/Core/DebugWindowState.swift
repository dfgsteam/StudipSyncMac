import Foundation
import Observation

struct SearchDebugEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let context: String
    let query: String
    let curl: String
    let errorMessage: String
}

@MainActor
@Observable
final class DebugWindowState {
    var semesterID: String?
    var courseID: String?
    var searchDebugEntries: [SearchDebugEntry] = []

    var requestKey: String {
        "\(semesterID ?? "none")::\(courseID ?? "none")"
    }

    func updateSelection(semesterID: String?, courseID: String?) {
        self.semesterID = semesterID
        self.courseID = courseID
    }

    func recordSearchFailure(context: String, query: String?, curl: String?, errorMessage: String) {
        let trimmedError = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedError.isEmpty else { return }

        let entry = SearchDebugEntry(
            timestamp: Date(),
            context: context,
            query: query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            curl: curl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "<kein cURL verfuegbar>",
            errorMessage: trimmedError
        )

        searchDebugEntries.insert(entry, at: 0)
        if searchDebugEntries.count > 20 {
            searchDebugEntries.removeLast(searchDebugEntries.count - 20)
        }
    }

    func clearSearchFailures() {
        searchDebugEntries.removeAll()
    }
}
