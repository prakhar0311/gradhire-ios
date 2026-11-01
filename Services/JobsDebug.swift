import Foundation
import os

// MARK: - Jobs Debug Log (temporary)

/// Temporary: traces the Jobs tab's state changes in debug builds, to catch
/// the blank-tab report on a device. Remove once the fix is confirmed.
enum JobsDebug {

    #if DEBUG
    private static let logger = Logger(subsystem: "com.prakhar.gradhire", category: "JobsDebug")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.debug("[JobsDebug] \(text, privacy: .public)")
        #endif
    }
}
