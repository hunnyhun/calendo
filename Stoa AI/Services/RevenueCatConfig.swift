import Foundation

/// RevenueCat configuration
enum RevenueCatConfig {
    /// RevenueCat API key read from Info.plist
    static var apiKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String, !key.isEmpty else {
            fatalError("RevenueCatAPIKey not found")
        }
        return key
    }
}

