import Foundation
import Network

enum SyncSchedulePlanner {
    static func toleranceSeconds(
        intervalMinutes: Int,
        minimumToleranceSeconds: Double,
        toleranceFactor: Double
    ) -> Double {
        let baseSeconds = Double(intervalMinutes * 60)
        return max(minimumToleranceSeconds, baseSeconds * toleranceFactor)
    }

    static func nextDelaySeconds(
        intervalMinutes: Int,
        toleranceSeconds: Double,
        minimumDelaySeconds: Double,
        backoffMultiplier: Double,
        randomUnit: () -> Double = { Double.random(in: 0...1) }
    ) -> Double {
        let baseSeconds = Double(intervalMinutes * 60) * max(1.0, backoffMultiplier)
        let scaledTolerance = toleranceSeconds * min(max(1.0, backoffMultiplier), 2.0)
        let clampedUnit = min(max(randomUnit(), 0), 1)
        let signedJitter = (clampedUnit * 2 - 1) * scaledTolerance
        return max(minimumDelaySeconds, baseSeconds + signedJitter)
    }
}

enum SyncAdaptiveBackoffPlanner {
    static func multiplier(
        consecutiveIdleRuns: Int,
        consecutiveFailures: Int,
        idleStep: Double = 0.5,
        maxIdleMultiplier: Double = 3.0,
        maxFailureMultiplier: Double = 8.0
    ) -> Double {
        let idleMultiplier = min(maxIdleMultiplier, 1.0 + (Double(max(0, consecutiveIdleRuns)) * idleStep))
        let failureExponent = min(max(0, consecutiveFailures), 3)
        let failureMultiplier = min(maxFailureMultiplier, pow(2.0, Double(failureExponent)))
        return max(idleMultiplier, failureMultiplier)
    }
}

final class SyncNetworkMonitor {
    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "StudipSync.SyncNetworkMonitor")
    private let lock = NSLock()

    private var isSatisfied = false
    private var isWiFi = false

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.isSatisfied = path.status == .satisfied
            self.isWiFi = path.usesInterfaceType(.wifi)
            self.lock.unlock()
        }

        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    var isConnectedViaWiFi: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSatisfied && isWiFi
    }
}

@MainActor
final class SyncScheduler {
    private enum RunFeedback {
        case successWithChanges
        case successWithoutChanges
        case skipped
        case failure
    }

    private var task: Task<Void, Never>?
    private let syncEngine: SyncEngine
    private let statusController: MenuBarStatusController?
    private let settingsStore: SettingsStore
    private let networkMonitor: SyncNetworkMonitor

    private let minimumIntervalMinutes = 1
    private let minimumDelaySeconds = 5.0
    private let minimumToleranceSeconds = 15.0
    private let toleranceFactor = 0.2

    private var consecutiveIdleRuns = 0
    private var consecutiveFailures = 0

    init(
        syncEngine: SyncEngine,
        statusController: MenuBarStatusController? = nil,
        settingsStore: SettingsStore,
        networkMonitor: SyncNetworkMonitor = SyncNetworkMonitor()
    ) {
        self.syncEngine = syncEngine
        self.statusController = statusController
        self.settingsStore = settingsStore
        self.networkMonitor = networkMonitor
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

            while !Task.isCancelled {
                let feedback = await self.runSyncWithStatusUpdate()
                await self.apply(feedback: feedback)

                if Task.isCancelled {
                    return
                }

                let delaySeconds = await self.nextDelaySeconds(
                    intervalMinutes: normalizedIntervalMinutes,
                    toleranceSeconds: toleranceSeconds
                )

                do {
                    try await Task.sleep(for: .seconds(delaySeconds))
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
            let feedback = await self.runSyncWithStatusUpdate()
            await self.apply(feedback: feedback)
        }
    }

    private func runSyncWithStatusUpdate() async -> RunFeedback {
        if shouldPauseForLowPowerMode() {
            statusController?.setIdle()
            AppLogger.info("Sync paused due to Low Power mode policy")
            return .skipped
        }

        if shouldPauseForWiFiPolicy() {
            statusController?.setOffline()
            AppLogger.info("Sync paused due to WiFi-only policy")
            return .skipped
        }

        statusController?.setRunning()

        do {
            let report = try await syncEngine.runSync()
            guard report.didRun else {
                statusController?.setIdle()
                return .skipped
            }

            statusController?.setSuccess()
            return report.hasChanges ? .successWithChanges : .successWithoutChanges
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
            return .failure
        } catch {
            statusController?.setError(error.localizedDescription)
            AppLogger.error("Sync failed: \(error.localizedDescription)")
            return .failure
        }
    }

    private func shouldPauseForLowPowerMode() -> Bool {
        settingsStore.configuration.pauseSyncOnLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func shouldPauseForWiFiPolicy() -> Bool {
        settingsStore.configuration.syncOnlyOnWiFi && !networkMonitor.isConnectedViaWiFi
    }

    private func apply(feedback: RunFeedback) {
        switch feedback {
        case .successWithChanges:
            consecutiveIdleRuns = 0
            consecutiveFailures = 0
        case .successWithoutChanges:
            consecutiveIdleRuns = min(consecutiveIdleRuns + 1, 8)
            consecutiveFailures = 0
        case .failure:
            consecutiveFailures = min(consecutiveFailures + 1, 8)
            consecutiveIdleRuns = 0
        case .skipped:
            break
        }
    }

    private func scheduleToleranceSeconds(for intervalMinutes: Int) -> Double {
        SyncSchedulePlanner.toleranceSeconds(
            intervalMinutes: intervalMinutes,
            minimumToleranceSeconds: minimumToleranceSeconds,
            toleranceFactor: toleranceFactor
        )
    }

    private func nextDelaySeconds(intervalMinutes: Int, toleranceSeconds: Double) -> Double {
        let backoffMultiplier = SyncAdaptiveBackoffPlanner.multiplier(
            consecutiveIdleRuns: consecutiveIdleRuns,
            consecutiveFailures: consecutiveFailures
        )

        let delay = SyncSchedulePlanner.nextDelaySeconds(
            intervalMinutes: intervalMinutes,
            toleranceSeconds: toleranceSeconds,
            minimumDelaySeconds: minimumDelaySeconds,
            backoffMultiplier: backoffMultiplier
        )
        let backoffText = String(format: "%.2f", backoffMultiplier)

        AppLogger.info(
            "Sync next run in \(Int(delay))s | idleRuns=\(consecutiveIdleRuns) failures=\(consecutiveFailures) backoff=\(backoffText)"
        )

        return delay
    }
}
