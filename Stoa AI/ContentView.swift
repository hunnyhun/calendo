import SwiftUI

// MARK: - Keyboard Extension
#if canImport(UIKit)
import UIKit
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

struct ContentView: View {
    // MARK: - Properties
    let userStatusManager = UserStatusManager.shared
    let notificationManager = NotificationManager.shared
    @State private var showPaywall = false
    @State private var showAuthView = false
    @State private var selectedFeature: Models.Feature? = .chat
    @State private var showSidebar = false
    @State private var chatViewModel = ChatViewModel()
    @State private var sidebarRefreshTrigger = UUID()
    @State private var lastRefreshTime = Date()
    @State private var showSubscriptionSuccessAlert = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var sidebarView: SidebarView?
    @State private var justLoggedIn = false  // Track if user just logged in
    @AppStorage("app_theme") private var appTheme: String = "light" // "light" or "dark"
    
    
    // MARK: - Onboarding state
    @State private var showOnboarding = false
    @State private var hasCheckedOnboarding = false
    
    // MARK: - Authentication check state
    @State private var hasCheckedInitialAuth = false
    
    // MARK: - Body
    var body: some View {
        Group {
            if !hasCheckedInitialAuth || userStatusManager.isLoading {
                // Show loading state during initial authentication check
                // This prevents the flash of auth view when user is already authenticated
                Color(.systemBackground)
                    .ignoresSafeArea()
            } else if userStatusManager.state.isAuthenticated {
                // Show main content only if authenticated
                mainContent
                    .transition(.opacity)
            } else {
                // Show authentication view if not authenticated
                AuthenticationView(onAuthenticationSuccess: nil)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userStatusManager.state.isAuthenticated)
        .preferredColorScheme(appTheme == "dark" ? .dark : .light)
        .task {
            // Check user status during initial load
            await userStatusManager.refreshUserState()
            // Mark that initial check is complete
            hasCheckedInitialAuth = true
            
            // Initialize app if user is authenticated
            if userStatusManager.state.isAuthenticated {
                chatViewModel.loadChatHistory()
                
                // Check notification permissions (but don't show prompt yet)
                let permissionStatus = await notificationManager.checkNotificationStatus()
                print("📱 [ContentView] Initial notification permission status: \(permissionStatus)")
                
                // Ensure device registration for authenticated users
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds delay
                    await notificationManager.ensureDeviceRegistration()
                    
                    // Run diagnostics to help track device registration issues
                    await notificationManager.diagnoseDeviceRegistration()
                }
            }
            
        // Setup notification observers
        setupNotificationObservers()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserStateChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let authStatus = userInfo["authStatus"] as? String,
               authStatus == "authenticated" {
                // User just logged in
                print("📱 [ContentView] User just logged in, will show notification prompt")
                justLoggedIn = true
                
                // Show notification prompt after a delay to allow UI to settle
                // Notification permission is now handled in onboarding flow
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToHabitsView"))) { _ in
            print("📱 [ContentView] Switching to habits view")
            selectedFeature = .habits
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToTasksView"))) { _ in
            print("📱 [ContentView] Switching to tasks view")
            selectedFeature = .tasks
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Refresh data when app becomes active
                if userStatusManager.state.isAuthenticated {
                    chatViewModel.loadChatHistory()
                    
                    // Reset the just logged in flag
                    justLoggedIn = false
                }
            }
            else if newPhase == .background {
                // Ensure badge count is synchronized when going to background
                print("📱 [ContentView] App entering background, ensuring badge count is synchronized")
                NotificationManager.shared.synchronizeBadgeCount()
                dismissKeyboardAndCloseSidebar()
            }
            else if newPhase != .active {
                dismissKeyboardAndCloseSidebar()
            }
        }
        .alert("subscriptionSuccessTitle".localized, isPresented: $showSubscriptionSuccessAlert) {
            Button("ok".localized) { }
        } message: {
            Text("subscriptionSuccessMessage".localized)
        }
        .onAppear {
            // Check if user has completed onboarding (local only for first launch)
            if !hasCheckedOnboarding {
                let hasCompletedOnboarding = OnboardingManager.shared.checkLocalOnboardingStatus()
                // Only show onboarding if not completed AND user is not authenticated
                // If user is authenticated but onboarding not done, they'll complete it in the auth page
                showOnboarding = !hasCompletedOnboarding
                hasCheckedOnboarding = true
                
                // Sync with remote status in background (but don't affect onboarding display)
                Task {
                    await OnboardingManager.shared.checkOnboardingStatus()
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding, onCompletion: {
                // After onboarding completes (which includes auth), show paywall
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showPaywall = true
                }
            })
        }
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                // Sidebar overlay for visual effect & tap-to-close
                if showSidebar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: showSidebar)
                        .onTapGesture {
                            dismissKeyboardAndCloseSidebar()
                        }
                        .zIndex(1)
                }
                
                // Sidebar
                let view = SidebarView(
                    showAuthView: $showAuthView,
                    selectedFeature: $selectedFeature,
                    chatViewModel: chatViewModel
                )
                view
                    .frame(width: 300)
                    .frame(maxWidth: 300, alignment: .leading)
                    .offset(x: showSidebar ? 0 : -300)
                    .zIndex(2)
                    .id(sidebarRefreshTrigger)
                    .onAppear {
                        sidebarView = view
                    }
                
                // Main Content with Navigation
                VStack(spacing: 0) {
                    // Main Content View - passing sidebar control
                    Group {
                        switch selectedFeature {
                        case .chat:
                            ChatView(
                                viewModel: chatViewModel,
                                showSidebarCallback: $showSidebar,
                                selectedFeature: Binding(
                                    get: { selectedFeature ?? .chat },
                                    set: { selectedFeature = $0 }
                                )
                            )
                        case .calendar:
                            CalendarView(
                                selectedFeature: Binding(
                                    get: { selectedFeature ?? .calendar },
                                    set: { selectedFeature = $0 }
                                )
                            )
                        case .reminders:
                            RemindersView(
                                selectedFeature: Binding(
                                    get: { selectedFeature ?? .reminders },
                                    set: { selectedFeature = $0 }
                                )
                            )
                        case .tracking:
                            TrackingView(
                                selectedFeature: Binding(
                                    get: { selectedFeature ?? .tracking },
                                    set: { selectedFeature = $0 }
                                )
                            )
                        case .settings:
                            SettingsViewWrapper(
                                selectedFeature: Binding(
                                    get: { selectedFeature ?? .settings },
                                    set: { selectedFeature = $0 }
                                ),
                                showPaywall: $showPaywall
                            )
                        case .tasks:
                            TaskTrackingView(onNavigateBack: {
                                selectedFeature = .chat
                            })
                        case .habits:
                            HabitTrackingView(onNavigateBack: {
                                selectedFeature = .chat
                            })
                        case .blog:
                            BlogView(
                                selectedFeature: Binding(
                                    get: { selectedFeature ?? .blog },
                                    set: { selectedFeature = $0 }
                                )
                            )
                        case .none:
                            ChatView(
                                viewModel: chatViewModel,
                                showSidebarCallback: $showSidebar,
                                selectedFeature: Binding(
                                    get: { selectedFeature ?? .chat },
                                    set: { selectedFeature = $0 }
                                )
                            )
                        }
                    }
                    .id(selectedFeature)
                    .disabled(showSidebar) // Disable interaction when sidebar is open
                }
                .background(Color(.systemBackground))
            }
            .navigationBarHidden(true)
            .overlay {
                if userStatusManager.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showAuthView) {
                AuthenticationView(onAuthenticationSuccess: {
                    chatViewModel.startNewChat()
                })
                .onDisappear {
                    if userStatusManager.state.isAuthenticated {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            refreshSidebar()
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onPurchaseSuccess: {
                    showSubscriptionSuccessAlert = true
                    chatViewModel.startNewChat()
                })
                .onDisappear {
                    if userStatusManager.state.isPremium {
                        withAnimation {
                            refreshSidebar()
                        }
                        chatViewModel.loadChatHistory()
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { gesture in
                        let threshold: CGFloat = 50
                        if gesture.translation.width > threshold && !showSidebar {
                            dismissKeyboardAndOpenSidebar()
                        } else if gesture.translation.width < -threshold && showSidebar {
                            dismissKeyboardAndCloseSidebar()
                        }
                    }
            )
            .onChange(of: selectedFeature) { _, _ in
                dismissKeyboardAndCloseSidebar()
            }
            .onChange(of: userStatusManager.state.isPremium) { _, isPremium in
                if isPremium {
                    chatViewModel.loadChatHistory()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func refreshSidebar() {
        guard userStatusManager.state.isPremium else { return }
        
        let now = Date()
        if now.timeIntervalSince(lastRefreshTime) > 0.5 {
            withAnimation {
                chatViewModel.loadChatHistory()
                sidebarRefreshTrigger = UUID()
                lastRefreshTime = now
                print("[ContentView] Refreshed sidebar at \(now)")
            }
        }
    }
    
    private func dismissKeyboardAndOpenSidebar() {
        hideKeyboard()
        withAnimation(.easeInOut(duration: 0.3)) {
            showSidebar = true
            if userStatusManager.state.isPremium {
                refreshSidebar()
            }
        }
    }
    
    private func dismissKeyboardAndCloseSidebar() {
        hideKeyboard()
        withAnimation(.easeInOut(duration: 0.3)) {
            showSidebar = false
        }
    }
    
    // MARK: - Notification Handling
    private func setupNotificationObservers() {
        print("📱 [ContentView] Setting up notification observers")
        
        // Remove any existing observers
        NotificationCenter.default.removeObserver(self)
        
        // Add observer for reminder notification taps
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OpenDailyQuoteView"),
            object: nil,
            queue: .main
        ) { notification in
            // Extract quote from notification
            if let userInfo = notification.userInfo,
               let _ = userInfo["quote"] as? String {
                print("📱 [ContentView] Received open reminder view notification")
                
                // Clear notification count before showing view
                if NotificationManager.shared.unreadNotificationCount > 0 {
                    print("📱 [ContentView] Clearing \(NotificationManager.shared.unreadNotificationCount) notifications")
                    NotificationManager.shared.markNotificationsAsRead()
                }
                
                // Close sidebar if it's open
                if self.showSidebar {
                    self.dismissKeyboardAndCloseSidebar()
                }
                
                // Switch to reminders view with a slight delay to ensure UI transitions
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("📱 [ContentView] Opening Reminders view")
                    self.selectedFeature = .reminders
                }
            }
        }
    }
    
    // MARK: - User Login Handler
    private func handleUserLogin() {
        // Notification permission is now handled in onboarding flow
    }
    
    private func handleUserLoginAsync() async {
        // Notification permission is now handled in onboarding flow
    }
    
    // MARK: - Notification Permission Helper
    private func checkNotificationPermission(afterDelay: TimeInterval) {
        Task {
            // Check if notifications are authorized
            let isAuthorized = await notificationManager.checkNotificationStatus()
            print("📱 [ContentView] Notification permission check: \(isAuthorized ? "Authorized" : "Not Authorized")")
            
            // If not authorized and this is a first login, request permission directly
            if !isAuthorized && justLoggedIn {
                // Request after delay to allow transitions to complete
                try? await Task.sleep(nanoseconds: UInt64(afterDelay * 1_000_000_000))
                print("📱 [ContentView] Directly requesting system notification permission")
                await requestNotificationPermission()
            }
        }
    }
    
    // MARK: - Request Notification Permission
    private func requestNotificationPermission() async {
        // Directly call the centralized permission request method
        print("📱 [ContentView] Requesting notification permission")
        let _ = await notificationManager.requestNotificationPermission()
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
