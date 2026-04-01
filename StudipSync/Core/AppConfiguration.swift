import Foundation

struct AppConfiguration: Codable, Equatable {
    var baseURL: URL
    var syncIntervalMinutes: Int
    var rootFolderBookmark: Data?
    var activeSemesterIDs: Set<String>

    static let `default` = AppConfiguration(
        baseURL: URL(string: "https://studip.example.edu")!,
        syncIntervalMinutes: 10,
        rootFolderBookmark: nil,
        activeSemesterIDs: []
    )
}
