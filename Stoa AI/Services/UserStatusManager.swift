import SwiftUI
import FirebaseAuth
import RevenueCat

// MARK: - User Status Manager
@Observable final class UserStatusManager: NSObject {
    // MARK: - Properties
    private let authManager = AuthenticationManager.shared
    private let cloudFunctionService = CloudFunctionService.shared
    private let subscriptionManager = SubscriptionManager.shared
    private(set) var state = Models.UserState()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    var isLoading: Bool = false
    var errorMessage: String?
    
    // MARK: - Computed Properties
    var currentStatus: Models.AuthStatus {
        state.authStatus
    }
    
    var userEmail: String? {
        state.userEmail
    }
    
    // MARK: - Singleton
    static let shared = UserStatusManager()
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Setup Auth State Observer
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                await self?.updateUserState()
            }
        }
        
        // Setup RevenueCat Observer
        Purchases.shared.delegate = self
        
        // Initial state check
        Task { @MainActor in
            if Auth.auth().currentUser != nil {
                Logger.debug("Existing user found on initial setup: \(Auth.auth().currentUser!.uid)", logger: Logger.auth)
                await refreshUserState()
            } else {
                Logger.debug("No current user on initial setup", logger: Logger.auth)
                await updateUserState()
            }
        }
    }
    
    // MARK: - State Management
    @MainActor
    private func updateUserState() async {
        let previousUserId = state.userId
        
        Logger.debug("Starting user state update (Previous User ID: \(previousUserId ?? "none"))", logger: Logger.app)
        
        let user = Auth.auth().currentUser
        let newUserId = user?.uid
        
        // Update state FIRST so that userId is available when handling device tokens
        if let user = user {
            await updateAuthenticatedUserState(user: user)
        } else {
            await updateUnauthenticatedUserState()
        }
        
        // THEN handle device token cleanup and registration if user changed
        // Now state.userId is set, so updateDeviceToken will work correctly
        await handleDeviceTokenTransition(from: previousUserId, to: newUserId)
        
        state.lastUpdated = Date()
    }
    
    /// Handle device token cleanup and registration when user ID changes
    @MainActor
    private func handleDeviceTokenTransition(from previousUserId: String?, to newUserId: String?) async {
        // Clean up old device token if user changed
        if newUserId != previousUserId, let oldUserId = previousUserId {
            Logger.debug("User ID changed. Removing device token from old user: \(oldUserId)", logger: Logger.app)
            if let fcmToken = NotificationManager.shared.getCurrentFCMToken() {
                await NotificationManager.shared.removeDeviceTokenFromUser(userId: oldUserId, fcmToken: fcmToken)
            } else {
                Logger.debug("User ID changed, but no FCM token found to remove", logger: Logger.app)
            }
        }
        
        // Register device for new user
        if let newUserId = newUserId, newUserId != previousUserId {
            Logger.debug("User ID changed to \(newUserId) - processing device registration", logger: Logger.app)
            NotificationManager.shared.processPendingDeviceTokens()
            
            if let fcmToken = NotificationManager.shared.getCurrentFCMToken() {
                Logger.debug("Registering current device token for new user \(newUserId): \(fcmToken.prefix(10))...", logger: Logger.app)
                NotificationManager.shared.updateDeviceToken(
                    fcmToken,
                    forceEnabled: NotificationManager.shared.isNotificationsEnabled
                )
            } else {
                Logger.debug("No current FCM token available for immediate registration", logger: Logger.app)
            }
        }
    }
    
    /// Update state for authenticated user
    @MainActor
    private func updateAuthenticatedUserState(user: User) async {
        Logger.debug("User authenticated: \(user.uid)", logger: Logger.app)
        
        state.authStatus = .authenticated
        state.userEmail = user.email
        state.userId = user.uid
        
        // Sync RevenueCat with Firebase
        await syncRevenueCatWithFirebase(firebaseUID: user.uid)
        
        // Update subscription state
        await updateSubscriptionState()
        
        postUserStateChangedNotification()
    }
    
    /// Update state for unauthenticated user
    @MainActor
    private func updateUnauthenticatedUserState() async {
        Logger.debug("User transitioned to unauthenticated state", logger: Logger.app)
        
        state.authStatus = .unauthenticated
        state.userEmail = nil
        state.userId = nil
        state.subscriptionTier = .free
        state.lastUpdated = Date()
        
        // Log out from RevenueCat if necessary
        if !Purchases.shared.isAnonymous {
            do {
                _ = try await Purchases.shared.logOut()
                Logger.debug("Logged out from RevenueCat after user became nil", logger: Logger.subscription)
            } catch {
                Logger.error("Failed to log out from RevenueCat after user became nil", logger: Logger.subscription, error: error)
            }
        }
        
        postUserStateChangedNotification()
    }
    
    /// Sync RevenueCat App User ID with Firebase UID
    @MainActor
    private func syncRevenueCatWithFirebase(firebaseUID: String) async {
        if Purchases.shared.appUserID != firebaseUID {
            Logger.debug("RevenueCat App User ID (\(Purchases.shared.appUserID)) doesn't match Firebase UID (\(firebaseUID)). Configuring RevenueCat.", logger: Logger.subscription)
            await SubscriptionManager.shared.configureWithFirebaseUID(firebaseUID)
        }
    }
    
    /// Update subscription state from RevenueCat
    @MainActor
    private func updateSubscriptionState() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let isPremium = determinePremiumStatus(from: customerInfo)
            let wasSubscribed = state.subscriptionTier == .premium
            
            state.subscriptionTier = isPremium ? .premium : .free
            
            if isPremium != wasSubscribed {
                Logger.info("Subscription state changed to: \(state.subscriptionTier.rawValue)", logger: Logger.subscription)
            }
        } catch {
            Logger.error("Failed to get RevenueCat customer info", logger: Logger.subscription, error: error)
            state.subscriptionTier = .free
        }
    }
    
    /// Determine if user has premium status from customer info
    private func determinePremiumStatus(from customerInfo: CustomerInfo) -> Bool {
        let hasPremiumEntitlement = customerInfo.entitlements["Premium"]?.isActive == true
        let hasActiveSubscription = !customerInfo.activeSubscriptions.isEmpty
        return hasPremiumEntitlement || hasActiveSubscription
    }
    
    @MainActor
    func refreshUserState() async {
        isLoading = true
        defer { isLoading = false }
        
        await updateUserState()
    }
    
    // MARK: - Feature Access Control
    func canAccessFeature(_ feature: Models.Feature) -> Bool {
        // All users can access chat
        return true
    }
    
    // MARK: - Auth Methods
    func signOut() async throws {
        Logger.info("Signing out user", logger: Logger.auth)
        try await authManager.signOut()
    }
    
    func deleteAccount() async throws {
        Logger.info("Deleting user account", logger: Logger.auth)
        
        try await cloudFunctionService.deleteAccountAndData()
        try await authManager.signOut()

        await updateUserState()
    }
    
    // MARK: - Notification Helper
    private func postUserStateChangedNotification() {
        NotificationCenter.default.post(
            name: Notification.Name(AppConfiguration.NotificationNames.userStateChanged),
            object: nil,
            userInfo: [
                "authStatus": state.authStatus.rawValue,
                "isPremium": state.isPremium,
                "timestamp": state.lastUpdated,
                "userId": state.userId as Any,
                "userEmail": state.userEmail as Any
            ]
        )
        Logger.debug("Posted UserStateChanged notification", logger: Logger.app)
    }
}

// MARK: - RevenueCat Delegate
extension UserStatusManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            await updateUserState()
        }
    }
}
