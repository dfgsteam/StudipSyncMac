import Foundation

@MainActor
final class SyncScheduler {
    private var task: Task<Void, Never>?
    private let syncEngine: SyncEngine
    private let statusController: MenuBarStatusController?
    private let minimumIntervalMinutes = 1
    private let minimumDelaySeconds = 5.0
    private let minimumToleranceSeconds = 15.0
    private let toleranceFactor = 0.2

    init(syncEngine: SyncEngine, statusController: MenuBarStatusController? = nil) {
        self.syncEngine = syncEngine
        self.statusController = statusController
    }

    func start(intervalMinutes: Int) {
        stop()
        let normalizedIntervalMinutes = max(minimumIntervalMinutes, intervalMinutes)
        let toleranceSeconds = scheduleToleranceSeconds(for: normalizedIntervalMinutes)
        AppLogger.info(
            "Sync scheduler started | interval=\(normalizedIntervalMinutes)m tolerance<=\(Int(toleranceSeconds))s"
        )

        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runSyncWithStatusUpdate()
            while !Task.isCancelled {
                do {
                    let delaySeconds = self.nextDelaySeconds(
                        intervalMinutes: normalizedIntervalMinutes,
                        toleranceSeconds: toleranceSeconds
                    )
                    try await Task.sleep(for: .seconds(delaySeconds))
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
        do {
            let didRun = try await syncEngine.runSync()
            if didRun {
                statusController?.setSuccess()
            }
        } catch let urlError as URLError {
            if urlError.code == .notConnectedToInternet
                || urlError.code == .networkConnectionLost
                || urlError.code == .cannotFindHost
                || urlError.code == .cannotConnectToHost {
                statusController?.setOffline()
            } else {
                statusController?.setError(urlError.localizedDescription)
            }
            AppLogger.error("Sync failed: \(urlError.localizedDescription)")
        } catch {
            statusController?.setError(error.localizedDescription)
            AppLogger.error("Sync failed: \(error.localizedDescription)")
        }
    }

    private func scheduleToleranceSeconds(for intervalMinutes: Int) -> Double {
        let baseSeconds = Double(intervalMinutes * 60)
        return max(minimumToleranceSeconds, baseSeconds * toleranceFactor)
    }

    private func nextDelaySeconds(intervalMinutes: Int, toleranceSeconds: Double) -> Double {
        let baseSeconds = Double(intervalMinutes * 60)
        let randomizedTolerance = Double.random(in: 0...toleranceSeconds)
        return max(minimumDelaySeconds, baseSeconds + randomizedTolerance)
    }
}
