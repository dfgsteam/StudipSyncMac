import Foundation
import OSLog

enum AppLogger {
    nonisolated private static let logger = Logger(subsystem: "StudipSync", category: "App")

    nonisolated static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    nonisolated static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    nonisolated static func secretRedacted(_ message: String) {
        logger.debug("\(message, privacy: .private(mask: .hash))")
    }
}
