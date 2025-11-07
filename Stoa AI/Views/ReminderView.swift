import SwiftUI
import FirebaseFirestore
import UIKit // Added for haptic feedback
import WidgetKit

// MARK: - Reminder Model
struct Reminder: Identifiable {
    // Rule: Always add debug logs & comment in the code
    let id: String
    let reminder: String
    let timestamp: Date
    let sentVia: String
    var isFavorite: Bool
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.reminder = data["reminder"] as? String ?? ""
        
        // Parse timestamp or use current date as fallback
        if let timestamp = data["timestamp"] as? Timestamp {
            self.timestamp = timestamp.dateValue()
        } else {
            self.timestamp = Date()
        }
        
        self.sentVia = data["sentVia"] as? String ?? "unknown"
        self.isFavorite = data["isFavorite"] as? Bool ?? false
    }
}

// MARK: - Reminder View Model
@Observable final class ReminderViewModel {
    // Properties
    var reminders: [Reminder] = []
    var isLoading = false
    var currentReminder: String?
    var currentReminderDate: Date?
    var fromNotification = false
    private let db = Firestore.firestore()
    
    // MARK: - Initialization
    init(initialReminder: String? = nil, fromNotification: Bool = false) {
        // Set initial reminder if provided (from notification)
        self.currentReminder = initialReminder
        self.fromNotification = fromNotification
        self.currentReminderDate = Date() // Default to today
        
        // Debug log
        print("🌟 [ReminderViewModel] Initialized with reminder: \(initialReminder ?? "none"), from notification: \(fromNotification)")
    }
    
