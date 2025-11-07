import Foundation
import UserNotifications
import os.log

/// Centralized badge management service
/// Handles all badge count operations to avoid duplication
@Observable final class BadgeManager {
    static let shared = BadgeManager()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private init() {
        Logger.info("BadgeManager initialized", logger: Logger.notification)
    }
    
    // MARK: - Badge Count Operations
    
    /// Reset badge count to zero
    func resetBadgeCount(completion: ((Error?) -> Void)? = nil) {
        setBadgeCount(0, completion: completion)
    }
    
    /// Set badge count to a specific value
    func setBadgeCount(_ count: Int, completion: ((Error?) -> Void)? = nil) {
        notificationCenter.setBadgeCount(count, withCompletionHandler: completion ?? { _ in })
    }
    
    /// Get current badge count from the system
    func getCurrentBadgeCount(completion: @escaping (Int) -> Void) {
        notificationCenter.getDeliveredNotifications { notifications in
            // Badge count is typically managed by the system, 
            // but we can infer from delivered notifications if needed
            DispatchQueue.main.async {
                completion(notifications.count)
            }
        }
    }
}

