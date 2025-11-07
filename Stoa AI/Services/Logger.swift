import Foundation
import os.log

/// Centralized logging system using OSLog
/// Replaces print() statements with proper structured logging
enum Logger {
    // MARK: - Subsystems
    private static let appSubsystem = "com.calendo.app"
    
    // MARK: - Loggers by Category
    static let app = OSLog(subsystem: appSubsystem, category: "App")
    static let notification = OSLog(subsystem: appSubsystem, category: "Notification")
    static let auth = OSLog(subsystem: appSubsystem, category: "Authentication")
    static let subscription = OSLog(subsystem: appSubsystem, category: "Subscription")
    static let firebase = OSLog(subsystem: appSubsystem, category: "Firebase")
    static let localization = OSLog(subsystem: appSubsystem, category: "Localization")
    static let habit = OSLog(subsystem: appSubsystem, category: "Habit")
    static let task = OSLog(subsystem: appSubsystem, category: "Task")
    static let chat = OSLog(subsystem: appSubsystem, category: "Chat")
    static let general = OSLog(subsystem: appSubsystem, category: "General")
    
    // MARK: - Log Levels
    
    /// Debug level: Detailed information for debugging (only visible in debug builds)
    static func debug(_ message: String, logger: OSLog = general, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        os_log("%{public}@", log: logger, type: .debug, logMessage)
        #endif
    }
    
    /// Info level: General informational messages
    static func info(_ message: String, logger: OSLog = general) {
        os_log("%{public}@", log: logger, type: .info, message)
    }
    
    /// Default level: Standard informational messages (default)
    static func log(_ message: String, logger: OSLog = general) {
        os_log("%{public}@", log: logger, type: .default, message)
    }
    
    /// Error level: Error conditions that don't prevent the app from functioning
    static func error(_ message: String, logger: OSLog = general, error: Error? = nil) {
        if let error = error {
            os_log("%{public}@ - Error: %{public}@", log: logger, type: .error, message, error.localizedDescription)
        } else {
            os_log("%{public}@", log: logger, type: .error, message)
        }
    }
    
    /// Fault level: Critical errors that may cause app to stop functioning
    static func fault(_ message: String, logger: OSLog = general, error: Error? = nil) {
        if let error = error {
            os_log("%{public}@ - Fault: %{public}@", log: logger, type: .fault, message, error.localizedDescription)
        } else {
            os_log("%{public}@", log: logger, type: .fault, message)
        }
    }
    
    /// Warning level: Warning conditions (custom extension using error level with warning prefix)
    static func warning(_ message: String, logger: OSLog = general) {
        os_log("⚠️ %{public}@", log: logger, type: .error, message)
    }
}

