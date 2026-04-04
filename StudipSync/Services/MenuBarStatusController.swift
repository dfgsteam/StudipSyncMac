import Foundation
import Observation

@MainActor
@Observable
final class MenuBarStatusController {
    private(set) var syncState: SyncState = .idle
    private(set) var lastSuccessfulSyncAt: Date?

    var statusLineText: String {
        "Status: \(syncState.statusTitle)"
    }

    var statusDetailText: String? {
        syncState.statusDetail
    }

    var lastSuccessfulSyncLineText: String {
        if let date = lastSuccessfulSyncAt {
            return "Letzter erfolgreicher Sync: \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Letzter erfolgreicher Sync: noch keiner"
    }

    func setRunning() {
        syncState = .running
    }

    func setSuccess() {
        let now = Date()
        lastSuccessfulSyncAt = now
        syncState = .success(now)
    }

    func setError(_ message: String) {
        syncState = .error(message)
    }

    func setOffline() {
        syncState = .offline
    }

    func setIdle() {
        syncState = .idle
    }
}
