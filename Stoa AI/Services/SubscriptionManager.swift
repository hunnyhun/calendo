import Foundation
import RevenueCat
import FirebaseAnalytics
import SwiftUI
import FirebaseAuth

// MARK: - Subscription Manager
@Observable final class SubscriptionManager: NSObject {
    // MARK: - Properties
    private(set) var currentSubscription: Models.SubscriptionTier = .free
    var isLoading: Bool = false
    var errorMessage: String?
    
    // MARK: - Singleton
    static let shared = SubscriptionManager()
    
    private override init() {
        super.init()
        setupRevenueCat()
    }
    
    // MARK: - Setup
    private func setupRevenueCat() {
        let firebaseUserID = Auth.auth().currentUser?.uid
        
        let builder = Configuration.Builder(withAPIKey: RevenueCatConfig.apiKey)
            .with(usesStoreKit2IfAvailable: true)
        
        if let uid = firebaseUserID {
            _ = builder.with(appUserID: uid)
        }
        
        Purchases.configure(with: builder.build())
        Purchases.shared.delegate = self
        
        // Configure logging levels
        #if DEBUG
        // In debug, use verbose logging for troubleshooting
        Purchases.logLevel = .debug
        #else
        // In production, only log errors
        Purchases.logLevel = .error
        #endif
        
        // Note: StoreKit may log internal errors (e.g., "StoreKit_Shared.StoreKitInternalError Code=7")
        // These are harmless background errors from StoreKit 2's Storefront update mechanism
        // They are especially common in simulator/development environments and can be safely ignored

        Task {
            await refreshSubscriptionStatus()
        }
    }
    
    // MARK: - Public Methods
    
    /// Configure RevenueCat with Firebase UID (call this after anonymous sign-in)
    func configureWithFirebaseUID(_ uid: String) async {
        Logger.debug("Configuring RevenueCat with Firebase UID: \(uid)", logger: Logger.subscription)
        
        do {
            let (_, created) = try await performRevenueCatLogin(uid: uid)
            Logger.info("RevenueCat login successful. New customer: \(created)", logger: Logger.subscription)
            
            // Refresh subscription status after login
            await refreshSubscriptionStatus()
        } catch {
            Logger.error("RevenueCat login failed", logger: Logger.subscription, error: error)
        }
    }
    
    // MARK: - Subscription Methods
    
    /// Refresh the current subscription status
    @MainActor
    func refreshSubscriptionStatus() async {
        let firebaseUserID = Auth.auth().currentUser?.uid
        let currentAppUserID = Purchases.shared.appUserID

        // Sync RevenueCat with Firebase if needed
        if let uid = firebaseUserID, uid != currentAppUserID {
            Logger.debug("Firebase UID (\(uid)) doesn't match RC App User ID (\(currentAppUserID)). Logging in to RevenueCat.", logger: Logger.subscription)
            do {
                let (_, _) = try await performRevenueCatLogin(uid: uid)
            } catch {
                Logger.error("RevenueCat login failed during refresh", logger: Logger.subscription, error: error)
            }
        } else if firebaseUserID == nil {
            Logger.debug("Firebase user logged out, but RC App User ID (\(currentAppUserID)) exists. Logging out from RevenueCat.", logger: Logger.subscription)
            do {
                _ = try await Purchases.shared.logOut()
                Logger.debug("RevenueCat logout successful", logger: Logger.subscription)
            } catch {
                Logger.error("RevenueCat logout failed", logger: Logger.subscription, error: error)
            }
        }

        // Update subscription status
        await updateSubscriptionStatusFromCustomerInfo()
    }
    
