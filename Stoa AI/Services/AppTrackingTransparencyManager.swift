import Foundation
import AppTrackingTransparency
import AdSupport

class AppTrackingTransparencyManager: ObservableObject {
    static let shared = AppTrackingTransparencyManager()
    
    @Published var trackingStatus: ATTrackingManager.AuthorizationStatus = .notDetermined
    
    private init() {
        updateTrackingStatus()
    }
    
    /// Updates the current tracking status
    private func updateTrackingStatus() {
        trackingStatus = ATTrackingManager.trackingAuthorizationStatus
    }
    
    /// Requests App Tracking Transparency permission
    /// - Returns: True if permission was granted, false otherwise
    @MainActor
    func requestTrackingPermission() async -> Bool {
        // Check if we're on iOS 14+ and tracking permission is available
        guard #available(iOS 14, *) else {
            print("📱 [ATT] App Tracking Transparency not available on this iOS version")
            return false
        }
        
        // If already determined, return current status
        if ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
            updateTrackingStatus()
            return trackingStatus == .authorized
        }
        
        // Request permission
        return await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    self.trackingStatus = status
                    let granted = status == .authorized
                    
                    print("📱 [ATT] Tracking permission status: \(status.description)")
                    
                    if granted {
                        print("📱 [ATT] IDFA: \(ASIdentifierManager.shared().advertisingIdentifier)")
                    }
                    
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// Check if tracking is currently authorized
    var isTrackingAuthorized: Bool {
        return trackingStatus == .authorized
    }
    
    /// Get the current IDFA if tracking is authorized
    var advertisingIdentifier: UUID? {
        guard isTrackingAuthorized else { return nil }
        let identifier = ASIdentifierManager.shared().advertisingIdentifier
        return identifier != UUID(uuidString: "00000000-0000-0000-0000-000000000000") ? identifier : nil
    }
}

// MARK: - ATTrackingManager.AuthorizationStatus Extension
extension ATTrackingManager.AuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }
}
