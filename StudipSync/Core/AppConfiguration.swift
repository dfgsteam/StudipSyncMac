import Foundation

struct AppConfiguration: Codable, Equatable {
    var baseURL: URL
    var syncIntervalMinutes: Int
    var rootFolderBookmark: Data?
    var activeSemesterIDs: Set<String>
    var semesterSearchStartDate: Date?
    var semesterSearchEndDate: Date?

    static let `default` = AppConfiguration(
        baseURL: URL(string: "https://studip.uni-goettingen.de")!,
        syncIntervalMinutes: 10,
        rootFolderBookmark: nil,
        activeSemesterIDs: [],
        semesterSearchStartDate: nil,
        semesterSearchEndDate: nil
    )
}
