import Foundation
import FirebaseCore
import FirebaseAppCheck

/// Centralized Firebase configuration
/// Handles Firebase initialization and App Check setup
class FirebaseConfig {
    /// Configure Firebase and App Check
    static func configure() {
        FirebaseApp.configure()
        configureAppCheck()
    }
    
    /// Configure Firebase App Check for security
    private static func configureAppCheck() {
        #if targetEnvironment(simulator)
        let providerFactory = AppCheckDebugProviderFactory()
        #else
        let providerFactory = DeviceCheckProviderFactory()
        #endif
        
        AppCheck.setAppCheckProviderFactory(providerFactory)
        
        // Fetch initial token to verify App Check is working (only log errors)
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                Logger.error("Error fetching initial App Check token", logger: Logger.firebase, error: error)
            }
        }
    }
} 