import Foundation

@MainActor
final class SyncScheduler {
    private var task: Task<Void, Never>?
    private let syncEngine: SyncEngine

    init(syncEngine: SyncEngine) {
        self.syncEngine = syncEngine
    }

    func start(intervalMinutes: Int) {
        stop()

        task = Task(priority: .utility) { [syncEngine] in
            await syncEngine.runSync()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Double(intervalMinutes * 60)))
                    await syncEngine.runSync()
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func triggerManualSync() {
        Task(priority: .userInitiated) {
            await syncEngine.runSync()
        }
    }
}
