import Foundation

enum SyncState: Equatable {
    case idle
    case running
    case success(Date)
    case error(String)
    case offline

    var statusTitle: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .success:
            return "Success"
        case .error:
            return "Error"
        case .offline:
            return "Offline"
        }
    }

    var statusDetail: String? {
        switch self {
        case .error(let message):
            return message
        default:
            return nil
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Synchronizing"
        case .success(let date):
            return "Last successful sync: \(date.formatted(date: .abbreviated, time: .shortened))"
        case .error(let message):
            return "Error: \(message)"
        case .offline:
            return "Offline"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle"
        case .error:
            return "xmark.circle"
        case .offline:
            return "wifi.slash"
        }
    }
}
