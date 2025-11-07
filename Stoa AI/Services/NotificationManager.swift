import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import os.log
// Rule: Always add debug logs for easier debug

// MARK: - Notification Manager
@Observable final class NotificationManager {
    // Rule: Always add debug logs
    
    // Singleton instance
    static let shared = NotificationManager()
    
    // Properties
    var isNotificationsEnabled = false
    var unreadNotificationCount = 0 // Track number of unread notifications
    private let db = Firestore.firestore()
    
    // Store FCM tokens that arrive before user authentication
    private var pendingFCMTokens: Set<String> = []
    
    // MARK: - Initialization
    private init() {
        // Load saved states
        loadNotificationStatus()
        loadUnreadNotificationCount()
        
        // Debug log for initialization
        Logger.debug("Initialized with unread count: \(unreadNotificationCount)", logger: Logger.notification)
        
        // Register for app lifecycle notifications to help manage badge state
        NotificationCenter.default.addObserver(self, 
                                           selector: #selector(handleAppDidBecomeActive), 
                                           name: UIApplication.didBecomeActiveNotification, 
                                           object: nil)
        
        // Add observer for app entering background to ensure badge count is synchronized
        NotificationCenter.default.addObserver(self, 
                                           selector: #selector(handleAppDidEnterBackground), 
                                           name: UIApplication.didEnterBackgroundNotification, 
                                           object: nil)
        
        // Check notification status on init to ensure we have the correct state
        Task {
            _ = await checkNotificationStatus()
        }
        
        // Add auth state change observer to create user when logging in
        NotificationCenter.default.addObserver(self,
                                           selector: #selector(handleUserStateChanged),
                                           name: Notification.Name("UserStateChanged"),
                                           object: nil)
    }
    
    // MARK: - User Management
    @objc private func handleUserStateChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let authStatus = userInfo["authStatus"] as? String,
              authStatus == "authenticated",
              let userId = userInfo["userId"] as? String else {
            return
        }
        
