import Foundation

actor MetadataCache {
    struct Snapshot: Codable {
        let semesters: [SemesterDTO]
        let updatedAt: Date
        let version: Int
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

    func load(baseURL: URL) async throws -> Snapshot? {
        let url = cacheFileURL(for: baseURL)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        return snapshot.version == version ? snapshot : nil
    }

    func save(semesters: [SemesterDTO], baseURL: URL) async throws {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let snapshot = Snapshot(semesters: semesters, updatedAt: Date(), version: version)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheFileURL(for: baseURL), options: .atomic)
    }

    func clear(baseURL: URL) throws {
        let url = cacheFileURL(for: baseURL)
        if fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
        }
    }

    private func cacheFileURL(for baseURL: URL) -> URL {
        let host = (baseURL.host ?? "default").lowercased()
        let pathHash = String(baseURL.path.hashValue.magnitude)
        return cacheDirectory.appendingPathComponent("metadata.\(host).\(pathHash).json")
    }
}
