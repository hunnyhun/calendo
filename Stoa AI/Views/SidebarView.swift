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
    @State private var showSubscriptionSuccessAlert = false
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Premium Banner - show for all non-premium users
            if !userStatusManager.state.isPremium {
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
            
            // Habits Button - available to all authenticated users
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
            
            // Tasks Button - available to all authenticated users
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
            
            
            // Chat history section with headers like ChatGPT
            VStack(spacing: 0) {
                // Chat history list
                ScrollView {
                    LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                        if chatViewModel.isLoadingHistory && chatViewModel.chatHistory.isEmpty {
                            // Show loading indicator while loading
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding()
                        } else if chatViewModel.chatHistory.isEmpty {
                            // Show no chats message if history is empty
                            Text("noChatsYet".localized)
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            // Display sections for all authenticated users
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
                    // User Info
                    if userStatusManager.state.isAuthenticated {
                            // Authenticated User - Enhanced User Info
                            HStack(spacing: 12) {
                                // Enhanced User Avatar with gradient ring
                                ZStack {
                                    // Gradient ring
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    userStatusManager.state.isPremium ? Color.brandPremium : Color.blue.opacity(0.6),
                                                    userStatusManager.state.isPremium ? Color.brandPremium.opacity(0.8) : Color.blue.opacity(0.4)
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
                                                    userStatusManager.state.isPremium ? Color.brandPremium.opacity(0.2) : Color.blue.opacity(0.2),
                                                    userStatusManager.state.isPremium ? Color.brandPremium.opacity(0.1) : Color.blue.opacity(0.1)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(userStatusManager.state.userEmail?.prefix(1).uppercased() ?? "U")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(userStatusManager.state.isPremium ? Color.brandPremium : .blue)
                                        )
                                }
                                
                                // Enhanced User Info
                                VStack(alignment: .leading, spacing: 4) {
                                    // User email with better typography
                                    if let email = userStatusManager.state.userEmail {
                                        Text(email)
                                            .font(.system(size: 14, weight: .medium))
                                            .lineLimit(1)
                                            .foregroundColor(userStatusManager.state.isPremium ? Color.brandPremium : .primary)
                                    }
                                    
                                    // Enhanced subscription tier with badge
                                    HStack(spacing: 6) {
                                        Text(userStatusManager.state.subscriptionTier.displayText.capitalized)
                                            .font(.system(size: 12, weight: userStatusManager.state.isPremium ? .semibold : .medium))
                                            .foregroundColor(userStatusManager.state.isPremium ? Color.brandPremium : .secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(userStatusManager.state.isPremium ? 
                                                  Color.brandPremium.opacity(0.1) : Color.gray.opacity(0.1))
                                    )
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(onPurchaseSuccess: {
                showSubscriptionSuccessAlert = true
                chatViewModel.startNewChat()
            })
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