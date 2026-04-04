import Foundation
import CryptoKit

actor MetadataCache {
    struct Snapshot: Codable {
        let semesters: [SemesterDTO]
        let coursesBySemesterID: [String: [CourseDTO]]
        let updatedAt: Date
        let version: Int

        init(
            semesters: [SemesterDTO],
            coursesBySemesterID: [String: [CourseDTO]] = [:],
            updatedAt: Date,
            version: Int
        ) {
            self.semesters = semesters
            self.coursesBySemesterID = coursesBySemesterID
            self.updatedAt = updatedAt
            self.version = version
        }

        enum CodingKeys: String, CodingKey {
            case semesters
            case coursesBySemesterID
            case updatedAt
            case version
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            semesters = try container.decode([SemesterDTO].self, forKey: .semesters)
            coursesBySemesterID = try container.decodeIfPresent([String: [CourseDTO]].self, forKey: .coursesBySemesterID) ?? [:]
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            version = try container.decode(Int.self, forKey: .version)
        }
    }

    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let version = 3

    init(fileManager: FileManager = .default, cacheRootURL: URL? = nil) {
        self.fileManager = fileManager

        if let cacheRootURL {
            self.cacheDirectory = cacheRootURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.cacheDirectory = support.appendingPathComponent("StudipSync", isDirectory: true)
        }
    }

    func load(baseURL: URL) async throws -> Snapshot? {
        try ensureCacheDirectoryExists()
        try migrateLegacyCacheIfNeeded(baseURL: baseURL)

        let url = cacheFileURL(for: baseURL)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version >= 1, snapshot.version <= version else {
            return nil
        }
        return snapshot
    }

    func save(semesters: [SemesterDTO], baseURL: URL) async throws {
        try ensureCacheDirectoryExists()
        try migrateLegacyCacheIfNeeded(baseURL: baseURL)

        let existingCourses = try await load(baseURL: baseURL)?.coursesBySemesterID ?? [:]
        let snapshot = Snapshot(
            semesters: semesters,
            coursesBySemesterID: existingCourses,
            updatedAt: Date(),
            version: version
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheFileURL(for: baseURL), options: .atomic)
        try cleanupLegacyCacheFiles(baseURL: baseURL)
    }

    func loadCourses(for semesterID: String, baseURL: URL) async throws -> [CourseDTO]? {
        guard let snapshot = try await load(baseURL: baseURL) else {
            return nil
        }

        let canonicalSemesterID = canonicalStudIPID(semesterID)
        if let courses = snapshot.coursesBySemesterID[canonicalSemesterID] {
            return courses
        }
        return snapshot.coursesBySemesterID[semesterID]
    }

    func saveCourses(_ courses: [CourseDTO], for semesterID: String, baseURL: URL) async throws {
        try ensureCacheDirectoryExists()
        try migrateLegacyCacheIfNeeded(baseURL: baseURL)

        let existing = try await load(baseURL: baseURL)
        let canonicalSemesterID = canonicalStudIPID(semesterID)

        var coursesBySemesterID = existing?.coursesBySemesterID ?? [:]
        coursesBySemesterID[canonicalSemesterID] = courses

        let snapshot = Snapshot(
            semesters: existing?.semesters ?? [],
            coursesBySemesterID: coursesBySemesterID,
            updatedAt: Date(),
            version: version
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheFileURL(for: baseURL), options: .atomic)
        try cleanupLegacyCacheFiles(baseURL: baseURL)
    }

    func clear(baseURL: URL) throws {
        try ensureCacheDirectoryExists()
        let url = cacheFileURL(for: baseURL)
        if fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
        }
        try cleanupLegacyCacheFiles(baseURL: baseURL)
    }

    private func cacheFileURL(for baseURL: URL) -> URL {
        let host = (baseURL.host ?? "default").lowercased()
        let stableKey = stableCacheKey(for: baseURL)
        return cacheDirectory.appendingPathComponent("metadata.\(host).\(stableKey).json")
    }

    private func stableCacheKey(for baseURL: URL) -> String {
        let normalizedBaseURL = normalizedBaseURLString(baseURL)
        let digest = SHA256.hash(data: Data(normalizedBaseURL.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func normalizedBaseURLString(_ baseURL: URL) -> String {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.absoluteString.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil

        var normalizedPath = components.path
        if normalizedPath != "/" {
            normalizedPath = normalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"
        }

        return components.string ?? baseURL.absoluteString.lowercased()
    }

    private func ensureCacheDirectoryExists() throws {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func migrateLegacyCacheIfNeeded(baseURL: URL) throws {
        let stableURL = cacheFileURL(for: baseURL)
        guard !fileManager.fileExists(atPath: stableURL.path()) else {
            try cleanupLegacyCacheFiles(baseURL: baseURL)
            return
        }

        let legacyURLs = try legacyCacheFileURLs(baseURL: baseURL)
        guard !legacyURLs.isEmpty else {
            return
        }

        let sourceURL = legacyURLs.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        } ?? legacyURLs[0]

        do {
            try fileManager.moveItem(at: sourceURL, to: stableURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: stableURL)
            try? fileManager.removeItem(at: sourceURL)
        }

        try cleanupLegacyCacheFiles(baseURL: baseURL)
    }

    private func cleanupLegacyCacheFiles(baseURL: URL) throws {
        let legacyURLs = try legacyCacheFileURLs(baseURL: baseURL)
        for url in legacyURLs {
            try? fileManager.removeItem(at: url)
        }
    }

    private func legacyCacheFileURLs(baseURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: cacheDirectory.path()) else {
            return []
        }

        let host = (baseURL.host ?? "default").lowercased()
        let prefix = "metadata.\(host)."
        let suffix = ".json"

        let contents = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return contents.filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
                return false
            }

            let payload = name.dropFirst(prefix.count).dropLast(suffix.count)
            guard !payload.isEmpty else {
                return false
            }

            // Legacy filenames used hashValue.magnitude (digits only).
            return payload.allSatisfy(\.isNumber)
        }
    }
}
