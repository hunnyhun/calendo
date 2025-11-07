import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    // MARK: - Properties
    var latestQuote: String?
    var fcmToken: String?
    
    // MARK: - App Lifecycle
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configure Firebase (includes App Check)
        FirebaseConfig.configure()
        
        // Configure delegates
        setupDelegates()
        
        // Register for app lifecycle notifications
        registerForAppLifecycleNotifications()
        
        // Initialize badge count and device registration
        initializeBadgeCount()
        initializeDeviceRegistration()
        
        return true
    }
    
    func application(_ app: UIApplication,
                    open url: URL,
                    options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Logger.info("Handling URL: \(url.absoluteString)", logger: Logger.app)
        return GIDSignIn.sharedInstance.handle(url)
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
    
    // MARK: - Setup Methods
    private func setupDelegates() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func registerForAppLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    private func initializeBadgeCount() {
        BadgeManager.shared.resetBadgeCount { error in
            if let error = error {
                Logger.error("Error resetting badge count on launch", logger: Logger.app, error: error)
            }
        }
        
        NotificationManager.shared.unreadNotificationCount = AppConfiguration.Badge.resetValue
        NotificationManager.shared.saveUnreadNotificationCount()
    }
    
    private func initializeDeviceRegistration() {
        guard let fcmToken = Messaging.messaging().fcmToken else {
            return
        }
        
        self.fcmToken = fcmToken
        updateDeviceRegistration(token: fcmToken)
        
        // Run diagnostic after delay to allow Firestore update to complete (only in debug builds)
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConfiguration.Delays.diagnosticDelay) {
            NotificationManager.shared.verifyDeviceTokenAndBadgeCount()
        }
        #endif
    }
    
    // MARK: - Helper Methods
    private func updateDeviceRegistration(token: String, forceEnabled: Bool? = nil) {
        NotificationManager.shared.updateDeviceToken(
            token,
            forceEnabled: forceEnabled ?? NotificationManager.shared.isNotificationsEnabled
        )
        NotificationManager.shared.updateDeviceBadgeCountInFirestore(
            fcmToken: token,
            badgeCount: AppConfiguration.Badge.resetValue
        )
    }
    
    
    // MARK: - Push Notification Handling
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Logger.info("Firebase registration token received: \(fcmToken?.prefix(10) ?? "nil")...", logger: Logger.app)
        
        guard let token = fcmToken else {
            return
        }
        
        self.fcmToken = token
        
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let isAuthorized = settings.authorizationStatus == .authorized
            
            DispatchQueue.main.async { [weak self] in
                NotificationManager.shared.isNotificationsEnabled = isAuthorized
                self?.updateDeviceRegistration(token: token, forceEnabled: isAuthorized)
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Fully delegate to NotificationManager for handling
        let userInfo = notification.request.content.userInfo
        let result = NotificationManager.shared.handleNotificationWillPresent(userInfo)
        
        // Store quote if available
        if let quote = result.quote {
            latestQuote = quote
        }
        
        completionHandler(result.options)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Fully delegate to NotificationManager for handling
        let userInfo = response.notification.request.content.userInfo
        NotificationManager.shared.handleNotificationResponse(userInfo)
        
        // Extract quote for AppDelegate property (if needed elsewhere)
        if let quote = NotificationManager.shared.handleReceivedNotification(userInfo) {
            latestQuote = quote
        }
        
        completionHandler()
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.error("APNs registration failed", logger: Logger.app, error: error)
    }
    
    // MARK: - App Lifecycle Handlers
    @objc func handleApplicationBecameActive(_ notification: Notification) {
        // Use BadgeManager instead of duplicate logic
        BadgeManager.shared.resetBadgeCount { error in
            if let error = error {
                Logger.error("Error resetting badge count on app active", logger: Logger.app, error: error)
            }
        }
        
        NotificationManager.shared.unreadNotificationCount = AppConfiguration.Badge.resetValue
        NotificationManager.shared.saveUnreadNotificationCount()
        
        // Update device registration if token is available
        let token = fcmToken ?? Messaging.messaging().fcmToken
        if let token = token {
            if fcmToken == nil {
                self.fcmToken = token
            }
            updateDeviceRegistration(token: token)
        }
    }
}
