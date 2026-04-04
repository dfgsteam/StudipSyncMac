import Foundation

struct AppConfiguration: Codable, Equatable {
    var baseURL: URL
    var syncIntervalMinutes: Int
    var maxConcurrentFileDownloads: Int
    var pauseSyncOnLowPowerMode: Bool
    var syncOnlyOnWiFi: Bool
    var rootFolderBookmark: Data?
    var activeSemesterIDs: Set<String>
    var semesterSearchStartDate: Date?
    var semesterSearchEndDate: Date?

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case syncIntervalMinutes
        case maxConcurrentFileDownloads
        case pauseSyncOnLowPowerMode
        case syncOnlyOnWiFi
        case rootFolderBookmark
        case activeSemesterIDs
        case semesterSearchStartDate
        case semesterSearchEndDate
    }

    static let `default` = AppConfiguration(
        baseURL: URL(string: "https://studip.uni-goettingen.de")!,
        syncIntervalMinutes: 10,
        maxConcurrentFileDownloads: 3,
        pauseSyncOnLowPowerMode: false,
        syncOnlyOnWiFi: false,
        rootFolderBookmark: nil,
        activeSemesterIDs: [],
        semesterSearchStartDate: nil,
        semesterSearchEndDate: nil
    )

    init(
        baseURL: URL,
        syncIntervalMinutes: Int,
        maxConcurrentFileDownloads: Int,
        pauseSyncOnLowPowerMode: Bool,
        syncOnlyOnWiFi: Bool,
        rootFolderBookmark: Data?,
        activeSemesterIDs: Set<String>,
        semesterSearchStartDate: Date?,
        semesterSearchEndDate: Date?
    ) {
        self.baseURL = baseURL
        self.syncIntervalMinutes = syncIntervalMinutes
        self.maxConcurrentFileDownloads = min(4, max(2, maxConcurrentFileDownloads))
        self.pauseSyncOnLowPowerMode = pauseSyncOnLowPowerMode
        self.syncOnlyOnWiFi = syncOnlyOnWiFi
        self.rootFolderBookmark = rootFolderBookmark
        self.activeSemesterIDs = activeSemesterIDs
        self.semesterSearchStartDate = semesterSearchStartDate
        self.semesterSearchEndDate = semesterSearchEndDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfiguration.default
        let baseURL = try container.decode(URL.self, forKey: .baseURL)
        let syncIntervalMinutes = try container.decode(Int.self, forKey: .syncIntervalMinutes)
        let maxConcurrentFileDownloads = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentFileDownloads)
            ?? defaults.maxConcurrentFileDownloads
        let pauseSyncOnLowPowerMode = try container.decodeIfPresent(Bool.self, forKey: .pauseSyncOnLowPowerMode)
            ?? defaults.pauseSyncOnLowPowerMode
        let syncOnlyOnWiFi = try container.decodeIfPresent(Bool.self, forKey: .syncOnlyOnWiFi)
            ?? defaults.syncOnlyOnWiFi
        let rootFolderBookmark = try container.decodeIfPresent(Data.self, forKey: .rootFolderBookmark)
        let activeSemesterIDs = try container.decodeIfPresent(Set<String>.self, forKey: .activeSemesterIDs) ?? []
        let semesterSearchStartDate = try container.decodeIfPresent(Date.self, forKey: .semesterSearchStartDate)
        let semesterSearchEndDate = try container.decodeIfPresent(Date.self, forKey: .semesterSearchEndDate)

        self.init(
            baseURL: baseURL,
            syncIntervalMinutes: syncIntervalMinutes,
            maxConcurrentFileDownloads: maxConcurrentFileDownloads,
            pauseSyncOnLowPowerMode: pauseSyncOnLowPowerMode,
            syncOnlyOnWiFi: syncOnlyOnWiFi,
            rootFolderBookmark: rootFolderBookmark,
            activeSemesterIDs: activeSemesterIDs,
            semesterSearchStartDate: semesterSearchStartDate,
            semesterSearchEndDate: semesterSearchEndDate
        )
    }
}
