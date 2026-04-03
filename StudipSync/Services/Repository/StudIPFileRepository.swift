import Foundation

actor StudIPFileRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func fetchTermsOfUse() async throws -> [TermsOfUseDTO] {
        let data = try await apiClient.performRequest(path: "/v1/terms-of-use")
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "terms-of-use", "collection", "items"])
    }

    func fetchTermsOfUse(id: String) async throws -> TermsOfUseDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/terms-of-use/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "terms-of-use", "item"])
    }

    func fetchFileRefs(scope: StudIPContainerScope, offset: Int = 0, limit: Int = 30) async throws -> [CourseFileRefDTO] {
        let path = StudIPRepositoryUtilities.makeScopedPath(scope: scope, suffix: "file-refs")
        let data = try await apiClient.performRequest(
            path: path,
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "file-refs", "files", "collection", "items"])
    }

    func fetchFolders(scope: StudIPContainerScope, offset: Int = 0, limit: Int = 30) async throws -> [FolderDTO] {
        let path = StudIPRepositoryUtilities.makeScopedPath(scope: scope, suffix: "folders")
        let data = try await apiClient.performRequest(
            path: path,
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "folders", "collection", "items"])
    }

    func fetchFileRef(id: String) async throws -> CourseFileRefDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/file-refs/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "file-refs", "item"])
    }

    func updateFileRef(id: String, attributes: FileRefPatchAttributesDTO) async throws -> CourseFileRefDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<FileRefPatchAttributesDTO, JSONAPIEmptyDTO>(
                type: "file-refs",
                id: id,
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/file-refs/\(escapedID)",
            method: .patch,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "file-refs", "item"])
    }

    func deleteFileRef(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/file-refs/\(escapedID)", method: .delete)
    }

    func fetchFolder(id: String) async throws -> FolderDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/folders/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "folders", "item"])
    }

    func updateFolder(id: String, attributes: FolderPatchAttributesDTO) async throws -> FolderDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let payload = JSONAPIWriteDocument(
            data: JSONAPIWriteData<FolderPatchAttributesDTO, JSONAPIEmptyDTO>(
                type: "folders",
                id: id,
                attributes: attributes,
                relationships: nil
            )
        )

        let data = try await apiClient.performRequest(
            path: "/v1/folders/\(escapedID)",
            method: .patch,
            body: payload
        )

        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "folders", "item"])
    }

    func deleteFolder(id: String) async throws {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        _ = try await apiClient.performRequest(path: "/v1/folders/\(escapedID)", method: .delete)
    }

    func fetchFolderFileRefs(folderID: String, offset: Int = 0, limit: Int = 30) async throws -> [CourseFileRefDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(folderID)
        let data = try await apiClient.performRequest(
            path: "/v1/folders/\(escapedID)/file-refs",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "file-refs", "files", "collection", "items"])
    }

    func fetchFolderFolders(folderID: String, offset: Int = 0, limit: Int = 30) async throws -> [FolderDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(folderID)
        let data = try await apiClient.performRequest(
            path: "/v1/folders/\(escapedID)/folders",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "folders", "collection", "items"])
    }

    func fetchFileContent(fileRefID: String, fallbackDownloadPath: String? = nil) async throws -> Data {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(fileRefID)
        do {
            return try await apiClient.performRequest(
                path: "/v1/file-refs/\(escapedID)/content",
                method: .get,
                acceptHeader: "*/*"
            )
        } catch let contentError {
            guard let fallbackDownloadPath = fallbackDownloadPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !fallbackDownloadPath.isEmpty else {
                throw contentError
            }

            AppLogger.info("File content endpoint failed for \(escapedID), trying fallback download path.")

            do {
                return try await apiClient.performRawPathRequest(
                    path: fallbackDownloadPath,
                    method: .get,
                    acceptHeader: "*/*"
                )
            } catch let fallbackError {
                throw NSError(
                    domain: "StudIPFileRepository",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Dateidownload fehlgeschlagen. content: \(contentError.localizedDescription) | fallback: \(fallbackError.localizedDescription)"
                    ]
                )
            }
        }
    }

    func headFileContent(fileRefID: String) async throws -> StudIPHTTPResponse {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(fileRefID)
        return try await apiClient.performRequestWithResponse(
            path: "/v1/file-refs/\(escapedID)/content",
            method: .head,
            acceptHeader: nil
        )
    }
}
