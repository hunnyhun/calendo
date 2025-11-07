import SwiftUI

struct RemindersView: View {
    // Navigation binding for bottom bar
    @Binding var selectedFeature: Models.Feature
    @State private var viewModel: ReminderViewModel
    @State private var animateReminder = false
    let notificationManager = NotificationManager.shared
    let userStatusManager = UserStatusManager.shared
    
    // Initializer with navigation binding
    init(selectedFeature: Binding<Models.Feature> = .constant(.reminders)) {
        self._selectedFeature = selectedFeature
        // Initialize with no initial reminder since it's not from notification
        self._viewModel = State(initialValue: ReminderViewModel(fromNotification: false))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(.systemBackground)
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Main Reminder Card
                        VStack(spacing: 30) {
                            // App logo at the top
                            Image("logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .scaleEffect(animateReminder ? 1.0 : 0.8)
                                .opacity(animateReminder ? 1.0 : 0.3)
                            
                            // Reminder Content
                            if let reminder = viewModel.currentReminder {
                                Text(reminder)
                                    .font(.system(size: 24, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal)
                                    .scaleEffect(animateReminder ? 1.0 : 0.95)
                                    .opacity(animateReminder ? 1.0 : 0)
                            } else if viewModel.isLoading {
                                ProgressView()
                                    .frame(height: 50)
                            } else {
                                Text("noReminderAvailable".localized)
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray)
                            }
                            
                            // Date
                            if let date = viewModel.currentReminderDate {
                                Text(date, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.top, 20)
                        
                        // Previous Reminders Section
                        if userStatusManager.state.isAuthenticated {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Previous Reminders")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 20)
                                
                                if viewModel.isLoading {
                                    // Authenticated User - Loading State
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 30)
                                } else if viewModel.reminders.isEmpty {
                                    // Authenticated User - Empty State
                                    Text("noPreviousReminders".localized)
                                        .font(.system(size: 16))
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 30)
                                } else {
                                    // Authenticated User - List of Previous Reminders
                                    VStack(spacing: 15) {
                                        ForEach(viewModel.reminders) { reminder in
                                            PreviousReminderRow(
                                                reminder: reminder,
                                                onToggleFavorite: {
                                                    Task { await viewModel.toggleFavorite(for: reminder) }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom, 30)
                        }
                    }
                }
            }
            
            // Bottom Navigation Bar
            BottomNavigationBar(selectedFeature: $selectedFeature)
        }
        .background(Color(.systemBackground))
        .onAppear {
            // Clear notification count when view appears
            if notificationManager.unreadNotificationCount > 0 {
                print("📱 [RemindersView] Clearing \(notificationManager.unreadNotificationCount) notifications")
                notificationManager.markNotificationsAsRead()
            }
            
            // Load reminders and animate
            Task {
                await viewModel.loadReminders()
            }
            
            // Animate reminder appearance
            withAnimation(.easeInOut(duration: 0.6)) {
                animateReminder = true
            }
        }
    }
}

#Preview {
    RemindersView(selectedFeature: .constant(.reminders))
}