    // MARK: - Load Reminders
    func loadReminders() async {
        // Debug log
        print("🌟 [ReminderViewModel] Loading reminders")
        
        guard let userId = UserStatusManager.shared.state.userId else {
            print("❌ [ReminderViewModel] Cannot load reminders - user not authenticated")
            return
        }
        
        isLoading = true
        
        do {
            // Get user's reminders
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("reminders")
                .order(by: "timestamp", descending: true)
                .limit(to: 30)
                .getDocuments()
            
            // Parse reminders
            let fetchedReminders = snapshot.documents.map { doc in
                Reminder(id: doc.documentID, data: doc.data())
            }
            
            // Update on main thread
            await MainActor.run {
                self.reminders = fetchedReminders
                
                // If we don't have a current reminder yet, use the most recent one
                if self.currentReminder == nil && !fetchedReminders.isEmpty {
                    self.currentReminder = fetchedReminders[0].reminder
                    self.currentReminderDate = fetchedReminders[0].timestamp
                    saveLastDailyReminderToAppGroup(fetchedReminders[0].reminder)
                } else if let current = self.currentReminder {
                    saveLastDailyReminderToAppGroup(current)
                }
                
                self.isLoading = false
            }
            
            print("✅ [ReminderViewModel] Loaded \(fetchedReminders.count) reminders")
        } catch {
            print("❌ [ReminderViewModel] Error loading reminders: \(error.localizedDescription)")
            
            // Update on main thread
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Toggle Favorite
    func toggleFavorite(for reminder: Reminder) async {
        // Debug log
        print("🌟 [ReminderViewModel] Toggling favorite for reminder: \(reminder.id)")
        
        do {
            // Toggle favorite status
            try await DailyQuoteFunctions.shared.updateQuoteFavoriteStatus(
                quoteId: reminder.id,
                isFavorite: !reminder.isFavorite
            )
            
            // Refresh reminders
            await loadReminders()
            
        } catch {
            print("❌ [ReminderViewModel] Error toggling favorite: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Save Current Reminder as Favorite
    func saveCurrentReminderAsFavorite() async {
        // Debug log
        print("🌟 [ReminderViewModel] Saving current reminder as favorite")
        
        guard let reminder = currentReminder else {
            print("❌ [ReminderViewModel] No current reminder to save")
            return
        }
        
        do {
            // Save to favorites
            try await DailyQuoteFunctions.shared.saveQuoteToFavorites(quote: reminder)
            
            // Refresh reminders
            await loadReminders()
            
        } catch {
            print("❌ [ReminderViewModel] Error saving favorite: \(error.localizedDescription)")
        }
    }
    
    // MARK: - App Group Helper
    func saveLastDailyReminderToAppGroup(_ reminder: String) {
        let sharedDefaults = UserDefaults(suiteName: "group.com.hunnyhun.stoicism")
        sharedDefaults?.set(reminder, forKey: "lastDailyReminder")
        print("[ReminderView] Saved last reminder to App Group: \(reminder)")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Reminder View
struct ReminderView: View {
    // Rule: Always add debug logs
    @State private var viewModel: ReminderViewModel
    @State private var animateReminder = false
    @State private var showFromNotificationBadge = false
    @State private var showAuthView = false
    @Environment(\.dismiss) private var dismiss
    let userStatusManager = UserStatusManager.shared
    
    // MARK: - Initialization
    init(initialReminder: String? = nil, fromNotification: Bool = false) {
        _viewModel = State(initialValue: ReminderViewModel(initialReminder: initialReminder, fromNotification: fromNotification))
        _showFromNotificationBadge = State(initialValue: fromNotification)
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 25) {
                        if showFromNotificationBadge {
                            notificationBadge
                                .padding(.top, 12)
                        }
                        
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
                                    .foregroundColor(.black)
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.gray)
                                    .opacity(animateReminder ? 1.0 : 0)
                            }
                        }
                        .padding(.vertical, 30)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Previous Reminders Section
                        VStack(alignment: .leading, spacing: 15) {
                            Text("previousReminders".localized)
                                .font(.title3)
                                .fontWeight(.bold)
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                            
                            // Check if user is not authenticated
                            if !userStatusManager.state.isAuthenticated {
                                // Sign In Prompt - Make tappable
                                Button { 
                                    showAuthView = true // Trigger auth sheet
                                } label: {
                                    VStack(spacing: 10) {
                                        Image(systemName: "person.crop.circle.badge.questionmark.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.yellow.opacity(0.7))
                                        Text("signInToViewDailyReminders".localized) // Updated text & key
                                            .font(.headline)
                                            .multilineTextAlignment(.center)
                                        // Subtitle removed
                                    }
                                    .padding(.vertical, 30)
                                    .padding(.horizontal, 30)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.yellow.opacity(0.05))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle()) // Use plain style to keep background
                                .padding(.horizontal, 20) // Add padding to the prompt box
                            } else if viewModel.isLoading {
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
                                    // Skip the first reminder if it's the current reminder
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
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("reminders".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Debug log
                        print("📝 [ReminderView] Close button tapped")
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(Color(.systemGray6))
                            )
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear {
                // Debug log
                print("📝 [ReminderView] View appeared")
                Task {
                    await viewModel.loadReminders()
                    
                    // Trigger animation after reminders are loaded
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                        animateReminder = true
                    }
                    
                    // Hide notification badge after a delay
                    if showFromNotificationBadge {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                showFromNotificationBadge = false
                            }
                        }
                    }
                }
                // Clear badge count when viewing reminders
                NotificationManager.shared.markNotificationsAsRead()
            }
        }
        .sheet(isPresented: $showAuthView) {
            AuthenticationView(onAuthenticationSuccess: nil)
        }
    }
    
    // MARK: - Helper Views
    
    // Notification Badge View
    private var notificationBadge: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Text("fromNotification".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Previous Reminder Row Component
struct PreviousReminderRow: View {
    let reminder: Reminder
    let onToggleFavorite: () -> Void
    
    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 15) {
                // App logo icon
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Reminder Text
                    Text(reminder.reminder)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    // Verse Reference (if applicable)
                    if reminder.reminder.contains("—") {
                        let components = reminder.reminder.components(separatedBy: "—")
                        if components.count > 1 {
                            Text(components[1].trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Date
                    Text(reminder.timestamp, style: .date)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Favorite Button
                Button(action: onToggleFavorite) {
                    Image(systemName: reminder.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(reminder.isFavorite ? .red : .gray.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 15)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
        }
    }
}

// Preview Provider
#if DEBUG
struct ReminderView_Previews: PreviewProvider {
    static var previews: some View {
        // Provide mock data for preview
        ReminderView(initialReminder: "This is a sample reminder for the preview.", fromNotification: true)
    }
}
#endif 

