import AppKit
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
    private var isConstrained = false

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.isSatisfied = path.status == .satisfied
            self.isWiFi = path.usesInterfaceType(.wifi)
            self.isConstrained = path.isConstrained
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

    var isEligibleForBackgroundSync: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSatisfied && isWiFi && !isConstrained
    }
}

enum SyncErrorCategory: String {
    case offline
    case unauthorized
    case configuration
    case serverTemporary
    case localAccess
    case unknown

    var isRetryable: Bool {
        switch self {
        case .offline, .serverTemporary:
            return true
        case .unauthorized, .configuration, .localAccess, .unknown:
            return false
        }
    }
}

struct SyncErrorClassification {
    let category: SyncErrorCategory
    let userMessage: String

    var isRetryable: Bool {
        category.isRetryable
    }
}

@MainActor
final class SyncScheduler {
    private enum RunTrigger {
        case scheduled
        case manual
    }

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
    private let maxImmediateRetries = 2
    private let retryBaseDelaySeconds = 2.0

    private var consecutiveIdleRuns = 0
    private var consecutiveFailures = 0

    private var configuredIntervalMinutes: Int?
    private var isSystemSleeping = false
    private var willSleepObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?

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
        registerSleepWakeObservers()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        if let willSleepObserver {
            center.removeObserver(willSleepObserver)
        }
        if let didWakeObserver {
            center.removeObserver(didWakeObserver)
        }
    }

    func start(intervalMinutes: Int) {
        let normalizedIntervalMinutes = max(minimumIntervalMinutes, intervalMinutes)
        configuredIntervalMinutes = normalizedIntervalMinutes
        let toleranceSeconds = scheduleToleranceSeconds(for: normalizedIntervalMinutes)

        AppLogger.info(
            "Sync scheduler started | interval=\(normalizedIntervalMinutes)m tolerance<=\(Int(toleranceSeconds))s"
        )

        launchLoop(intervalMinutes: normalizedIntervalMinutes, toleranceSeconds: toleranceSeconds, runImmediately: true)
    }

    func stop() {
        cancelLoop(clearConfiguration: true)
    }

    func triggerManualSync() {
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let feedback = await self.runSyncWithStatusUpdate(trigger: .manual)
            self.apply(feedback: feedback)
        }
    }

    private func launchLoop(intervalMinutes: Int, toleranceSeconds: Double, runImmediately: Bool) {
        cancelLoop(clearConfiguration: false)

        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            if runImmediately {
                let feedback = await self.runSyncWithStatusUpdate(trigger: .scheduled)
                self.apply(feedback: feedback)
            }

            while !Task.isCancelled {
                let delaySeconds = self.nextDelaySeconds(
                    intervalMinutes: intervalMinutes,
                    toleranceSeconds: toleranceSeconds
                )

                do {
                    try await Task.sleep(for: .seconds(delaySeconds))
                } catch {
                    return
                }

                if Task.isCancelled {
                    return
                }

                let feedback = await self.runSyncWithStatusUpdate(trigger: .scheduled)
                self.apply(feedback: feedback)
            }
        }
    }

    private func cancelLoop(clearConfiguration: Bool) {
        task?.cancel()
        task = nil
        if clearConfiguration {
            configuredIntervalMinutes = nil
        }
    }

    private func runSyncWithStatusUpdate(trigger: RunTrigger) async -> RunFeedback {
        if trigger != .manual {
            if isSystemSleeping {
                statusController?.setIdle()
                return .skipped
            }

            if shouldPauseForLowPowerMode() {
                statusController?.setIdle()
                AppLogger.info("Sync paused due to Low Power mode policy")
                return .skipped
            }

            if shouldPauseForWiFiPolicy() {
                statusController?.setOffline()
                AppLogger.info("Sync paused due to WiFi-only or Low-Data policy")
                return .skipped
            }
        }

        statusController?.setRunning()

        var retryAttempt = 0
        while true {
            do {
                let report = try await syncEngine.runSync()
                guard report.didRun else {
                    statusController?.setIdle()
                    return .skipped
                }

                statusController?.setSuccess()
                return report.hasChanges ? .successWithChanges : .successWithoutChanges
            } catch {
                let classification = classify(error)
                if classification.isRetryable, retryAttempt < maxImmediateRetries {
                    retryAttempt += 1
                    let retryDelay = retryDelaySeconds(forAttempt: retryAttempt)
                    AppLogger.error(
                        "Sync failed [\(classification.category.rawValue)] attempt=\(retryAttempt) retryIn=\(Int(retryDelay))s: \(classification.userMessage)"
                    )

                    do {
                        try await Task.sleep(for: .seconds(retryDelay))
                    } catch {
                        return .failure
                    }
                    continue
                }

                if classification.category == .offline {
                    statusController?.setOffline()
                } else {
                    statusController?.setError(classification.userMessage)
                }

                AppLogger.error("Sync failed [\(classification.category.rawValue)]: \(classification.userMessage)")
                return .failure
            }
        }
    }

    private func classify(_ error: Error) -> SyncErrorClassification {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return SyncErrorClassification(category: .offline, userMessage: "Offline: \(urlError.localizedDescription)")
            case .timedOut, .resourceUnavailable, .internationalRoamingOff:
                return SyncErrorClassification(category: .serverTemporary, userMessage: "Temporarer Netzwerkfehler: \(urlError.localizedDescription)")
            default:
                return SyncErrorClassification(category: .unknown, userMessage: urlError.localizedDescription)
            }
        }

        if let apiError = error as? StudIPAPIClient.APIClientError {
            switch apiError {
            case .missingCredentials:
                return SyncErrorClassification(category: .configuration, userMessage: "Fehlende Zugangsdaten. API-Key oder Login hinterlegen.")
            case .unauthorized:
                return SyncErrorClassification(category: .unauthorized, userMessage: "Autorisierung fehlgeschlagen. API-Key/Login pruefen.")
            case .sandboxNetworkPermissionMissing:
                return SyncErrorClassification(category: .configuration, userMessage: "Netzwerkzugriff in App-Sandbox aktivieren.")
            case .httpStatus(let code, _, _):
                if code == 401 || code == 403 {
                    return SyncErrorClassification(category: .unauthorized, userMessage: "HTTP \(code): Autorisierung fehlgeschlagen.")
                }
                if code == 408 || code == 425 || code == 429 || (500...599).contains(code) {
                    return SyncErrorClassification(category: .serverTemporary, userMessage: "HTTP \(code): temporarer Serverfehler.")
                }
                return SyncErrorClassification(category: .unknown, userMessage: "HTTP \(code): \(apiError.localizedDescription)")
            case .invalidPath, .invalidResponse:
                return SyncErrorClassification(category: .configuration, userMessage: apiError.localizedDescription)
            }
        }

        if let syncError = error as? SyncEngine.SyncEngineError {
            switch syncError {
            case .rootFolderNotConfigured:
                return SyncErrorClassification(category: .configuration, userMessage: syncError.localizedDescription)
            case .couldNotResolveRootFolder, .rootFolderNotAccessible:
                return SyncErrorClassification(category: .localAccess, userMessage: syncError.localizedDescription)
            case .activeSemesterSyncFailed(let failures):
                let mappedCategory = mapActiveSemesterFailureCategory(failures)
                return SyncErrorClassification(category: mappedCategory, userMessage: syncError.localizedDescription)
            case .missingDownloadedFilePayload:
                return SyncErrorClassification(category: .serverTemporary, userMessage: syncError.localizedDescription)
            }
        }

        return SyncErrorClassification(category: .unknown, userMessage: error.localizedDescription)
    }

    private func mapActiveSemesterFailureCategory(_ failures: [SyncEngine.ActiveSemesterFailure]) -> SyncErrorCategory {
        guard !failures.isEmpty else {
            return .unknown
        }

        let categories = Set(failures.map(\.category))
        if categories.count == 1, categories.contains(.offline) {
            return .offline
        }
        if categories.contains(.unauthorized) {
            return .unauthorized
        }
        if categories.contains(.configuration) {
            return .configuration
        }
        if categories.contains(.localAccess) {
            return .localAccess
        }
        if categories.contains(.serverTemporary) || categories.contains(.offline) {
            return .serverTemporary
        }
        return .unknown
    }

    private func retryDelaySeconds(forAttempt attempt: Int) -> Double {
        let exponent = Double(max(0, attempt - 1))
        return min(15.0, retryBaseDelaySeconds * pow(2, exponent))
    }

    private func shouldPauseForLowPowerMode() -> Bool {
        settingsStore.configuration.pauseSyncOnLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func shouldPauseForWiFiPolicy() -> Bool {
        settingsStore.configuration.syncOnlyOnWiFi && !networkMonitor.isEligibleForBackgroundSync
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

    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter

        willSleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor [strongSelf] in
                strongSelf.isSystemSleeping = true
                strongSelf.cancelLoop(clearConfiguration: false)
                strongSelf.statusController?.setIdle()
                AppLogger.info("System will sleep. Sync scheduler paused.")
            }
        }

        didWakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor [strongSelf] in
                strongSelf.isSystemSleeping = false
                guard let interval = strongSelf.configuredIntervalMinutes else { return }

                let tolerance = strongSelf.scheduleToleranceSeconds(for: interval)
                strongSelf.launchLoop(intervalMinutes: interval, toleranceSeconds: tolerance, runImmediately: true)
                AppLogger.info("System did wake. Sync scheduler resumed.")
            }
        }
    }
}
