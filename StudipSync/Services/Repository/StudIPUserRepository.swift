import Foundation

actor StudIPUserRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder
    private var cachedCurrentUserID: String?
    private var cachedUsersByID: [String: UserDTO] = [:]

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func warmupCurrentUserID() async {
        do {
            _ = try await ensureCurrentUserID()
        } catch {
            AppLogger.error("Current user warmup failed: \(error.localizedDescription)")
        }
    }

    func ensureCurrentUserID() async throws -> String {
        if let cachedCurrentUserID, !cachedCurrentUserID.isEmpty {
            return cachedCurrentUserID
        }

        let me = try await fetchUserProfile(id: "me")
        let id = canonicalStudIPID(me.id)
        cachedCurrentUserID = id
        return id
    }

    func fetchUserProfile(id: String) async throws -> UserDTO {
        let normalizedID = canonicalStudIPID(id)
        if let cached = cachedUsersByID[normalizedID] {
            return cached
        }

        let user = try await fetchOne(StudIPQuery<UserResource>().byID(normalizedID))
        cachedUsersByID[normalizedID] = user
        return user
    }

    func fetchUsers(userIDs: [String]) async -> [String: UserDTO] {
        var usersByID: [String: UserDTO] = [:]
        usersByID.reserveCapacity(userIDs.count)

        for userID in userIDs {
            do {
                usersByID[userID] = try await fetchUserProfile(id: userID)
            } catch {
                AppLogger.error("Failed to load user profile \(userID): \(error.localizedDescription)")
            }
        }

        return usersByID
    }

    private func fetchOne<Resource: StudIPResourceDescriptor>(_ query: StudIPQuery<Resource>) async throws -> Resource.Model {
        let data = try await apiClient.performRequest(path: query.path, queryItems: query.queryItems)
        return try responseDecoder.parseEntity(
            from: data,
            fallbackObjectKeys: Resource.fallbackCollectionKeys + ["data", "item"]
        )
    }
}
