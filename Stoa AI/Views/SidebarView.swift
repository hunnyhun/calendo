import SwiftUI

struct SidebarView: View {
    // MARK: - Properties
    let userStatusManager = UserStatusManager.shared
    let notificationManager = NotificationManager.shared
    @Binding var showAuthView: Bool
    @Binding var selectedFeature: Models.Feature?
    let chatViewModel: ChatViewModel
    @State private var showPaywall = false
    @State private var showAccountMenu = false
    @State private var showSettings = false
    @State private var showDailyQuote = false
    @State private var showSubscriptionSuccessAlert = false
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Premium Banner - keep as requested
            if !userStatusManager.state.isPremium && !userStatusManager.state.isAnonymous {
                Button(action: {
                    print("DEBUG: Opening paywall")
                    showPaywall = true
                }) {
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .foregroundColor(.white)
                        Text("upgradeToPremiumButton".localized)
                            .bold()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.brandBrightGreen)
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            
            // Daily Quote Button
            Button(action: {
                // Clear notification count before showing view
                if notificationManager.unreadNotificationCount > 0 {
                    print("📱 [SidebarView] Clearing \(notificationManager.unreadNotificationCount) notifications")
                    notificationManager.markNotificationsAsRead()
                }
                
                // Then show the daily quote view
                print("📱 [SidebarView] Opening Daily Quote view")
                showDailyQuote = true
            }) {
                HStack {
                            Image(systemName: "quote.bubble.fill")
                            .foregroundColor(Color.brandPrimary)
                    Text("dailySpiritualQuote".localized)
                        .bold()
                    Spacer()
                    
                    // Badge showing unread notification count
                    if notificationManager.unreadNotificationCount > 0 {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 22, height: 22)
                            
                            Text("\(notificationManager.unreadNotificationCount)")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.white)
                        }
                    }
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .foregroundColor(.primary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .padding(.top, 8)
            
            // Habits Button - only for authenticated (non-anonymous) users
            if userStatusManager.state.isAuthenticated && !userStatusManager.state.isAnonymous {
                Button(action: {
                    print("📱 [SidebarView] Opening Habits view")
                    selectedFeature = .habits
                }) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(Color.brandPrimary)
                        Text("My Habits")
                            .bold()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            
            // Tasks Button - only for authenticated (non-anonymous) users
            if userStatusManager.state.isAuthenticated && !userStatusManager.state.isAnonymous {
                Button(action: {
                    print("📱 [SidebarView] Opening Tasks view")
                    selectedFeature = .tasks
                }) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(Color.brandPrimary)
                        Text("My Tasks")
                            .bold()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            
            // Calendar Button - only for authenticated (non-anonymous) users
            if userStatusManager.state.isAuthenticated && !userStatusManager.state.isAnonymous {
                Button(action: {
                    print("📱 [SidebarView] Opening Calendar view")
                    selectedFeature = .calendar
                }) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(Color.brandPrimary)
                        Text("Calendar")
                            .bold()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }

            // Settings Button for Anonymous Users
            if userStatusManager.state.isAnonymous {
                Button { 
                    showSettings = true
                } label: {
                     HStack {
                        Image(systemName: "gearshape.fill") // Settings icon
                            .foregroundColor(.gray)
                        Text("settingsButtonLabel".localized) // Use localized key
                            .bold()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .padding(.top, 8) // Spacing below daily quote button
            }
            
            // Chat history section with headers like ChatGPT
            VStack(spacing: 0) {
                // Chat history list
                ScrollView {
                    LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                        if userStatusManager.state.isAnonymous {
                            // Show message for anonymous users
                            Text("signInToViewHistory".localized) // Use localized key
                                .foregroundColor(.secondary)
                                .font(.footnote)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else if chatViewModel.isLoadingHistory && chatViewModel.chatHistory.isEmpty {
                            // Show loading indicator if not anonymous and loading
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding()
                        } else if chatViewModel.chatHistory.isEmpty {
                            // Show no chats message if not anonymous and history is empty
                            Text("noChatsYet".localized)
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            // Display sections if not anonymous and history is loaded
                            ForEach(chatViewModel.sectionedHistory, id: \.section.id) { section in
                                Section(header: sectionHeader(title: section.section.rawValue)) {
                                    ForEach(section.conversations) { history in
                                        chatHistoryRow(history: history)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxHeight: .infinity)
            
            // User profile at bottom - Stylish version
            VStack(spacing: 0) {
                // Subtle divider
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // User content
                HStack(spacing: 0) {
                    // User Info or Sign In Button
                    if userStatusManager.state.isAuthenticated {
                        if userStatusManager.state.isAnonymous {
                            // Anonymous User - Enhanced Sign In Prompt
                            VStack(spacing: 12) {
                                // Icon and promotional text
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.yellow.opacity(0.8))
                                    
                                    Text("signUpBenefitText".localized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Enhanced Sign In Button
                                Button { 
                                    showAuthView = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "star.circle.fill")
                                            .font(.system(size: 16, weight: .medium))
                                        
                                        Text("signUpOrLogIn".localized)
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.yellow.opacity(0.9),
                                                Color.orange.opacity(0.8)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                                    .shadow(color: Color.yellow.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .scaleEffect(1.0)
                                .animation(.easeInOut(duration: 0.2), value: userStatusManager.state.isAnonymous)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                        } else {
                            // Authenticated User - Enhanced User Info
                            HStack(spacing: 12) {
                                // Enhanced User Avatar with gradient ring
                                ZStack {
                                    // Gradient ring
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    userStatusManager.state.isPremium ? Color.yellow : Color.blue.opacity(0.6),
                                                    userStatusManager.state.isPremium ? Color.orange : Color.blue.opacity(0.4)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                        .frame(width: 44, height: 44)
                                    
                                    // Main avatar circle
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    userStatusManager.state.isPremium ? Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.2) : Color.blue.opacity(0.2),
                                                    userStatusManager.state.isPremium ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(userStatusManager.state.userEmail?.prefix(1).uppercased() ?? "U")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(userStatusManager.state.isPremium ? Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.9) : .blue)
                                        )
                                }
                                
                                // Enhanced User Info
                                VStack(alignment: .leading, spacing: 4) {
                                    // User email with better typography
                                    if let email = userStatusManager.state.userEmail {
                                        Text(email)
                                            .font(.system(size: 14, weight: .medium))
                                            .lineLimit(1)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    // Enhanced subscription tier with badge
                                    HStack(spacing: 6) {
                                        if userStatusManager.state.isPremium {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.8))
                                        }
                                        
                                        Text(userStatusManager.state.subscriptionTier.displayText.capitalized)
                                            .font(.system(size: 12, weight: userStatusManager.state.isPremium ? .semibold : .medium))
                                            .foregroundColor(userStatusManager.state.isPremium ? Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.9) : .secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(userStatusManager.state.isPremium ? 
                                                  Color.yellow.opacity(0.1) : Color.gray.opacity(0.1))
                                    )
                                }
                                
                                Spacer()
                                
                                // Enhanced Settings Button with hover effect
                                Button(action: {
                                    showSettings = true
                                }) {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.gray.opacity(0.8))
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle()
                                                .fill(Color.gray.opacity(0.1))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                }
                                .scaleEffect(1.0)
                                .animation(.easeInOut(duration: 0.2), value: showSettings)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                    }
                    // No need for an else here, as ContentView handles initial anonymous login
                }
            }
            .background(
                // Subtle background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSettings) {
            SettingsView(showPaywall: $showPaywall)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onPurchaseSuccess: {
                showSubscriptionSuccessAlert = true
                chatViewModel.startNewChat()
            })
        }
        .sheet(isPresented: $showDailyQuote) {
            DailyQuoteView(fromNotification: false)
        }
        .alert("subscriptionSuccessTitle".localized, isPresented: $showSubscriptionSuccessAlert) {
            Button("ok".localized) { }
        } message: {
            Text("subscriptionSuccessMessage".localized)
        }
    }
    
    // MARK: - Section Header
    private func sectionHeader(title: String) -> some View {
        // Use localized string - this will use the rawValue as a key in the strings files
        Text(title.localized)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
    }
    
    // MARK: - Chat History Row
    private func chatHistoryRow(history: ChatHistory) -> some View {
        Button(action: {
            print("DEBUG: Loading conversation: \(history.id)")
            chatViewModel.loadConversation(history)
            selectedFeature = .chat
        }) {
            HStack(alignment: .center, spacing: 12) {
                // Tick icon with brand green color
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.brandPrimary)
                    .font(.system(size: 16, weight: .medium))
                
                // Chat title and preview
                VStack(alignment: .leading, spacing: 2) {
                    // Title with better styling
                    Text(history.title)
                        .lineLimit(1)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(chatViewModel.currentConversation?.id == history.id ? .blue : .primary)
                    
                    // Last message preview with better styling
                    Text(history.lastMessage)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 4)
                
                // Add timestamp if needed
                Text(history.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(chatViewModel.currentConversation?.id == history.id ? 
                          Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationStack {
        SidebarView(
            showAuthView: .constant(false),
            selectedFeature: .constant(.chat),
            chatViewModel: ChatViewModel()
        )
    }
} 