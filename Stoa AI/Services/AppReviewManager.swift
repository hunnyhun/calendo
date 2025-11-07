import SwiftUI
import StoreKit

@MainActor
class AppReviewManager: ObservableObject {
    static let shared = AppReviewManager()
    
    private init() {}
    
    /// Simple request review - shows the native App Store review prompt
    func requestReview() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            print("📱 [AppReview] Requesting review from user")
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }
}

