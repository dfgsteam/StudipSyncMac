import Foundation

actor StudIPPlannerRepository {
    private let apiClient: StudIPAPIClient
    private let responseDecoder: StudIPResponseDecoder

    init(apiClient: StudIPAPIClient, responseDecoder: StudIPResponseDecoder = StudIPResponseDecoder()) {
        self.apiClient = apiClient
        self.responseDecoder = responseDecoder
    }

    func fetchUserEvents(userID: String, timestamp: Int? = nil) async throws -> [EventDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(userID)
        var queryItems: [URLQueryItem] = []
        if let timestamp {
            queryItems.append(URLQueryItem(name: "filter[timestamp]", value: String(timestamp)))
        }

        let data = try await apiClient.performRequest(path: "/v1/users/\(escapedID)/events", queryItems: queryItems)
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "events", "collection", "items"])
    }

    func fetchUserEventsICS(userID: String) async throws -> String {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(userID)
        let data = try await apiClient.performRequest(
            path: "/v1/users/\(escapedID)/events.ics",
            method: .get,
            acceptHeader: "text/calendar,*/*"
        )

        return String(data: data, encoding: .utf8) ?? ""
    }

    func fetchCourseEvents(courseID: String, offset: Int = 0, limit: Int = 30) async throws -> [EventDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(courseID)
        let data = try await apiClient.performRequest(
            path: "/v1/courses/\(escapedID)/events",
            queryItems: StudIPRepositoryUtilities.pageQueryItems(offset: offset, limit: limit)
        )

        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "events", "collection", "items"])
    }

    func fetchUserSchedule(userID: String, timestamp: Int? = nil) async throws -> [ScheduleEntryDTO] {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(userID)
        var queryItems: [URLQueryItem] = []
        if let timestamp {
            queryItems.append(URLQueryItem(name: "filter[timestamp]", value: String(timestamp)))
        }

        let data = try await apiClient.performRequest(path: "/v1/users/\(escapedID)/schedule", queryItems: queryItems)
        return try responseDecoder.parseCollection(from: data, fallbackCollectionKeys: ["data", "schedule", "schedule-entries", "collection", "items"])
    }

    func fetchScheduleEntry(id: String) async throws -> ScheduleEntryDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/schedule-entries/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "schedule-entries", "item"])
    }

    func fetchSeminarCycleDate(id: String) async throws -> SeminarCycleDateDTO {
        let escapedID = StudIPRepositoryUtilities.escapedPathID(id)
        let data = try await apiClient.performRequest(path: "/v1/seminar-cycle-dates/\(escapedID)")
        return try responseDecoder.parseEntity(from: data, fallbackObjectKeys: ["data", "seminar-cycle-dates", "item"])
    }
}