    /// Get available packages
    @MainActor
    func getAvailablePackages() async throws -> [Package] {
        isLoading = true
        defer { isLoading = false }
        
        return try await withCheckedThrowingContinuation { continuation in
            Logger.debug("Fetching available packages", logger: Logger.subscription)
            
            Purchases.shared.getOfferings { offerings, error in
                if let error = error {
                    Logger.error("Failed to fetch offerings", logger: Logger.subscription, error: error)
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let offerings = offerings,
                      let current = offerings.current else {
                    Logger.error("No offerings available", logger: Logger.subscription)
                    continuation.resume(throwing: SubscriptionError.noOfferings)
                    return
                }
                
                Logger.debug("Successfully fetched \(current.availablePackages.count) packages", logger: Logger.subscription)
                continuation.resume(returning: current.availablePackages)
            }
        }
    }
    
    /// Purchase a package
    @MainActor
    func purchase(package: Package) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            Logger.info("Starting purchase for package: \(package.identifier)", logger: Logger.subscription)
            logPackageDetails(package)
            
            let result = try await Purchases.shared.purchase(package: package)
            
            Logger.info("Purchase successful", logger: Logger.subscription)
            Logger.debug("Customer info after purchase - Entitlements: \(result.customerInfo.entitlements.all)", logger: Logger.subscription)
            
            // Update subscription status
            updateSubscriptionFromPurchase(result.customerInfo)
            
            // Note: We skip manual AnalyticsEventPurchase logging because:
            // 1. Firebase Analytics automatically tracks StoreKit purchases
            // 2. Manual logging causes duplicate events (as Firebase sees both StoreKit and manual events)
            // If custom tracking is needed, use logPurchaseToAnalytics() with a custom event name
            
            // Notify UserStatusManager to update its state (this may trigger RevenueCat delegate, which is fine)
            await UserStatusManager.shared.refreshUserState()
            
        } catch {
            Logger.error("Purchase failed", logger: Logger.subscription, error: error)
            if let rcError = error as? RevenueCat.ErrorCode {
                Logger.error("RevenueCat error code: \(rcError)", logger: Logger.subscription)
            }
            throw error
        }
    }
    
    /// Restore purchases
    @MainActor
    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            Logger.info("Starting purchase restoration", logger: Logger.subscription)
            
            // Ensure user is logged in to Firebase before restoring
            guard let firebaseUserID = Auth.auth().currentUser?.uid else {
                Logger.error("User must be logged in to restore purchases", logger: Logger.subscription)
                throw SubscriptionError.notLoggedIn
            }
            Logger.debug("Current Firebase User ID: \(firebaseUserID)", logger: Logger.subscription)

            // Get current customer info for comparison
            let beforeInfo = try await Purchases.shared.customerInfo()
            Logger.debug("Before restore - AppUserID: \(beforeInfo.originalAppUserId)", logger: Logger.subscription)

            // Perform restore
            let customerInfo = try await Purchases.shared.restorePurchases()
            Logger.debug("After restore - AppUserID: \(customerInfo.originalAppUserId)", logger: Logger.subscription)

            // Validate and update subscription from restore
            updateSubscriptionFromRestore(customerInfo: customerInfo, firebaseUID: firebaseUserID)

            Logger.debug("Restore completed - Final subscription: \(currentSubscription.rawValue)", logger: Logger.subscription)

            // Notify UserStatusManager to update its state
            await UserStatusManager.shared.refreshUserState()

        } catch {
            Logger.error("Restore failed", logger: Logger.subscription, error: error)
            if let rcError = error as? RevenueCat.ErrorCode {
                Logger.error("RevenueCat error code: \(rcError)", logger: Logger.subscription)
            }
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    /// Perform RevenueCat login with Firebase UID
    private func performRevenueCatLogin(uid: String) async throws -> (CustomerInfo, Bool) {
        let (customerInfo, created) = try await Purchases.shared.logIn(uid)
        Logger.debug("RevenueCat login successful. New customer: \(created)", logger: Logger.subscription)
        return (customerInfo, created)
    }
    
    /// Update subscription status from customer info
    @MainActor
    private func updateSubscriptionStatusFromCustomerInfo() async {
        do {
            Logger.debug("Starting subscription refresh with App User ID: \(Purchases.shared.appUserID)", logger: Logger.subscription)

            let customerInfo = try await Purchases.shared.customerInfo()
            Logger.debug("Got customer info - Entitlements: \(customerInfo.entitlements.all)", logger: Logger.subscription)
            
            let isPremium = determinePremiumStatus(from: customerInfo)
            currentSubscription = isPremium ? .premium : .free
            
            Logger.info("Updated subscription tier: \(currentSubscription.rawValue), isPremium: \(isPremium)", logger: Logger.subscription)
            
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("Failed to refresh subscription status", logger: Logger.subscription, error: error)
            Logger.debug("RevenueCat error details: \(error)", logger: Logger.subscription)
            currentSubscription = .free
        }
    }
    
    /// Determine premium status from customer info
    private func determinePremiumStatus(from customerInfo: CustomerInfo) -> Bool {
        let hasPremiumEntitlement = customerInfo.entitlements["Premium"]?.isActive == true
        let hasActiveSubscription = !customerInfo.activeSubscriptions.isEmpty
        return hasPremiumEntitlement || hasActiveSubscription
    }
    
    /// Update subscription from purchase result
    private func updateSubscriptionFromPurchase(_ customerInfo: CustomerInfo) {
        let isPremium = determinePremiumStatus(from: customerInfo)
        
        currentSubscription = isPremium ? .premium : .free
        
        Logger.info("Updated subscription tier: \(currentSubscription.rawValue)", logger: Logger.subscription)
        Logger.debug("Premium check - Has Premium Entitlement: \(customerInfo.entitlements["Premium"]?.isActive == true), Has Active Subscription: \(!customerInfo.activeSubscriptions.isEmpty)", logger: Logger.subscription)
    }
    
    /// Update subscription from restore result with validation
    private func updateSubscriptionFromRestore(customerInfo: CustomerInfo, firebaseUID: String) {
        let isPremiumActive = customerInfo.entitlements["Premium"]?.isActive == true
        let restoredAppUserID = customerInfo.originalAppUserId
        
        Logger.debug("Restore check - isPremiumActive: \(isPremiumActive), restoredAppUserID: \(restoredAppUserID), currentFirebaseUID: \(firebaseUID)", logger: Logger.subscription)

        if isPremiumActive {
            // Validate that the restored App User ID matches the current Firebase User ID
            if restoredAppUserID == firebaseUID {
                Logger.info("Restore successful and App User ID matches Firebase UID. Granting premium.", logger: Logger.subscription)
                currentSubscription = .premium
            } else {
                // Mismatch detected! Do not grant premium.
                Logger.warning("Restore successful, but App User ID (\(restoredAppUserID)) does not match current Firebase UID (\(firebaseUID)). Potential abuse attempt or account switching. Not granting premium.", logger: Logger.subscription)
                currentSubscription = .free
                errorMessage = "Restored purchase belongs to a different user account."
                // Consider throwing SubscriptionError.restoreMismatch here instead
            }
        } else {
            Logger.debug("No active 'Premium' entitlement found after restore.", logger: Logger.subscription)
            currentSubscription = .free
        }
    }
    
    /// Log package details for debugging
    private func logPackageDetails(_ package: Package) {
        Logger.debug("Package details - Identifier: \(package.identifier), Store Product ID: \(package.storeProduct.productIdentifier), Price: \(package.storeProduct.price)", logger: Logger.subscription)
    }
}

// MARK: - Custom Errors
extension SubscriptionManager {
    enum SubscriptionError: LocalizedError {
        case noOfferings
        case notLoggedIn
        case restoreMismatch

        var errorDescription: String? {
            switch self {
            case .noOfferings:
                return "No subscription offerings available"
            case .notLoggedIn:
                return "You must be logged in to restore purchases."
            case .restoreMismatch:
                return "The restored purchase is linked to a different account."
            }
        }
    }
}

// MARK: - RevenueCat Delegate
extension SubscriptionManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Logger.debug("RevenueCat update received", logger: Logger.subscription)
        Task { @MainActor in
            await refreshSubscriptionStatus()
        }
    }
}
