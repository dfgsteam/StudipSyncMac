import Foundation
import CryptoKit

actor SharedCourseParticipationCache {
    struct SharedCourseEntry: Codable, Hashable, Identifiable {
        let courseID: String
        let courseTitle: String
        let semesterID: String?
        let semesterTitle: String?

        var id: String {
            "\(semesterID ?? "none"):\(courseID)"
        }
    }

    struct Snapshot: Codable {
        let ownerUserID: String
        let updatedAt: Date
        let version: Int
        let entriesByUserID: [String: [SharedCourseEntry]]
    }

    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let version = 1

    init(fileManager: FileManager = .default, cacheRootURL: URL? = nil) {
        self.fileManager = fileManager

        if let cacheRootURL {
            self.cacheDirectory = cacheRootURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.cacheDirectory = support.appendingPathComponent("StudipSync", isDirectory: true)
        }
    }

    func load(baseURL: URL, ownerUserID: String) throws -> Snapshot? {
        try ensureCacheDirectoryExists()
        let fileURL = cacheFileURL(baseURL: baseURL, ownerUserID: ownerUserID)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version == version else {
            return nil
        }
        return snapshot
    }

    func save(baseURL: URL, snapshot: Snapshot) throws {
        try ensureCacheDirectoryExists()
        let fileURL = cacheFileURL(baseURL: baseURL, ownerUserID: snapshot.ownerUserID)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func clearAll() throws {
        try ensureCacheDirectoryExists()
        let contents = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents where url.lastPathComponent.hasPrefix("shared-courses.") && url.pathExtension == "json" {
            try? fileManager.removeItem(at: url)
        }
    }

    private func cacheFileURL(baseURL: URL, ownerUserID: String) -> URL {
        let digest = SHA256.hash(
            data: Data("\(normalizedBaseURLString(baseURL))|\(canonicalStudIPID(ownerUserID))".utf8)
        )
        let stableKey = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("shared-courses.\(stableKey).json")
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
}
