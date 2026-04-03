import Foundation

enum RuntimeFlags {
    static var isDeveloperModeEnabled: Bool {
        #if DEBUG
        return true
        #else
        let env = ProcessInfo.processInfo.environment
        if env["STUDIPSYNC_DEV_MODE"] == "1" { return true }
        if ProcessInfo.processInfo.arguments.contains("--dev-mode") { return true }
        return false
        #endif
    }
}
