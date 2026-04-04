import Foundation

enum StudIPCourseRawSection: String {
    case files
    case chat
    case wiki
    case participants
    case forum
}

enum StudIPSemesterDataSource: String {
    case cache
    case remote
}

struct StudIPSemesterLoadResult {
    let semesters: [SemesterDTO]
    let source: StudIPSemesterDataSource
}

struct StudIPCourseLoadResult {
    let courses: [CourseDTO]
    let source: StudIPSemesterDataSource
}

enum StudIPRepositoryError: LocalizedError {
    case invalidPayloadPreview(String)
    case noCoursesForSemester(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayloadPreview(let preview):
            return "Unbekanntes Antwortformat. Preview: \(preview)"
        case .noCoursesForSemester(let semesterID):
            return "Keine Kurse fuer Semester \(semesterID) gefunden."
        }
    }
}

struct StudIPCourseParticipant: Identifiable, Hashable {
    let id: String
    let userID: String
    let displayName: String
    let email: String?
    let permission: String?
    let position: Int?
    let group: Int?
    let label: String?
    let mkdate: String?
}

struct StudIPCourseFileRef: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let ownerName: String?
    let mimeType: String?
    let downloads: Int?
    let fileSize: Int?
    let createdAt: Date?
    let changedAt: Date?
    let isReadable: Bool?
    let isDownloadable: Bool?
    let downloadURL: URL?
}

struct StudIPCourseChatThread: Identifiable, Hashable {
    let id: String
    let name: String
    let previewText: String?
    let contextType: String?
    let latestActivity: Date?
    let visitedAt: Date?
    let createdAt: Date?
    let changedAt: Date?
    let isCommentable: Bool?
    let isReadable: Bool?
    let isWritable: Bool?
    let isFollowed: Bool?
    let unseenComments: Int?
    let authorID: String?
    let avatarURL: URL?
}

struct StudIPCourseWikiPage: Identifiable, Hashable {
    let id: String
    let keyword: String
    let content: String?
    let changedAt: Date?
    let version: Int?
    let authorID: String?
    let authorName: String?
}