        // User just logged in, ensure user document exists
        createUserDocumentIfNeeded(userId: userId)
    }
    
    // Create a user document in Firestore if it doesn't exist
    private func createUserDocumentIfNeeded(userId: String) {
        let userDocRef = db.collection("users").document(userId)
        
        Logger.debug("Ensuring user document exists for userId: \(userId)", logger: Logger.notification)
        
        // Check if document exists
        userDocRef.getDocument { (document, error) in
            if let error = error {
                Logger.debug("Error checking user document: \(error.localizedDescription)", logger: Logger.notification)
                return
            }
            
            if let document = document, document.exists {
                Logger.debug("User document already exists", logger: Logger.notification)
            } else {
                // Create user document with basic information
                let userData: [String: Any] = [
                    "userId": userId,
                    "email": UserStatusManager.shared.userEmail ?? "",
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastSeen": FieldValue.serverTimestamp(),
                    "notificationsEnabled": self.isNotificationsEnabled
                ]
                
                userDocRef.setData(userData) { error in
                    if let error = error {
                        Logger.error("Error creating user document", logger: Logger.notification, error: error)
                    } else {
                        Logger.debug("User document created successfully", logger: Logger.notification)
                        
                        // Process any pending device tokens
                        self.processPendingDeviceTokens()
                        
                        // Also register current token if available
                        if let token = self.getCurrentFCMToken() {
                            self.updateDeviceToken(token, forceEnabled: self.isNotificationsEnabled)
                        }
                    }
                }
            }
        }
    }
    
    // App lifecycle handler - App became active
    @objc private func handleAppDidBecomeActive() {
        Logger.debug("App became active. Current unread count: \(unreadNotificationCount)", logger: Logger.notification)
        
        // Reset badge count in Firestore when app becomes active
        if let fcmToken = getCurrentFCMToken() {
            // Reset badge count to zero in Firestore when app is opened
            updateDeviceBadgeCountInFirestore(fcmToken: fcmToken, badgeCount: 0)
        }
        
        // Ensure synchronization
        synchronizeBadgeCount() 
    }
    
    // App lifecycle handler - App entered background
    @objc private func handleAppDidEnterBackground() {
        // Ensure badge count is synchronized when app enters background
        Logger.debug("App entered background, synchronizing badge count: \(unreadNotificationCount)", logger: Logger.notification)
        synchronizeBadgeCount()
    }
    
    // MARK: - Notification Count Management
    
    // Increment notification count
    func incrementUnreadCount() {
        // Increment count 
        unreadNotificationCount += 1
        
        // Debug log
        Logger.debug("Incrementing unread count to: \(unreadNotificationCount)", logger: Logger.notification)
        
        // Update app badge using non-deprecated API
        UNUserNotificationCenter.current().setBadgeCount(unreadNotificationCount) { error in
            if let error = error {
                Logger.error("Error updating badge count", logger: Logger.notification, error: error)
            }
        }
        
        // Save to persistent storage
        saveUnreadNotificationCount()
    }
    
    // Set notification count to specific value
    func setUnreadCount(_ count: Int) {
        // Set count
        unreadNotificationCount = count
        
        // Debug log
        Logger.debug("Setting unread count to: \(count)", logger: Logger.notification)
        
        // Update app badge using non-deprecated API
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                Logger.error("Error updating badge count", logger: Logger.notification, error: error)
            }
        }
        
        // Save to persistent storage
        saveUnreadNotificationCount()
    }
    
    // Reset notification count - Call this when the user has viewed the relevant content
    // Renamed from clearUnreadCount
    func markNotificationsAsRead() {
        if unreadNotificationCount > 0 {
            // Reset unread count
            unreadNotificationCount = 0
            
            // Update app badge using non-deprecated API
            UNUserNotificationCenter.current().setBadgeCount(0) { error in
                if let error = error {
                    Logger.error("Error clearing badge count", logger: Logger.notification, error: error)
                }
            }
            
            // Debug log
            Logger.debug("Marked notifications as read, cleared unread count", logger: Logger.notification)
            
            // Save to persistent storage
            saveUnreadNotificationCount()
            
            // Clear delivered notifications from the Notification Center
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            
            // Also update the badge count in Firestore for this device
            if let fcmToken = getCurrentFCMToken() {
                updateDeviceBadgeCountInFirestore(fcmToken: fcmToken, badgeCount: 0)
            }
        }
    }
    
    // Synchronize badge count with system
    func synchronizeBadgeCount() {
        // Ensure app badge count matches our internal count
        Logger.debug("Synchronizing badge count: \(unreadNotificationCount)", logger: Logger.notification)
        
        // Update app badge using non-deprecated API
        UNUserNotificationCenter.current().setBadgeCount(unreadNotificationCount) { error in
            if let error = error {
                Logger.error("Error synchronizing badge count", logger: Logger.notification, error: error)
            }
        }
    }
    
    // MARK: - Handle Received Notification
    func handleReceivedNotification(_ userInfo: [AnyHashable: Any]) -> String? {
        // Debug log
        Logger.debug("Handling received notification", logger: Logger.notification)
        
        // When app is in foreground, increment badge instead of using server value
        // This prevents continuing from previously high values
        incrementUnreadCount()
        
        // Sync our badge count back to Firebase so server stays in sync
        if let fcmToken = getCurrentFCMToken() {
            updateDeviceBadgeCountInFirestore(fcmToken: fcmToken, badgeCount: unreadNotificationCount)
            Logger.debug("Updated Firestore badge count to: \(unreadNotificationCount)", logger: Logger.notification)
        }
        
        // Extract quote from notification payload
        if let data = userInfo["data"] as? [String: Any],
           let quote = data["quote"] as? String {
            return quote
        }
        
        return nil
    }
    
    // MARK: - Handle Notification Tap
    func handleNotificationTap(_ userInfo: [AnyHashable: Any]) -> (quote: String, source: String)? {
        // Extract quote from notification payload
        if let data = userInfo["data"] as? [String: Any],
           let quote = data["quote"] as? String {
            
            // Get source information
            let source = data["source"] as? String ?? "notification"
            
            // Mark notifications as read when tapped
            markNotificationsAsRead()
            
            return (quote: quote, source: source)
        }
        
        return nil
    }
    
    // MARK: - UNUserNotificationCenterDelegate Methods
    
    /// Handle notification received while app is in foreground
    /// Returns the quote text if available, and determines presentation options
    func handleNotificationWillPresent(_ userInfo: [AnyHashable: Any]) -> (quote: String?, options: UNNotificationPresentationOptions) {
        Logger.info("Handling notification received while app in foreground", logger: Logger.notification)
        
        // When app is in foreground, increment badge instead of using server value
        // This prevents continuing from previously high values
        incrementUnreadCount()
        
        // Sync our badge count back to Firebase so server stays in sync
        if let fcmToken = getCurrentFCMToken() {
            updateDeviceBadgeCountInFirestore(fcmToken: fcmToken, badgeCount: unreadNotificationCount)
            Logger.debug("Updated Firestore badge count to: \(unreadNotificationCount)", logger: Logger.notification)
        }
        
        // Extract quote from notification payload
        var quote: String?
        if let data = userInfo["data"] as? [String: Any],
           let extractedQuote = data["quote"] as? String {
            quote = extractedQuote
        }
        
        // Show notification with badge, sound, and banner
        return (quote: quote, options: [.banner, .sound, .badge])
    }
    
    /// Handle notification tap response
    /// Completes all handling including badge reset, marking as read, and posting notification to open quote view
    func handleNotificationResponse(_ userInfo: [AnyHashable: Any]) {
        Logger.info("Handling notification tap", logger: Logger.notification)
        
        // Extract badge count if available (for logging purposes)
        if let badgeCount = extractBadgeCount(from: userInfo) {
            Logger.debug("Badge count from notification payload: \(badgeCount)", logger: Logger.notification)
        }
        
        // Reset badge count when notification is tapped
        BadgeManager.shared.resetBadgeCount { error in
            if let error = error {
                Logger.error("Error resetting badge count on notification tap", logger: Logger.notification, error: error)
            }
        }
        
        // Mark notifications as read
        markNotificationsAsRead()
        
        // Extract notification data and post to open quote view if available
        if let notificationData = extractNotificationData(from: userInfo) {
            // Post notification to open the quote view
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConfiguration.Delays.notificationOpenDelay) {
                NotificationCenter.default.post(
                    name: Notification.Name(AppConfiguration.NotificationNames.openDailyQuoteView),
                    object: nil,
                    userInfo: [
                        "quote": notificationData.quote,
                        "source": notificationData.source,
                        "fromNotification": true
                    ]
                )
            }
        }
    }
    
    // MARK: - Helper Methods for Notification Handling
    
    /// Extract badge count from notification payload
    private func extractBadgeCount(from userInfo: [AnyHashable: Any]) -> Int? {
        // Try APS payload first
        if let aps = userInfo["aps"] as? [String: Any],
           let badge = aps["badge"] as? Int {
            return badge
        }
        
        // Try data payload
        if let data = userInfo["data"] as? [String: Any],
           let badgeString = data["badgeCount"] as? String,
           let badge = Int(badgeString) {
            return badge
        }
        
        return nil
    }
    
    /// Extract notification data (quote and source) from payload
    private func extractNotificationData(from userInfo: [AnyHashable: Any]) -> (quote: String, source: String)? {
        if let data = userInfo["data"] as? [String: Any],
           let quote = data["quote"] as? String {
            let source = data["source"] as? String ?? "notification"
            return (quote: quote, source: source)
        }
        return nil
    }
    
    // MARK: - Request Permission
    func requestNotificationPermission() async -> Bool {
        // Rule: Always add debug logs
        Logger.debug("Requesting notification permission", logger: Logger.notification)
        
        do {
            // Configure notification center
            let center = UNUserNotificationCenter.current()
            
            // Request authorization for alerts, badges, and sounds
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await center.requestAuthorization(options: options)
            
            // Debug log
            Logger.debug("Notification permission granted: \(granted)", logger: Logger.notification)
            
            // Update local state regardless of outcome
            isNotificationsEnabled = granted
            saveNotificationStatus()
            
            if granted {
                // Register for remote notifications on main thread
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                // Get FCM token and update device record
                await refreshDeviceToken()
            } else {
                // Permission denied, update if we have a token
                await updateDeviceTokenWithCurrentState()
            }
            
            return granted
        } catch {
            Logger.error("Error requesting notification permission", logger: Logger.notification, error: error)
            isNotificationsEnabled = false
            saveNotificationStatus()
            return false
        }
    }
    
    // MARK: - Helper Methods for Device Token
    
    // New method to get current FCM token
    func getCurrentFCMToken() -> String? {
        // UIApplication.shared.delegate must be accessed on the main thread
        var tokenFromAppDelegate: String?
        
        if Thread.isMainThread {
            // Already on main thread, access directly
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                tokenFromAppDelegate = appDelegate.fcmToken
            }
        } else {
            // Not on main thread, dispatch synchronously to main thread
            DispatchQueue.main.sync {
                if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                    tokenFromAppDelegate = appDelegate.fcmToken
                }
            }
        }
        
        if let token = tokenFromAppDelegate {
            return token
        }
        
        // Fallback to Messaging directly
        return Messaging.messaging().fcmToken
    }
    
    // New method to refresh and update device token
    private func refreshDeviceToken() async {
        // Force token refresh first
        do {
            let token = try await Messaging.messaging().token()
            Logger.debug("Refreshed FCM token: \(token.prefix(10))...", logger: Logger.notification)
            
            // Update device record with current permission state
            updateDeviceToken(token, forceEnabled: isNotificationsEnabled)
        } catch {
            Logger.debug("Error refreshing FCM token: \(error.localizedDescription)", logger: Logger.notification)
        }
    }
    
    // New method to update token with current state
    private func updateDeviceTokenWithCurrentState() async {
        if let token = getCurrentFCMToken() {
            Logger.debug("Updating device with current state: token=\(token.prefix(10))..., enabled=\(isNotificationsEnabled)", logger: Logger.notification)
            updateDeviceToken(token, forceEnabled: isNotificationsEnabled)
        }
    }
    
    // MARK: - Enable Notifications (Legacy method - kept for backward compatibility)
    func enableNotifications() async -> Bool {
        // Simply forward to requestNotificationPermission
        Logger.debug("enableNotifications() called - redirecting to requestNotificationPermission()", logger: Logger.notification)
        return await requestNotificationPermission()
    }
    
    // MARK: - Update Device Token
    func updateDeviceToken(_ fcmToken: String, forceEnabled: Bool? = nil) {
        Logger.debug("updateDeviceToken called with token: \(fcmToken.prefix(10))...", logger: Logger.notification)
        
        guard let userId = UserStatusManager.shared.state.userId else {
            Logger.debug("No user ID available - storing token for later registration: \(fcmToken.prefix(10))...", logger: Logger.notification)
            pendingFCMTokens.insert(fcmToken)
            return
        }
        
        // Remove from pending tokens since we're processing it now
        pendingFCMTokens.remove(fcmToken)
        Logger.debug("Registering device token for user \(userId): \(fcmToken.prefix(10))...", logger: Logger.notification)
        
        // Get timezone information
        let timeZone = TimeZone.current
        let timeZoneName = timeZone.identifier
        let timeZoneOffset = timeZone.secondsFromGMT() / 3600
        
        // Determine notification enabled status
        // Use forced value if provided (can be true or false), otherwise use current setting
        let enabled: Bool
        if let forceValue = forceEnabled {
            enabled = forceValue
        } else {
            enabled = isNotificationsEnabled
        }
        
        // First, remove old device tokens for the current platform to prevent duplicates
        let devicesRef = db.collection("users").document(userId).collection("devices")
        
        // Get current device's model name
        let deviceModel = UIDevice.current.model
        let deviceName = UIDevice.current.name
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        // Query for existing records from this device to clean up
        devicesRef.whereField("platform", isEqualTo: "iOS")
                  .whereField("deviceId", isEqualTo: deviceId)
                  .getDocuments { (snapshot, error) in
            if let error = error {
                Logger.debug("Error querying existing device tokens: \(error.localizedDescription)", logger: Logger.notification)
            } else if let snapshot = snapshot {
                let batch = self.db.batch()
                
                // Delete old tokens from this device
                for document in snapshot.documents {
                    if document.documentID != fcmToken {
                        batch.deleteDocument(document.reference)
                    }
                }
                
                // Commit batch delete
                batch.commit { error in
                    if let error = error {
                        Logger.debug("Error removing old tokens: \(error.localizedDescription)", logger: Logger.notification)
                    } else {
                        Logger.debug("Successfully removed old tokens", logger: Logger.notification)
                    }
                }
            }
        }
        
        // Save new token to Firestore
        let deviceRef = db.collection("users").document(userId).collection("devices").document(fcmToken)
        
        let deviceData: [String: Any] = [
            "token": fcmToken,
            "platform": "iOS",
            "deviceModel": deviceModel,
            "deviceName": deviceName,
            "deviceId": deviceId,
            "notificationsEnabled": enabled,
            "timeZone": timeZoneName,
            "timeZoneOffset": timeZoneOffset,
            "badgeCount": 0, // Always start with zero when registering device
            "lastUpdated": FieldValue.serverTimestamp()
        ]
        
        deviceRef.setData(deviceData, merge: true) { error in
            if let error = error {
                Logger.error("Failed to register device", logger: Logger.notification, error: error)
            } else {
                Logger.debug("Successfully registered device for user \(userId)", logger: Logger.notification)
            }
        }
    }
    
    // MARK: - Process Pending Tokens
    func processPendingDeviceTokens() {
        guard !pendingFCMTokens.isEmpty else {
            return
        }
        
        guard UserStatusManager.shared.state.userId != nil else {
            Logger.debug("Still no user ID available, keeping tokens pending", logger: Logger.notification)
            return
        }
        
        Logger.debug("Processing \(pendingFCMTokens.count) pending device tokens after authentication", logger: Logger.notification)
        
        let tokensToProcess = Array(pendingFCMTokens)
        for token in tokensToProcess {
            updateDeviceToken(token, forceEnabled: isNotificationsEnabled)
        }
    }
    
    // MARK: - Ensure Device Registration
    func ensureDeviceRegistration() async {
        guard let userId = UserStatusManager.shared.state.userId else {
            Logger.debug("Cannot ensure device registration: No user ID", logger: Logger.notification)
            return
        }
        
        // Check if device is already registered
        let devicesRef = db.collection("users").document(userId).collection("devices")
        
        do {
            let snapshot = try await devicesRef.getDocuments()
            if snapshot.documents.isEmpty {
                Logger.debug("No devices found for user \(userId), attempting registration", logger: Logger.notification)
                
                // Try to register current token if available
                if let fcmToken = getCurrentFCMToken() {
                    Logger.debug("Registering device with current FCM token", logger: Logger.notification)
                    updateDeviceToken(fcmToken)
                } else {
                    Logger.debug("No FCM token available for device registration", logger: Logger.notification)
                    
                    // Try to get a new token with retry logic
                    await attemptFCMTokenRetrieval(userId: userId)
                }
            }
        } catch {
            Logger.error("Error checking device registration", logger: Logger.notification, error: error)
            // Retry device registration after a delay
            await retryDeviceRegistration(userId: userId)
        }
    }
    
    // MARK: - FCM Token Retrieval with Retry
    private func attemptFCMTokenRetrieval(userId: String) async {
        var retryCount = 0
        let maxRetries = 5
        let retryDelay: UInt64 = 1_000_000_000 // 1 second
        
        while retryCount < maxRetries {
            do {
                let token = try await Messaging.messaging().token()
                Logger.debug("Got new FCM token on attempt \(retryCount + 1), registering device", logger: Logger.notification)
                updateDeviceToken(token)
                return
            } catch {
                Logger.debug("Failed to get FCM token on attempt \(retryCount + 1): \(error.localizedDescription)", logger: Logger.notification)
                retryCount += 1
                
                if retryCount < maxRetries {
                    try? await Task.sleep(nanoseconds: retryDelay)
                }
            }
        }
        
        Logger.error("Failed to get FCM token after \(maxRetries) attempts for user \(userId)", logger: Logger.notification)
    }
    
    // MARK: - Retry Device Registration
    private func retryDeviceRegistration(userId: String) async {
        Logger.debug("Retrying device registration for user \(userId)", logger: Logger.notification)
        
        // Wait a bit before retry
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Try again
        await ensureDeviceRegistration()
    }
    
    // MARK: - Device Registration Diagnostics
    func diagnoseDeviceRegistration() async {
        Logger.debug("Starting device registration diagnostics", logger: Logger.notification)
        
        // Check user authentication
        let isAuthenticated = UserStatusManager.shared.state.isAuthenticated
        let userId = UserStatusManager.shared.state.userId
        Logger.debug("User authenticated: \(isAuthenticated), User ID: \(userId ?? "nil")", logger: Logger.notification)
        
        // Check FCM token availability
        let fcmToken = getCurrentFCMToken()
        if let token = fcmToken {
            Logger.debug("FCM token available: \(token.prefix(10))...", logger: Logger.notification)
        }
        Logger.debug("Pending FCM tokens: \(pendingFCMTokens.count)", logger: Logger.notification)
        
        // If user is authenticated, check device registration status
        if let userId = userId {
            await checkDeviceRegistrationStatus(userId: userId)
        }
    }
    
    // MARK: - Check Device Registration Status
    private func checkDeviceRegistrationStatus(userId: String) async {
        do {
            let devicesRef = db.collection("users").document(userId).collection("devices")
            let snapshot = try await devicesRef.getDocuments()
            
            Logger.debug("Device registration status for user \(userId): Total devices: \(snapshot.documents.count)", logger: Logger.notification)
            
        } catch {
            Logger.error("Error checking device registration status", logger: Logger.notification, error: error)
        }
    }
    
    // Function to remove a specific device token for a given user
    func removeDeviceTokenFromUser(userId: String, fcmToken: String) async {
        Logger.debug("Attempting to remove token \(fcmToken.prefix(10))... for user \(userId)", logger: Logger.notification)
        let deviceRef = db.collection("users").document(userId).collection("devices").document(fcmToken)
        
        do {
            try await deviceRef.delete()
            Logger.debug("Successfully removed device token \(fcmToken.prefix(10))... for user \(userId)", logger: Logger.notification)
        } catch {
            Logger.error("Failed to remove device token \(fcmToken.prefix(10))... for user \(userId)", logger: Logger.notification, error: error)
        }
    }
    
    // Helper to update only the badge count in Firestore
    func updateDeviceBadgeCountInFirestore(fcmToken: String, badgeCount: Int) {
        guard let userId = UserStatusManager.shared.state.userId else {
            Logger.debug("Cannot update device badge count: No user ID", logger: Logger.notification)
            return
        }
        
        Logger.debug("Updating badge count in Firestore to \(badgeCount) for token: \(fcmToken.prefix(10))...", logger: Logger.notification)
        let deviceRef = db.collection("users").document(userId).collection("devices").document(fcmToken)
        deviceRef.updateData([
            "badgeCount": badgeCount,
            "lastUpdated": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                Logger.debug("Error updating badge count in Firestore: \(error.localizedDescription)", logger: Logger.notification)
            } else {
                Logger.debug("Successfully updated badge count in Firestore to \(badgeCount)", logger: Logger.notification)
            }
        }
    }
    
    // MARK: - Check Notification Status
    func checkNotificationStatus() async -> Bool {
        let current = UNUserNotificationCenter.current()
        let settings = await current.notificationSettings()
        
        // Get the current system authorization status
        let isAuthorized = settings.authorizationStatus == .authorized
        
        // Check if the system status differs from our stored state
        if isAuthorized != isNotificationsEnabled {
            Logger.debug("System status (\(isAuthorized)) differs from app state (\(isNotificationsEnabled)). Updating app state.", logger: Logger.notification)
            
            // Update the local state
            isNotificationsEnabled = isAuthorized
            saveNotificationStatus()
            
            // Update token with current permission state
            await updateDeviceTokenWithCurrentState()
        }
        
        return isAuthorized
    }
    
    // MARK: - Persistence
    func saveNotificationStatus() {
        UserDefaults.standard.set(isNotificationsEnabled, forKey: "notificationsEnabled")
    }
    
    // Make this method public so it can be called from AppDelegate
    func saveUnreadNotificationCount() {
        UserDefaults.standard.set(unreadNotificationCount, forKey: "unreadNotificationCount")
    }
    
    private func loadNotificationStatus() {
        // Remove loading the explicitlyDisabledByUser flag
        isNotificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }
    
    private func loadUnreadNotificationCount() {
        unreadNotificationCount = UserDefaults.standard.integer(forKey: "unreadNotificationCount")
    }
    
    // MARK: - Diagnostic Functions
    func verifyDeviceTokenAndBadgeCount() {
        #if DEBUG
        Logger.debug("Starting device token and badge count verification", logger: Logger.notification)
        
        // Check if we have a user ID
        guard let userId = UserStatusManager.shared.state.userId else {
            Logger.debug("No user ID available", logger: Logger.notification)
            return
        }
        
        // Check if we have a token using the thread-safe method
        if let token = getCurrentFCMToken() {
            Logger.debug("FCM token from Messaging: \(token.prefix(15))..., Local badge count: \(unreadNotificationCount)", logger: Logger.notification)
        }
        
        // Check Firestore for all device tokens
        db.collection("users").document(userId).collection("devices").getDocuments { (snapshot, error) in
            if let error = error {
                Logger.debug("Error fetching devices: \(error.localizedDescription)", logger: Logger.notification)
                return
            }
            
            guard let documents = snapshot?.documents else {
                return
            }
            
            Logger.debug("Found \(documents.count) devices in Firestore", logger: Logger.notification)
            
            // Check if we have a matching token
            if let appToken = self.getCurrentFCMToken(),
               documents.contains(where: { $0.documentID == appToken }) {
                Logger.debug("Current device matches FCM token in Firestore", logger: Logger.notification)
            }
        }
        #endif
    }
} 