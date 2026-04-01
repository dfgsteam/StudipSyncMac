import Foundation

actor SyncEngine {
    private var isRunning = false

    func runSync() async {
        guard !isRunning else {
            AppLogger.info("Sync skipped because another run is in progress")
            return
        }

        isRunning = true
        defer { isRunning = false }

        AppLogger.info("Sync run started")
        do {
            try await Task.sleep(for: .seconds(1))
            AppLogger.info("Sync run completed")
        } catch {
            AppLogger.error("Sync run interrupted: \(error.localizedDescription)")
        }
    }
}
