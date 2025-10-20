import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
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
        print("📱 [NotificationManager] Initialized with unread count: \(unreadNotificationCount)")
        
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
        
        print("📱 [NotificationManager] Ensuring user document exists for userId: \(userId)")
        
        // Check if document exists
        userDocRef.getDocument { (document, error) in
            if let error = error {
                print("📱 [NotificationManager] Error checking user document: \(error.localizedDescription)")
                return
            }
            
            if let document = document, document.exists {
                print("📱 [NotificationManager] User document already exists")
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
                        print("📱 [NotificationManager] Error creating user document: \(error.localizedDescription)")
                    } else {
                        print("📱 [NotificationManager] User document created successfully")
                        
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
        print("📱 [NotificationManager] App became active. Current unread count: \(unreadNotificationCount)")
        
        // Reset badge count in Firestore when app becomes active
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
           let fcmToken = appDelegate.fcmToken {
            // Reset badge count to zero in Firestore when app is opened
            updateDeviceBadgeCountInFirestore(fcmToken: fcmToken, badgeCount: 0)
            print("📱 [NotificationManager] Reset badge count in Firestore to 0")
        }
        
        // Ensure synchronization
        synchronizeBadgeCount() 
    }
    
    // App lifecycle handler - App entered background
    @objc private func handleAppDidEnterBackground() {
        // Ensure badge count is synchronized when app enters background
        print("📱 [NotificationManager] App entered background, synchronizing badge count: \(unreadNotificationCount)")
        synchronizeBadgeCount()
    }
    
    // MARK: - Notification Count Management
    
    // Increment notification count
    func incrementUnreadCount() {
        // Increment count 
        unreadNotificationCount += 1
        
        // Debug log
        print("📱 [NotificationManager] Incrementing unread count to: \(unreadNotificationCount)")
        
        // Update app badge using non-deprecated API
        UNUserNotificationCenter.current().setBadgeCount(unreadNotificationCount) { error in
            if let error = error {
                print("❌ [NotificationManager] Error updating badge count: \(error.localizedDescription)")
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
        print("📱 [NotificationManager] Setting unread count to: \(count)")
        
        // Update app badge using non-deprecated API
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("❌ [NotificationManager] Error updating badge count: \(error.localizedDescription)")
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
                    print("❌ [NotificationManager] Error clearing badge count: \(error.localizedDescription)")
                }
            }
            
            // Debug log
            print("📱 [NotificationManager] Marked notifications as read, cleared unread count")
            
            // Save to persistent storage
            saveUnreadNotificationCount()
            
            // Clear delivered notifications from the Notification Center
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            
            // Also update the badge count in Firestore for this device
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let fcmToken = appDelegate.fcmToken {
                print("📱 [NotificationManager] Updating Firestore badge count to 0 from markNotificationsAsRead")
                updateDeviceBadgeCountInFirestore(fcmToken: fcmToken, badgeCount: 0)
            } else {
                print("📱 [NotificationManager] Cannot update Firestore: No FCM token available")
            }
        } else {
            print("📱 [NotificationManager] No notifications to mark as read (count already 0)")
        }
    }
    
    // Synchronize badge count with system
    func synchronizeBadgeCount() {
        // Ensure app badge count matches our internal count
        print("📱 [NotificationManager] Synchronizing badge count: \(unreadNotificationCount)")
        
        // Update app badge using non-deprecated API
        UNUserNotificationCenter.current().setBadgeCount(unreadNotificationCount) { error in
            if let error = error {
                print("❌ [NotificationManager] Error synchronizing badge count: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Handle Received Notification
    func handleReceivedNotification(_ userInfo: [AnyHashable: Any]) -> String? {
        // Debug log
        print("📱 [NotificationManager] Handling received notification")
        
        // When app is in foreground, increment badge instead of using server value
        // This prevents continuing from previously high values
        incrementUnreadCount()
        
        // Sync our badge count back to Firebase so server stays in sync
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
           let fcmToken = appDelegate.fcmToken {
            updateDeviceBadgeCountInFirestore(fcmToken: fcmToken, badgeCount: unreadNotificationCount)
            print("📱 [NotificationManager] Updated Firestore badge count to: \(unreadNotificationCount)")
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
    
    // MARK: - Request Permission
    func requestNotificationPermission() async -> Bool {
        // Rule: Always add debug logs
        print("📱 [NotificationManager] Requesting notification permission")
        
        do {
            // Configure notification center
            let center = UNUserNotificationCenter.current()
            
            // Request authorization for alerts, badges, and sounds
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await center.requestAuthorization(options: options)
            
            // Debug log
            print("📱 [NotificationManager] Notification permission granted: \(granted)")
            
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
            print("📱 [NotificationManager] Error requesting notification permission: \(error.localizedDescription)")
            isNotificationsEnabled = false
            saveNotificationStatus()
            return false
        }
    }
    
    // MARK: - Helper Methods for Device Token
    
    // New method to get current FCM token
    func getCurrentFCMToken() -> String? {
        // Try to get token from AppDelegate first
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
           let fcmToken = appDelegate.fcmToken {
            return fcmToken
        }
        
        // Fallback to Messaging directly
        return Messaging.messaging().fcmToken
    }
    
    // New method to refresh and update device token
    private func refreshDeviceToken() async {
        // Force token refresh first
        do {
            let token = try await Messaging.messaging().token()
            print("📱 [NotificationManager] Refreshed FCM token: \(token.prefix(10))...")
            
            // Update device record with current permission state
            updateDeviceToken(token, forceEnabled: isNotificationsEnabled)
        } catch {
            print("📱 [NotificationManager] Error refreshing FCM token: \(error.localizedDescription)")
        }
    }
    
    // New method to update token with current state
    private func updateDeviceTokenWithCurrentState() async {
        if let token = getCurrentFCMToken() {
            print("📱 [NotificationManager] Updating device with current state: token=\(token.prefix(10))..., enabled=\(isNotificationsEnabled)")
            updateDeviceToken(token, forceEnabled: isNotificationsEnabled)
        } else {
            print("📱 [NotificationManager] No FCM token available to update device state")
        }
    }
    
    // MARK: - Enable Notifications (Legacy method - kept for backward compatibility)
    func enableNotifications() async -> Bool {
        // Simply forward to requestNotificationPermission
        print("📱 [NotificationManager] enableNotifications() called - redirecting to requestNotificationPermission()")
        return await requestNotificationPermission()
    }
    
    // MARK: - Update Device Token
    func updateDeviceToken(_ fcmToken: String, forceEnabled: Bool? = nil) {
        print("📱 [NotificationManager] updateDeviceToken called with token: \(fcmToken.prefix(10))...")
        print("📱 [NotificationManager] Current user ID: \(UserStatusManager.shared.state.userId ?? "nil")")
        print("📱 [NotificationManager] User authenticated: \(UserStatusManager.shared.state.isAuthenticated)")
        
        guard let userId = UserStatusManager.shared.state.userId else {
            print("📱 [NotificationManager] No user ID available - storing token for later registration: \(fcmToken.prefix(10))...")
            pendingFCMTokens.insert(fcmToken)
            print("📱 [NotificationManager] Pending tokens count: \(pendingFCMTokens.count)")
            return
        }
        
        // Remove from pending tokens since we're processing it now
        pendingFCMTokens.remove(fcmToken)
        print("📱 [NotificationManager] Registering device token for user \(userId): \(fcmToken.prefix(10))...")
        
        // Get timezone information
        let timeZone = TimeZone.current
        let timeZoneName = timeZone.identifier
        let timeZoneOffset = timeZone.secondsFromGMT() / 3600
        
        // Determine notification enabled status
        // Use forced value if provided (can be true or false), otherwise use current setting
        let enabled: Bool
        if let forceValue = forceEnabled {
            enabled = forceValue
            print("📱 [NotificationManager] Using forced notification status: \(enabled)")
        } else {
            enabled = isNotificationsEnabled
            print("📱 [NotificationManager] Using current notification status: \(enabled)")
        }
        
        print("📱 [NotificationManager] Updating device token with notificationsEnabled: \(enabled)")
        
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
                print("📱 [NotificationManager] Error querying existing device tokens: \(error)")
            } else if let snapshot = snapshot {
                let batch = self.db.batch()
                
                // Delete old tokens from this device
                for document in snapshot.documents {
                    if document.documentID != fcmToken {
                        print("📱 [NotificationManager] Removing old device token: \(document.documentID)")
                        batch.deleteDocument(document.reference)
                    }
                }
                
                // Commit batch delete
                batch.commit { error in
                    if let error = error {
                        print("📱 [NotificationManager] Error removing old tokens: \(error)")
                    } else {
                        print("📱 [NotificationManager] Successfully removed old tokens")
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
        
        print("📱 [NotificationManager] Saving device data to Firestore:")
        print("📱 [NotificationManager] - User ID: \(userId)")
        print("📱 [NotificationManager] - Device ID: \(deviceId)")
        print("📱 [NotificationManager] - Device Model: \(deviceModel)")
        print("📱 [NotificationManager] - Device Name: \(deviceName)")
        print("📱 [NotificationManager] - Notifications Enabled: \(enabled)")
        print("📱 [NotificationManager] - Timezone: \(timeZoneName)")
        
        deviceRef.setData(deviceData, merge: true) { error in
            if let error = error {
                print("❌ [NotificationManager] Failed to register device: \(error.localizedDescription)")
            } else {
                print("✅ [NotificationManager] Successfully registered device for user \(userId)")
            }
        }
    }
    
    // MARK: - Process Pending Tokens
    func processPendingDeviceTokens() {
        guard !pendingFCMTokens.isEmpty else {
            print("📱 [NotificationManager] No pending device tokens to process")
            return
        }
        
        guard UserStatusManager.shared.state.userId != nil else {
            print("📱 [NotificationManager] Still no user ID available, keeping tokens pending")
            return
        }
        
        print("📱 [NotificationManager] Processing \(pendingFCMTokens.count) pending device tokens after authentication")
        
        let tokensToProcess = Array(pendingFCMTokens)
        for token in tokensToProcess {
            updateDeviceToken(token, forceEnabled: isNotificationsEnabled)
        }
    }
    
    // MARK: - Ensure Device Registration
    func ensureDeviceRegistration() async {
        guard let userId = UserStatusManager.shared.state.userId else {
            print("📱 [NotificationManager] Cannot ensure device registration: No user ID")
            return
        }
        
        print("📱 [NotificationManager] Ensuring device registration for user: \(userId)")
        
        // Check if device is already registered
        let devicesRef = db.collection("users").document(userId).collection("devices")
        
        do {
            let snapshot = try await devicesRef.getDocuments()
            if snapshot.documents.isEmpty {
                print("📱 [NotificationManager] No devices found for user \(userId), attempting registration")
                
                // Try to register current token if available
                if let fcmToken = getCurrentFCMToken() {
                    print("📱 [NotificationManager] Registering device with current FCM token")
                    updateDeviceToken(fcmToken)
                } else {
                    print("⚠️ [NotificationManager] No FCM token available for device registration")
                    
                    // Try to get a new token with retry logic
                    await attemptFCMTokenRetrieval(userId: userId)
                }
            } else {
                print("✅ [NotificationManager] User \(userId) already has \(snapshot.documents.count) device(s) registered")
            }
        } catch {
            print("❌ [NotificationManager] Error checking device registration: \(error.localizedDescription)")
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
                print("📱 [NotificationManager] Got new FCM token on attempt \(retryCount + 1), registering device")
                updateDeviceToken(token)
                return
            } catch {
                print("⚠️ [NotificationManager] Failed to get FCM token on attempt \(retryCount + 1): \(error.localizedDescription)")
                retryCount += 1
                
                if retryCount < maxRetries {
                    print("📱 [NotificationManager] Retrying FCM token retrieval in \(retryDelay / 1_000_000_000) seconds...")
                    try? await Task.sleep(nanoseconds: retryDelay)
                }
            }
        }
        
        print("❌ [NotificationManager] Failed to get FCM token after \(maxRetries) attempts for user \(userId)")
    }
    
    // MARK: - Retry Device Registration
    private func retryDeviceRegistration(userId: String) async {
        print("📱 [NotificationManager] Retrying device registration for user \(userId)")
        
        // Wait a bit before retry
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Try again
        await ensureDeviceRegistration()
    }
    
    // MARK: - Device Registration Diagnostics
    func diagnoseDeviceRegistration() async {
        print("🔍 [NotificationManager] Starting device registration diagnostics")
        
        // Check user authentication
        let isAuthenticated = UserStatusManager.shared.state.isAuthenticated
        let userId = UserStatusManager.shared.state.userId
        print("🔍 [NotificationManager] User authenticated: \(isAuthenticated)")
        print("🔍 [NotificationManager] User ID: \(userId ?? "nil")")
        
        // Check FCM token availability
        let fcmToken = getCurrentFCMToken()
        print("🔍 [NotificationManager] FCM token available: \(fcmToken != nil)")
        if let token = fcmToken {
            print("🔍 [NotificationManager] FCM token: \(token.prefix(10))...")
        }
        
        // Check pending tokens
        print("🔍 [NotificationManager] Pending FCM tokens: \(pendingFCMTokens.count)")
        
        // If user is authenticated, check device registration status
        if let userId = userId {
            await checkDeviceRegistrationStatus(userId: userId)
        }
        
        print("🔍 [NotificationManager] Device registration diagnostics completed")
    }
    
    // MARK: - Check Device Registration Status
    private func checkDeviceRegistrationStatus(userId: String) async {
        do {
            let devicesRef = db.collection("users").document(userId).collection("devices")
            let snapshot = try await devicesRef.getDocuments()
            
            print("🔍 [NotificationManager] Device registration status for user \(userId):")
            print("🔍 [NotificationManager] - Total devices: \(snapshot.documents.count)")
            
            for document in snapshot.documents {
                let data = document.data()
                let token = data["token"] as? String ?? "unknown"
                let platform = data["platform"] as? String ?? "unknown"
                let deviceModel = data["deviceModel"] as? String ?? "unknown"
                let notificationsEnabled = data["notificationsEnabled"] as? Bool ?? false
                let lastUpdated = data["lastUpdated"] as? Timestamp
                
                print("🔍 [NotificationManager] - Device: \(token.prefix(10))...")
                print("🔍 [NotificationManager]   Platform: \(platform)")
                print("🔍 [NotificationManager]   Model: \(deviceModel)")
                print("🔍 [NotificationManager]   Notifications: \(notificationsEnabled)")
                if let lastUpdated = lastUpdated {
                    print("🔍 [NotificationManager]   Last Updated: \(lastUpdated.dateValue())")
                }
            }
            
        } catch {
            print("❌ [NotificationManager] Error checking device registration status: \(error.localizedDescription)")
        }
    }
    
    // Function to remove a specific device token for a given user
    func removeDeviceTokenFromUser(userId: String, fcmToken: String) async {
        print("📱 [NotificationManager] Attempting to remove token \(fcmToken.prefix(10))... for user \(userId)")
        let deviceRef = db.collection("users").document(userId).collection("devices").document(fcmToken)
        
        do {
            try await deviceRef.delete()
            print("📱 [NotificationManager] Successfully removed device token \(fcmToken.prefix(10))... for user \(userId)")
        } catch {
            print("❌ [NotificationManager] Failed to remove device token \(fcmToken.prefix(10))... for user \(userId): \(error.localizedDescription)")
            // Handle error appropriately, maybe retry or log specifically
        }
    }
    
    // Helper to update only the badge count in Firestore
    func updateDeviceBadgeCountInFirestore(fcmToken: String, badgeCount: Int) {
        guard let userId = UserStatusManager.shared.state.userId else {
            print("📱 [NotificationManager] Cannot update device badge count: No user ID")
            return
        }
        
        print("📱 [NotificationManager] Updating badge count in Firestore to \(badgeCount) for token: \(fcmToken.prefix(10))...")
        let deviceRef = db.collection("users").document(userId).collection("devices").document(fcmToken)
        deviceRef.updateData([
            "badgeCount": badgeCount,
            "lastUpdated": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("📱 [NotificationManager] Error updating badge count in Firestore: \(error.localizedDescription)")
            } else {
                print("📱 [NotificationManager] Successfully updated badge count in Firestore to \(badgeCount)")
                
                // Verify the update was successful by reading the document
                deviceRef.getDocument { (document, error) in
                    if let document = document, document.exists {
                        if let data = document.data(), let storedBadge = data["badgeCount"] as? Int {
                            print("📱 [NotificationManager] Verified Firestore badge count is now: \(storedBadge)")
                        } else {
                            print("📱 [NotificationManager] Could not read badge count from document")
                        }
                    } else {
                        print("📱 [NotificationManager] Device document does not exist")
                    }
                }
            }
        }
    }
    
    // MARK: - Check Notification Status
    func checkNotificationStatus() async -> Bool {
        let current = UNUserNotificationCenter.current()
        let settings = await current.notificationSettings()
        
        // Get the current system authorization status
        let isAuthorized = settings.authorizationStatus == .authorized
        
        // Rule: Always add debug logs
        print("📱 [NotificationManager] System notification status check: \(isAuthorized ? "authorized" : "not authorized"), Current app state: \(isNotificationsEnabled)")
        
        // Check if the system status differs from our stored state
        if isAuthorized != isNotificationsEnabled {
            print("📱 [NotificationManager] System status (\(isAuthorized)) differs from app state (\(isNotificationsEnabled)). Updating app state.")
            
            // Update the local state
            isNotificationsEnabled = isAuthorized
            saveNotificationStatus()
            
            // Update token with current permission state
            await updateDeviceTokenWithCurrentState()
        } else {
            // Rule: Always add debug logs
            print("📱 [NotificationManager] System status matches app state. No change needed.")
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
        print("📊 [Badge Diagnostic] Starting device token and badge count verification")
        
        // Check if we have a user ID
        guard let userId = UserStatusManager.shared.state.userId else {
            print("📊 [Badge Diagnostic] No user ID available")
            return
        }
        print("📊 [Badge Diagnostic] User ID: \(userId)")
        
        // Check if we have a token directly
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            if let token = appDelegate.fcmToken {
                print("📊 [Badge Diagnostic] FCM token from AppDelegate: \(token.prefix(15))...")
            } else {
                print("📊 [Badge Diagnostic] No FCM token stored in AppDelegate")
            }
        }
        
        // Check for token via Messaging
        if let token = Messaging.messaging().fcmToken {
            print("📊 [Badge Diagnostic] FCM token from Messaging: \(token.prefix(15))...")
        } else {
            print("📊 [Badge Diagnostic] No FCM token available from Messaging")
        }
        
        // Verify badge counts
        print("📊 [Badge Diagnostic] Local badge count: \(unreadNotificationCount)")
        
        // Note: As of iOS 17, there's no non-deprecated API to read the current badge count.
        // UNUserNotificationCenter provides setBadgeCount but no getBadgeCount.
        // We'll rely on our locally tracked count as the source of truth.
        print("📊 [Badge Diagnostic] Using local badge count as source of truth: \(unreadNotificationCount)")
        
        // Check Firestore for all device tokens
        db.collection("users").document(userId).collection("devices").getDocuments { (snapshot, error) in
            if let error = error {
                print("📊 [Badge Diagnostic] Error fetching devices: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("📊 [Badge Diagnostic] No devices found in Firestore")
                return
            }
            
            print("📊 [Badge Diagnostic] Found \(documents.count) devices in Firestore")
            
            for (index, document) in documents.enumerated() {
                let data = document.data()
                let tokenId = document.documentID
                let badgeCount = data["badgeCount"] as? Int ?? -1
                let enabled = data["notificationsEnabled"] as? Bool ?? false
                let lastUpdated = data["lastUpdated"] as? Timestamp
                
                print("📊 [Badge Diagnostic] Device \(index+1):")
                print("📊 [Badge Diagnostic] - Token ID: \(tokenId.prefix(15))...")
                print("📊 [Badge Diagnostic] - Badge Count: \(badgeCount)")
                print("📊 [Badge Diagnostic] - Notifications Enabled: \(enabled)")
                if let lastUpdated = lastUpdated {
                    print("📊 [Badge Diagnostic] - Last Updated: \(lastUpdated.dateValue())")
                } else {
                    print("📊 [Badge Diagnostic] - Last Updated: Unknown")
                }
                
                // Check if we have a matching token in the AppDelegate
                if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                   let appToken = appDelegate.fcmToken,
                   appToken == tokenId {
                    print("📊 [Badge Diagnostic] ✅ This device matches current FCM token!")
                }
            }
        }
    }
} 