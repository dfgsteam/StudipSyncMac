import Foundation

@MainActor
final class SyncScheduler {
    private var task: Task<Void, Never>?
    private let syncEngine: SyncEngine
    private let statusController: MenuBarStatusController?

    init(syncEngine: SyncEngine, statusController: MenuBarStatusController? = nil) {
        self.syncEngine = syncEngine
        self.statusController = statusController
    }

    func start(intervalMinutes: Int) {
        stop()

        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runSyncWithStatusUpdate()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Double(intervalMinutes * 60)))
                    await self.runSyncWithStatusUpdate()
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
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runSyncWithStatusUpdate()
        }
    }

    private func runSyncWithStatusUpdate() async {
        statusController?.setRunning()
        await syncEngine.runSync()
        statusController?.setSuccess()
    }
}
