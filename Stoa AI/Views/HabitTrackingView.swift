import SwiftUI
import FirebaseAuth

// MARK: - Main Habit Tracking View
struct HabitTrackingView: View {
    @ObservedObject private var habitManager = HabitManager.shared
    @StateObject private var importService = ImportService.shared
    var onNavigateToHabitChat: (() -> Void)? = nil
    var onNavigateBack: (() -> Void)? = nil
    
    @State private var showingHabitCreation = false
    @State private var showingHabitDetail: ComprehensiveHabit?
    @State private var selectedTab = 0
    @State private var showingImportAlert = false
    @State private var showingImportSheet = false
    @State private var shareLink: URL?
    
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
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Import button
                    Button(action: {
                        checkClipboardForImport()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                            .foregroundColor(.brandPrimary)
                    }
                    
                    // Add button
                Button(action: {
                    handleHabitCreation()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.brandPrimary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
                
                // Custom tab toggle
                ViewTypeToggle(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    // Active habits
                    ActiveHabitsView(
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
                    
                    // Completed habits
                    CompletedHabitsView(
                        habitManager: habitManager,
                        showingHabitDetail: $showingHabitDetail
                    )
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .onAppear {
                Task {
                    await habitManager.loadHabits()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ImportFromDeepLink"))) { notification in
                if let userInfo = notification.userInfo,
                   let url = userInfo["url"] as? URL {
                    Task {
                        if await importService.parseFromURL(url) {
                            if importService.importableHabit != nil {
                                showingImportSheet = true
                            } else {
                                showingImportAlert = true
                            }
                        } else {
                            showingImportAlert = true
                        }
                    }
                }
            }
            .sheet(item: $showingHabitDetail) { habit in
                HabitDetailView(habit: habit, habitManager: habitManager)
            }
            .sheet(isPresented: $showingImportSheet) {
                if let habit = importService.importableHabit {
                    ImportHabitView(habit: habit, habitManager: habitManager) {
                        importService.clearImport()
                        showingImportSheet = false
                    }
                }
            }
            .alert("Import Error", isPresented: $showingImportAlert) {
                Button("OK", role: .cancel) {
                    importService.clearImport()
                }
            } message: {
                Text(importService.importError ?? "Could not import habit.")
            }
        }
        
        // MARK: - Helper Functions
        
        func checkClipboardForImport() {
            let pasteboard = UIPasteboard.general
            if let clipboardText = pasteboard.string, !clipboardText.isEmpty {
                Task {
                    if await importService.parseFromText(clipboardText) {
                        if importService.importableHabit != nil {
                            showingImportSheet = true
                        } else {
                            showingImportAlert = true
                        }
                    } else {
                        showingImportAlert = true
                    }
                }
            } else {
                importService.importError = "Clipboard is empty. Please copy a shared habit first."
                showingImportAlert = true
            }
        }
        
        private func handleHabitCreation() {
            // All users can create habits now
            // Call the navigation callback if provided, otherwise post notification
            if let onNavigateToHabitChat = onNavigateToHabitChat {
                onNavigateToHabitChat()
            } else {
                // Fallback: Post notification to switch ChatView to habit mode
                NotificationCenter.default.post(name: Notification.Name("SwitchToHabitMode"), object: nil)
            }
        }
    }

// MARK: - Active Habits View
struct ActiveHabitsView: View {
    @ObservedObject var habitManager: HabitManager
    let onCreateHabit: () -> Void
    @State private var showingCheckIn: ComprehensiveHabit?
    @State private var showingDeleteAlert: ComprehensiveHabit?
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @State private var shareLink: URL?
    
    // Show only active habits
    private var activeHabits: [ComprehensiveHabit] {
        let filtered = habitManager.habits.filter { $0.isActive }
        print("🔍 [ActiveHabitsView] activeHabits computed - Total habits: \(habitManager.habits.count), Active: \(filtered.count)")
        print("🔍 [ActiveHabitsView] Habit states: \(habitManager.habits.map { "\($0.name): \($0.isActive ? "ACTIVE" : "INACTIVE")" })")
        return filtered
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if activeHabits.isEmpty {
                    EmptyHabitsView(onCreateHabit: onCreateHabit)
                } else {
                    ForEach(activeHabits) { habit in
                        TodayHabitCard(
                            habit: habit,
                            isCompleted: habitManager.isHabitCompletedToday(habit),
                            onCheckIn: {
                                showingCheckIn = habit
                            },
                            onToggleActive: {
                                Task {
                                    await habitManager.toggleHabitActive(habit)
                                }
                            },
                            onDelete: {
                                showingDeleteAlert = habit
                            },
                            onShare: {
                                Task {
                                    let shareResult = await habitManager.shareHabit(habit)
                                    shareText = shareResult.text
                                    shareLink = shareResult.link
                                    showingShareSheet = true
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                showingDeleteAlert = habit
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                Task {
                                    await habitManager.toggleHabitActive(habit)
                                }
                            } label: {
                                Label(habit.isActive ? "Deactivate" : "Activate", systemImage: habit.isActive ? "pause.circle" : "play.circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sheet(item: $showingCheckIn) { habit in
            HabitCheckInView(habit: habit, habitManager: habitManager)
        }
        .alert(item: $showingDeleteAlert) { habit in
            Alert(
                title: Text("Delete Habit"),
                message: Text("Are you sure you want to delete \"\(habit.name)\"? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await habitManager.deleteHabit(habit)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = shareLink {
                ShareSheet(activityItems: [shareText, link])
            } else {
                ShareSheet(activityItems: [shareText])
            }
        }
    }
}

// MARK: - Completed Habits View
struct CompletedHabitsView: View {
    @ObservedObject var habitManager: HabitManager
    @Binding var showingHabitDetail: ComprehensiveHabit?
    @State private var showingDeleteAlert: ComprehensiveHabit?
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @State private var shareLink: URL?
    
    // Filter completed habits (only habits with habit_schedule number that have reached their end date)
    private var completedHabits: [ComprehensiveHabit] {
        habitManager.habits.filter { habit in
            habit.isCompleted // Only habits with habit_schedule (not null) that have reached their end date
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if completedHabits.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        VStack(spacing: 8) {
                            Text("No Completed Habits")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Completed habits will appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(40)
                } else {
                    ForEach(completedHabits) { habit in
                        HabitSummaryCard(
                            habit: habit,
                            stats: habitManager.getStats(for: habit),
                            onTap: {
                                showingHabitDetail = habit
                            },
                            onToggleActive: {
                                Task {
                                    await habitManager.toggleHabitActive(habit)
                                }
                            },
                            onDelete: {
                                showingDeleteAlert = habit
                            },
                            onShare: {
                                Task {
                                    let shareResult = await habitManager.shareHabit(habit)
                                    shareText = shareResult.text
                                    shareLink = shareResult.link
                                    showingShareSheet = true
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                showingDeleteAlert = habit
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                Task {
                                    await habitManager.toggleHabitActive(habit)
                                }
                            } label: {
                                Label(habit.isActive ? "Deactivate" : "Activate", systemImage: habit.isActive ? "pause.circle" : "play.circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .alert(item: $showingDeleteAlert) { habit in
            Alert(
                title: Text("Delete Habit"),
                message: Text("Are you sure you want to delete \"\(habit.name)\"? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await habitManager.deleteHabit(habit)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = shareLink {
                ShareSheet(activityItems: [shareText, link])
            } else {
                ShareSheet(activityItems: [shareText])
            }
        }
    }
}

// MARK: - Today Habit Card
struct TodayHabitCard: View {
    let habit: ComprehensiveHabit
    let isCompleted: Bool
    let onCheckIn: () -> Void
    let onToggleActive: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    @State private var showingMenu = false
    
    // Break down complex expressions into computed properties
    private var categoryIcon: some View {
        Image(systemName: displayCategory.icon)
            .font(.title2)
            .foregroundColor(displayCategory.color)
            .frame(width: 40, height: 40)
            .background(displayCategory.color.opacity(0.1))
            .clipShape(Circle())
    }
    
    // Convert string category to HabitCategory for display
    private var displayCategory: HabitCategory {
        let categoryString = habit.category.lowercased()
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
        switch habit.lowLevelSchedule.span {
        case "day":
            if habit.lowLevelSchedule.spanValue == 1.0 {
                return .daily
            } else {
                return .custom(days: Int(habit.lowLevelSchedule.spanValue))
            }
        case "week":
            return .weekly
        default:
            return .daily
        }
    }
    
    // Derive duration from schedule
    // Note: duration_minutes doesn't exist in new structure, return nil
    private var displayDuration: String? {
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
    
    // Tracking method no longer exists in new structure
    // Show goal or difficulty instead
    @ViewBuilder
    private var trackingInfo: some View {
        Text("📊 \(habit.difficulty.capitalized)")
            .font(.caption2)
            .foregroundColor(.blue)
            .padding(.top, 2)
            .lineLimit(1)
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
            HStack(spacing: 12) {
            checkInButton
                
                Menu {
                    Button(action: onToggleActive) {
                        Label(habit.isActive ? "Deactivate" : "Activate", systemImage: habit.isActive ? "pause.circle" : "play.circle")
                    }
                    
                    Button(action: onShare) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .opacity(habit.isActive ? 1.0 : 0.6)
    }
}

// MARK: - All Habits View
struct AllHabitsView: View {
    @ObservedObject var habitManager: HabitManager
    @Binding var showingHabitDetail: ComprehensiveHabit?
    @State private var showingDeleteAlert: ComprehensiveHabit?
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @State private var shareLink: URL?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(habitManager.habits) { habit in
                    HabitSummaryCard(
                        habit: habit,
                        stats: habitManager.getStats(for: habit),
                        onTap: {
                            showingHabitDetail = habit
                        },
                        onToggleActive: {
                            Task {
                                await habitManager.toggleHabitActive(habit)
                            }
                        },
                        onDelete: {
                            showingDeleteAlert = habit
                        },
                        onShare: {
                            Task { @MainActor in
                                let shareResult = await habitManager.shareHabit(habit)
                                shareText = shareResult.text
                                shareLink = shareResult.link
                                showingShareSheet = true
                            }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            showingDeleteAlert = habit
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            Task {
                                await habitManager.toggleHabitActive(habit)
                            }
                        } label: {
                            Label(habit.isActive ? "Deactivate" : "Activate", systemImage: habit.isActive ? "pause.circle" : "play.circle")
                        }
                        .tint(.orange)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .alert(item: $showingDeleteAlert) { habit in
            Alert(
                title: Text("Delete Habit"),
                message: Text("Are you sure you want to delete \"\(habit.name)\"? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await habitManager.deleteHabit(habit)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = shareLink {
                ShareSheet(activityItems: [shareText, link])
            } else {
                ShareSheet(activityItems: [shareText])
            }
        }
    }
}

// MARK: - Habit Summary Card
struct HabitSummaryCard: View {
    let habit: ComprehensiveHabit
    let stats: HabitStats?
    let onTap: () -> Void
    let onToggleActive: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    
    // Convert string category to HabitCategory for display
    private var displayCategory: HabitCategory {
        let categoryString = habit.category.lowercased()
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
        switch habit.lowLevelSchedule.span {
        case "day":
            if habit.lowLevelSchedule.spanValue == 1.0 {
                return .daily
            } else {
                return .custom(days: Int(habit.lowLevelSchedule.spanValue))
            }
        case "week":
            return .weekly
        default:
            return .daily
        }
    }
    
    // Derive duration from schedule
    // Note: duration_minutes doesn't exist in new structure, return nil
    private var displayDuration: String? {
        return nil
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: displayCategory.icon)
                        .font(.title3)
                        .foregroundColor(displayCategory.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(displayCategory.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
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
                        
                        Menu {
                            Button(action: onToggleActive) {
                                Label(habit.isActive ? "Deactivate" : "Activate", systemImage: habit.isActive ? "pause.circle" : "play.circle")
                            }
                            
                            Button(action: onShare) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
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

