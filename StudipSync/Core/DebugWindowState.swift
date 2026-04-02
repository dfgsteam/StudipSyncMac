import Foundation
import Observation

@MainActor
@Observable
final class DebugWindowState {
    var semesterID: String?
    var courseID: String?

    var requestKey: String {
        "\(semesterID ?? "none")::\(courseID ?? "none")"
    }

    func updateSelection(semesterID: String?, courseID: String?) {
        self.semesterID = semesterID
        self.courseID = courseID
    }
}
