import Foundation
import Observation

@MainActor
@Observable
final class MenuBarStatusController {
    private(set) var syncState: SyncState = .idle

    func setRunning() {
        syncState = .running
    }

    func setSuccess() {
        syncState = .success(Date())
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
