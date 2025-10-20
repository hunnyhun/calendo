import SwiftUI
import FirebaseAuth

// MARK: - Main Habit Tracking View
struct HabitTrackingView: View {
    @ObservedObject private var habitManager = HabitManager.shared
    let userStatusManager = UserStatusManager.shared
    var onNavigateToHabitChat: (() -> Void)? = nil
    var onNavigateBack: (() -> Void)? = nil
    
    @State private var showingHabitCreation = false
    @State private var showingHabitDetail: ComprehensiveHabit?
    @State private var selectedTab = 0
    @State private var showingAnonymousAlert = false
    @State private var showingLimitAlert = false
    @State private var showingAuthView = false
    @State private var showingPaywall = false
    
    private var userStatus: Models.UserStatus {
        if userStatusManager.state.isAuthenticated {
            return .loggedIn(isPremium: userStatusManager.state.isPremium)
        } else {
            return .anonymous
        }
    }
    
    private var canAccessHabits: Bool {
        Models.HabitAccessHelper.canAccessHabitMode(userStatus: userStatus)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button, title and add button
            HStack {
                // Back button
                Button(action: {
                    onNavigateBack?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Back")
                            .font(.headline)
                    }
                    .foregroundColor(.brandPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Habits")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Build virtue through consistent practice")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    handleHabitCreation()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.brandPrimary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
                
                // Tab selection
                Picker("View", selection: $selectedTab) {
                    Text("Today").tag(0)
                    Text("All Habits").tag(1)
                    Text("Progress").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                // Content based on selected tab
                if canAccessHabits {
                    TabView(selection: $selectedTab) {
                        // Today's habits
                        TodayHabitsView(
                            habitManager: habitManager,
                            onCreateHabit: handleHabitCreation
                        )
                        .tag(0)
                        
                        // All habits
                        AllHabitsView(
                            habitManager: habitManager,
                            showingHabitDetail: $showingHabitDetail
                        )
                        .tag(1)
                        
                        // Progress view
                        HabitProgressView(habitManager: habitManager)
                            .tag(2)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                } else {
                    // Show login required view
                    VStack(spacing: 24) {
                        Spacer()
                        
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 80))
                            .foregroundColor(.brandPrimary)
                        
                        VStack(spacing: 12) {
                            Text("Sign In Required")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Create an account to access habit tracking and build your philosophical practices")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        Button(action: {
                            showingAuthView = true
                        }) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Sign Up or Log In")
                            }
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                }
            }
            .onAppear {
                if canAccessHabits {
                    Task {
                        await habitManager.loadHabits()
                    }
                }
            }
            .sheet(item: $showingHabitDetail) { habit in
                HabitDetailView(habit: habit, habitManager: habitManager)
            }
            .sheet(isPresented: $showingAnonymousAlert) {
                AnonymousHabitLimitSheet(
                    isPresented: $showingAnonymousAlert,
                    onSignUp: {
                        showingAnonymousAlert = false
                        showingAuthView = true
                    },
                    onDismiss: {
                        showingAnonymousAlert = false
                    }
                )
            }
            .sheet(isPresented: $showingLimitAlert) {
                FreeUserHabitLimitSheet(
                    isPresented: $showingLimitAlert,
                    currentHabitCount: habitManager.habits.count,
                    onUpgrade: {
                        showingLimitAlert = false
                        showingPaywall = true
                    },
                    onDismiss: {
                        showingLimitAlert = false
                    }
                )
            }
            .sheet(isPresented: $showingAuthView) {
                AuthenticationView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
        
        // MARK: - Helper Functions
        
        private func handleHabitCreation() {
            let accessResult = Models.HabitAccessHelper.canCreateHabit(
                userStatus: userStatus,
                currentHabitCount: habitManager.habits.count
            )
            
            switch accessResult {
            case .allowed:
                // Call the navigation callback if provided, otherwise post notification
                if let onNavigateToHabitChat = onNavigateToHabitChat {
                    onNavigateToHabitChat()
                } else {
                    // Fallback: Post notification to switch ChatView to habit mode
                    NotificationCenter.default.post(name: Notification.Name("SwitchToHabitMode"), object: nil)
                }
            case .requiresLogin:
                showingAnonymousAlert = true
            case .requiresPremium:
                showingLimitAlert = true
            }
        }
    }

// MARK: - Today's Habits View
struct TodayHabitsView: View {
    @ObservedObject var habitManager: HabitManager
    let onCreateHabit: () -> Void
    @State private var showingCheckIn: ComprehensiveHabit?
    
    private var todayHabits: [ComprehensiveHabit] {
        habitManager.habits.filter { habit in
            // Derive frequency from schedule
            let frequency: HabitFrequency
            if let lowLevelSchedule = habit.lowLevelSchedule {
                switch lowLevelSchedule.span {
                case "daily":
                    frequency = .daily
                case "weekly":
                    frequency = .weekly
                case "every-n-days":
                    if let interval = lowLevelSchedule.spanInterval {
                        frequency = .custom(days: interval)
                    } else {
                        frequency = .daily
                    }
                default:
                    frequency = .daily
                }
            } else {
                frequency = .daily
            }
            
            // Filter habits that should be done today
            switch frequency {
            case .daily:
                return true
            case .weekly:
                return Calendar.current.component(.weekday, from: Date()) == 2 // Monday
            case .custom(let days):
                let formatter = ISO8601DateFormatter()
                let createdAt = formatter.date(from: habit.createdAt) ?? Date()
                let daysSinceCreation = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
                return daysSinceCreation % days == 0
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if todayHabits.isEmpty {
                    EmptyHabitsView(onCreateHabit: onCreateHabit)
                } else {
                    ForEach(todayHabits) { habit in
                        TodayHabitCard(
                            habit: habit,
                            isCompleted: habitManager.isHabitCompletedToday(habit),
                            onCheckIn: {
                                showingCheckIn = habit
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sheet(item: $showingCheckIn) { habit in
            HabitCheckInView(habit: habit, habitManager: habitManager)
        }
    }
}

// MARK: - Today Habit Card
struct TodayHabitCard: View {
    let habit: ComprehensiveHabit
    let isCompleted: Bool
    let onCheckIn: () -> Void
    
    // Break down complex expressions into computed properties
    private var categoryIcon: some View {
        Image(systemName: displayCategory.icon)
            .font(.title2)
            .foregroundColor(Color(displayCategory.color))
            .frame(width: 40, height: 40)
            .background(Color(displayCategory.color).opacity(0.1))
            .clipShape(Circle())
    }
    
    // Convert string category to HabitCategory for display
    private var displayCategory: HabitCategory {
        let categoryString = habit.category?.lowercased() ?? "personal growth"
        switch categoryString {
        case "physical", "fitness", "health":
            return .physical
        case "mental", "mindfulness", "meditation":
            return .mindfulness
        case "spiritual", "spirituality":
            return .spiritual
        case "social", "relationships":
            return .social
        case "productivity", "work", "career":
            return .productivity
        case "learning", "education", "study":
            return .learning
        default:
            return .personalGrowth
        }
    }
    
    // Derive frequency from schedule
    private var displayFrequency: HabitFrequency {
        if let lowLevelSchedule = habit.lowLevelSchedule {
            switch lowLevelSchedule.span {
            case "daily":
                return .daily
            case "weekly":
                return .weekly
            case "every-n-days":
                if let interval = lowLevelSchedule.spanInterval {
                    return .custom(days: interval)
                }
                return .daily
            default:
                return .daily
            }
        }
        return .daily
    }
    
    // Derive duration from schedule
    private var displayDuration: String? {
        if let lowLevelSchedule = habit.lowLevelSchedule,
           let firstProgram = lowLevelSchedule.program.first,
           let firstStep = firstProgram.steps.first,
           let durationMinutes = firstStep.durationMinutes {
            return "\(durationMinutes) minutes"
        }
        return nil
    }
    
    private var habitInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(habit.name)
                .font(.headline)
                .foregroundColor(.primary)
            
            frequencyInfo
            
            trackingInfo
        }
    }
    
    private var frequencyInfo: some View {
        HStack {
            Text(displayFrequency.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let duration = displayDuration {
                Text("• \(duration)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var trackingInfo: some View {
        if let trackingMethod = habit.trackingMethod {
            Text("📊 \(trackingMethod)")
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(.top, 2)
                .lineLimit(1)
        }
    }
    
    private var checkInButton: some View {
        Button(action: onCheckIn) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isCompleted ? .green : .gray)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isCompleted ? Color.green.opacity(0.05) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isCompleted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }
    
    var body: some View {
        HStack(spacing: 16) {
            categoryIcon
            habitInfo
            Spacer()
            checkInButton
        }
        .padding(16)
        .background(cardBackground)
    }
}

// MARK: - All Habits View
struct AllHabitsView: View {
    @ObservedObject var habitManager: HabitManager
    @Binding var showingHabitDetail: ComprehensiveHabit?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(habitManager.habits) { habit in
                    HabitSummaryCard(
                        habit: habit,
                        stats: habitManager.getStats(for: habit),
                        onTap: {
                            showingHabitDetail = habit
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Habit Summary Card
struct HabitSummaryCard: View {
    let habit: ComprehensiveHabit
    let stats: HabitStats?
    let onTap: () -> Void
    
    // Convert string category to HabitCategory for display
    private var displayCategory: HabitCategory {
        let categoryString = habit.category?.lowercased() ?? "personal growth"
        switch categoryString {
        case "physical", "fitness", "health":
            return .physical
        case "mental", "mindfulness", "meditation":
            return .mindfulness
        case "spiritual", "spirituality":
            return .spiritual
        case "social", "relationships":
            return .social
        case "productivity", "work", "career":
            return .productivity
        case "learning", "education", "study":
            return .learning
        default:
            return .personalGrowth
        }
    }
    
    // Derive frequency from schedule
    private var displayFrequency: HabitFrequency {
        if let lowLevelSchedule = habit.lowLevelSchedule {
            switch lowLevelSchedule.span {
            case "daily":
                return .daily
            case "weekly":
                return .weekly
            case "every-n-days":
                if let interval = lowLevelSchedule.spanInterval {
                    return .custom(days: interval)
                }
                return .daily
            default:
                return .daily
            }
        }
        return .daily
    }
    
    // Derive duration from schedule
    private var displayDuration: String? {
        if let lowLevelSchedule = habit.lowLevelSchedule,
           let firstProgram = lowLevelSchedule.program.first,
           let firstStep = firstProgram.steps.first,
           let durationMinutes = firstStep.durationMinutes {
            return "\(durationMinutes) minutes"
        }
        return nil
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: displayCategory.icon)
                        .font(.title3)
                        .foregroundColor(Color(displayCategory.color))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(displayCategory.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let stats = stats {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(stats.completionRate * 100))%")
                                .font(.headline)
                                .foregroundColor(stats.isOnTrack ? .green : .orange)
                            
                            Text("\(stats.currentStreak) day streak")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if !habit.description.isEmpty {
                    Text(habit.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Label(displayFrequency.displayText, systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let duration = displayDuration {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Empty Habits View
struct EmptyHabitsView: View {
    let onCreateHabit: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "target")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Habits Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Start building virtue through daily practices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Create Your First Habit") {
                onCreateHabit()
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.brandPrimary)
            .clipShape(Capsule())
        }
        .padding(40)
    }
}

// MARK: - Habit Progress View (Stub)
struct HabitProgressView: View {
    @ObservedObject var habitManager: HabitManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Progress Analytics")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Coming Soon")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // This will be expanded in future iterations
                VStack(spacing: 16) {
                    Text("📊 Detailed habit analytics")
                    Text("📈 Progress trends and insights")
                    Text("🏆 Achievement badges")
                    Text("📅 Calendar view")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
            .padding(40)
        }
    }
}

// MARK: - Preview
#Preview {
    HabitTrackingView()
}
