import SwiftUI
import GoogleSignIn
// Firebase is configured in AppDelegate

// Main app entry point
@main
struct CalendoApp: App {
    // MARK: - Properties
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) var scenePhase
    
    // MARK: - Body
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environment(\.scenePhase, .active)
                    .onOpenURL { url in
                        // Handle deep links for importing habits/tasks
                        Logger.info("Handling URL: \(url.absoluteString)", logger: Logger.app)
                        handleDeepLink(url)
                    }
            }
            // Allow system to control light/dark mode
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DailyQuoteNotificationTapped"))) { notification in
                // Handle notification when app is launched via notification
                Logger.info("Handling quote notification from app launch", logger: Logger.app)
            }
        }
    }
    
    init() {
        Logger.debug("Calendo App initialized", logger: Logger.app)
        // Firebase is configured in AppDelegate
    }
    
    // MARK: - Deep Link Handling
    
    private func handleDeepLink(_ url: URL) {
        // Check if it's a share link for importing habits/tasks
        // New format: calendo://share/type/shareId (backend-generated)
        // Old format: calendo://import/type?data=... (client-side, for backward compatibility)
        if url.scheme == "calendo" && (url.host == "share" || url.host == "import") {
            NotificationCenter.default.post(
                name: Notification.Name("ImportFromDeepLink"),
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
}

