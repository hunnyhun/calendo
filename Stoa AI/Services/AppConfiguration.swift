import Foundation

/// Centralized app configuration values
/// Makes delays and other constants configurable
enum AppConfiguration {
    enum Delays {
        /// Delay before running badge count diagnostic (allows Firestore updates to complete)
        static var diagnosticDelay: TimeInterval {
            // Could be made configurable via UserDefaults or remote config
            UserDefaults.standard.object(forKey: "diagnosticDelay") as? TimeInterval ?? 3.0
        }
        
        /// Delay before opening daily quote view after notification tap
        static var notificationOpenDelay: TimeInterval {
            UserDefaults.standard.object(forKey: "notificationOpenDelay") as? TimeInterval ?? 0.5
        }
    }
    
    enum NotificationNames {
        static let openDailyQuoteView = "OpenDailyQuoteView"
        static let userStateChanged = "UserStateChanged"
    }
    
    enum Badge {
        static let resetValue = 0
    }
    
    enum Auth {
        /// Maximum retries for device registration after authentication
        static let maxDeviceRegistrationRetries = 10
        
        /// Delay between retry attempts for device registration (in seconds)
        static let deviceRegistrationRetryDelay: TimeInterval = 0.2
        
        /// Length of nonce string for Apple Sign In
        static let nonceLength = 32
    }
}

