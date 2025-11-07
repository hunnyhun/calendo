import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Onboarding Manager
@Observable final class OnboardingManager: @unchecked Sendable {
    
    // MARK: - Singleton
    static let shared = OnboardingManager()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Onboarding Keys
    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let onboardingCompletedAt = "onboardingCompletedAt"
        static let onboardingVersion = "onboardingVersion"
        static let onboardingStepsCompleted = "onboardingStepsCompleted"
    }
    
    // MARK: - Current Onboarding Version
    private let currentOnboardingVersion = "1.0"
    
    // MARK: - Computed Properties
    var hasCompletedOnboarding: Bool {
        get {
            userDefaults.bool(forKey: Keys.hasCompletedOnboarding)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.hasCompletedOnboarding)
            if newValue {
                userDefaults.set(Date(), forKey: Keys.onboardingCompletedAt)
                userDefaults.set(currentOnboardingVersion, forKey: Keys.onboardingVersion)
            }
        }
    }
    
    var onboardingCompletedAt: Date? {
        userDefaults.object(forKey: Keys.onboardingCompletedAt) as? Date
    }
    
    var onboardingVersion: String? {
        userDefaults.string(forKey: Keys.onboardingVersion)
    }
    
    // MARK: - Private Init
    private init() {}
    
    // MARK: - Onboarding Completion
    func markOnboardingCompleted() async {
        print("🎯 [OnboardingManager] Marking onboarding as completed")
        
        // Update local storage
        hasCompletedOnboarding = true
        
        // Update remote storage if user is authenticated
        if let userId = UserStatusManager.shared.state.userId {
            await updateOnboardingStatusInFirestore(userId: userId)
        } else {
            print("⚠️ [OnboardingManager] No user ID available, onboarding completion stored locally only")
        }
        
        // Post notification
        NotificationCenter.default.post(
            name: Notification.Name("OnboardingCompleted"),
            object: nil,
            userInfo: [
                "completedAt": Date(),
                "version": currentOnboardingVersion
            ]
        )
        
        print("✅ [OnboardingManager] Onboarding marked as completed successfully")
    }
    
    // MARK: - Firestore Update
    private func updateOnboardingStatusInFirestore(userId: String) async {
        do {
            let userRef = db.collection("users").document(userId)
            
            let onboardingData: [String: Any] = [
                "onboardingCompleted": true,
                "onboardingCompletedAt": FieldValue.serverTimestamp(),
                "onboardingVersion": currentOnboardingVersion,
                "lastUpdated": FieldValue.serverTimestamp()
            ]
            
            try await userRef.updateData(onboardingData)
            print("✅ [OnboardingManager] Onboarding status updated in Firestore for user \(userId)")
            
        } catch {
            print("❌ [OnboardingManager] Failed to update onboarding status in Firestore: \(error.localizedDescription)")
            
            // Retry after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                Task {
                    await self?.retryOnboardingStatusUpdate(userId: userId)
                }
            }
        }
    }
    
    // MARK: - Retry Logic
    private func retryOnboardingStatusUpdate(userId: String) async {
        print("🔄 [OnboardingManager] Retrying onboarding status update for user \(userId)")
        
        do {
            let userRef = db.collection("users").document(userId)
            
            let onboardingData: [String: Any] = [
                "onboardingCompleted": true,
                "onboardingCompletedAt": FieldValue.serverTimestamp(),
                "onboardingVersion": currentOnboardingVersion,
                "lastUpdated": FieldValue.serverTimestamp()
            ]
            
            try await userRef.updateData(onboardingData)
            print("✅ [OnboardingManager] Onboarding status retry successful for user \(userId)")
            
        } catch {
            print("❌ [OnboardingManager] Onboarding status retry failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Check Onboarding Status
    func checkOnboardingStatus() async -> Bool {
        print("🔍 [OnboardingManager] Checking onboarding status")
        
        // First check local storage
        let localStatus = hasCompletedOnboarding
        
        // If user is authenticated, also check remote status
        if let userId = UserStatusManager.shared.state.userId {
            let remoteStatus = await getOnboardingStatusFromFirestore(userId: userId)
            
            // If remote status differs from local, update local
            if remoteStatus != localStatus {
                print("🔄 [OnboardingManager] Remote onboarding status (\(remoteStatus)) differs from local (\(localStatus)), updating local")
                hasCompletedOnboarding = remoteStatus
                return remoteStatus
            }
        }
        
        return localStatus
    }
    
    // MARK: - Check Local Onboarding Status Only (for first launch)
    func checkLocalOnboardingStatus() -> Bool {
        print("🔍 [OnboardingManager] Checking local onboarding status only")
        return hasCompletedOnboarding
    }
    
    // MARK: - Get Remote Status
    private func getOnboardingStatusFromFirestore(userId: String) async -> Bool {
        do {
            let userRef = db.collection("users").document(userId)
            let document = try await userRef.getDocument()
            
            if document.exists {
                let data = document.data()
                let remoteStatus = data?["onboardingCompleted"] as? Bool ?? false
                print("📡 [OnboardingManager] Remote onboarding status: \(remoteStatus)")
                return remoteStatus
            } else {
                print("📡 [OnboardingManager] User document not found in Firestore")
                return false
            }
            
        } catch {
            print("❌ [OnboardingManager] Failed to get remote onboarding status: \(error.localizedDescription)")
            return hasCompletedOnboarding // Fallback to local status
        }
    }
    
    // MARK: - Reset Onboarding
    func resetOnboarding() {
        print("🔄 [OnboardingManager] Resetting onboarding status")
        
        userDefaults.removeObject(forKey: Keys.hasCompletedOnboarding)
        userDefaults.removeObject(forKey: Keys.onboardingCompletedAt)
        userDefaults.removeObject(forKey: Keys.onboardingVersion)
        
        // Post notification
        NotificationCenter.default.post(
            name: Notification.Name("OnboardingReset"),
            object: nil
        )
        
        print("✅ [OnboardingManager] Onboarding status reset successfully")
    }
    
    // MARK: - Get Onboarding Progress
    func getOnboardingProgress() -> OnboardingProgress {
        let completedAt = onboardingCompletedAt
        let version = onboardingVersion
        
        return OnboardingProgress(
            isCompleted: hasCompletedOnboarding,
            completedAt: completedAt,
            version: version,
            isCurrentVersion: version == currentOnboardingVersion
        )
    }
}

// MARK: - Onboarding Progress Model
struct OnboardingProgress {
    let isCompleted: Bool
    let completedAt: Date?
    let version: String?
    let isCurrentVersion: Bool
    
    var needsUpdate: Bool {
        isCompleted && !isCurrentVersion
    }
    
    var daysSinceCompletion: Int? {
        guard let completedAt = completedAt else { return nil }
        return Calendar.current.dateComponents([.day], from: completedAt, to: Date()).day
    }
}
