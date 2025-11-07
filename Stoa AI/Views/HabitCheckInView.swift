import SwiftUI
import UserNotifications

// MARK: - Habit Check-In View
struct HabitCheckInView: View {
    let habit: ComprehensiveHabit
    @ObservedObject var habitManager: HabitManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var notes = ""
    @State private var rating: Int? = nil
    @State private var reflection = ""
    @State private var selectedMood: HabitMood? = nil
    @State private var isSubmitting = false
    
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
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Habit info header
                    VStack(spacing: 16) {
                        Image(systemName: displayCategory.icon)
                            .font(.system(size: 40))
                            .foregroundColor(displayCategory.color)
                            .frame(width: 80, height: 80)
                            .background(displayCategory.color.opacity(0.1))
                            .clipShape(Circle())
                        
                        VStack(spacing: 8) {
                            Text(habit.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            if let duration = displayDuration {
                                Label(duration, systemImage: "clock")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Show difficulty instead of trackingMethod
                            Text("📊 \(habit.difficulty.capitalized)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 20) {
                        // Mood selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How did it feel?")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                ForEach(HabitMood.allCases, id: \.self) { mood in
                                    MoodButton(
                                        mood: mood,
                                        isSelected: selectedMood == mood
                                    ) {
                                        selectedMood = mood
                                    }
                                }
                            }
                        }
                        
                        // Rating
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How well did you do? (Optional)")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 8) {
                                ForEach(1...5, id: \.self) { star in
                                    Button(action: {
                                        rating = star
                                    }) {
                                        Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                                            .font(.title3)
                                            .foregroundColor(star <= (rating ?? 0) ? .yellow : .gray)
                                    }
                                }
                                
                                Spacer()
                                
                                if let rating = rating {
                                    Text(ratingText(for: rating))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // Notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes (Optional)")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("How did it go? Any observations?", text: $notes, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(3...6)
                        }
                        
                        // Reflection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Personal Reflection (Optional)")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("What did you learn? How does this align with your values?", text: $reflection, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(3...6)
                            
                            Text("Reflect on how this practice contributes to your philosophical growth")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 20)
                    
                    // Submit button
                    Button(action: submitCheckIn) {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            }
                            
                            Text(isSubmitting ? "Recording..." : "Mark Complete")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSubmitting)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func ratingText(for rating: Int) -> String {
        switch rating {
        case 1: return "Struggled"
        case 2: return "Okay"
        case 3: return "Good"
        case 4: return "Great"
        case 5: return "Excellent"
        default: return ""
        }
    }
    
    private func submitCheckIn() {
        isSubmitting = true
        
        Task {
            await habitManager.recordHabitCompletion(
                habit,
                notes: notes.isEmpty ? nil : notes,
                rating: rating,
                reflection: reflection.isEmpty ? nil : reflection,
                mood: selectedMood
            )
            
            await MainActor.run {
                isSubmitting = false
                dismiss()
            }
        }
    }
}

// MARK: - Mood Button
struct MoodButton: View {
    let mood: HabitMood
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(mood.emoji)
                    .font(.title2)
                
                Text(mood.rawValue)
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Habit Detail View
struct HabitDetailView: View {
    let habit: ComprehensiveHabit
    @ObservedObject var habitManager: HabitManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingEdit = false
    @State private var showingDeleteAlert = false
    
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
    
    private var stats: HabitStats? {
        habitManager.getStats(for: habit)
    }
    
    private var recentEntries: [HabitEntry] {
        let habitId = habit.id
        
        return habitManager.entries
            .filter { $0.habitId == habitId }
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(10)
            .map { $0 }
    }
    
    // Collect all reminders from days_indexed, weeks_indexed, and months_indexed
    private func collectAllReminders() -> [HabitReminderNew] {
        var reminders: [HabitReminderNew] = []
        
        if let firstProgram = habit.lowLevelSchedule.program.first {
            // Collect from days_indexed
            for dayItem in firstProgram.daysIndexed {
                reminders.append(contentsOf: dayItem.reminders)
            }
            
            // Collect from weeks_indexed
            for weekItem in firstProgram.weeksIndexed {
                reminders.append(contentsOf: weekItem.reminders)
            }
            
            // Collect from months_indexed
            for monthItem in firstProgram.monthsIndexed {
                reminders.append(contentsOf: monthItem.reminders)
            }
        }
        
        // Remove duplicates
        var uniqueReminders: [HabitReminderNew] = []
        var seenReminders: Set<String> = []
        for reminder in reminders {
            let key = "\(reminder.time ?? "")|\(reminder.message ?? "")"
            if !seenReminders.contains(key) {
                seenReminders.insert(key)
                uniqueReminders.append(reminder)
            }
        }
        
        return uniqueReminders
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: displayCategory.icon)
                            .font(.system(size: 50))
                            .foregroundColor(displayCategory.color)
                            .frame(width: 100, height: 100)
                            .background(displayCategory.color.opacity(0.1))
                            .clipShape(Circle())
                        
                        VStack(spacing: 8) {
                            Text(habit.name)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text(displayCategory.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Capsule())
                            
                            if !habit.description.isEmpty {
                                Text(habit.description)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    // Stats
                    if let stats = stats {
                        HabitStatsView(stats: stats)
                    }
                    
                    // Habit details
                    VStack(spacing: 16) {
                        HabitDetailRow(
                            icon: "calendar",
                            title: "Frequency",
                            value: displayFrequency.displayText
                        )
                        
                        if let duration = displayDuration {
                            HabitDetailRow(
                                icon: "clock",
                                title: "Duration",
                                value: duration
                            )
                        }
                        
                        // Show goal instead of motivation
                        HabitDetailRow(
                            icon: "target",
                            title: "Goal",
                            value: habit.goal
                        )
                        
                        // Show difficulty instead of trackingMethod
                        HabitDetailRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Difficulty",
                            value: habit.difficulty.capitalized
                        )
                        
                    }
                    .padding(.horizontal, 20)
                    
                    // Reminders section - collect from indexed items
                    let allReminders = collectAllReminders()
                    if !allReminders.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "bell")
                                    .foregroundColor(.blue)
                                Text("Reminders")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            VStack(spacing: 12) {
                                ForEach(Array(allReminders.enumerated()), id: \.offset) { index, reminder in
                                    HabitReminderRow(reminder: reminder)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Recent entries
                    if !recentEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Recent Check-ins")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                            
                            LazyVStack(spacing: 8) {
                                ForEach(recentEntries) { entry in
                                    HabitEntryRow(entry: entry)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .navigationTitle("Habit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Edit Habit") {
                            showingEdit = true
                        }
                        
                        Button("Delete Habit", role: .destructive) {
                            showingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete Habit", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await habitManager.deleteHabit(habit)
                        await MainActor.run {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this habit? This action cannot be undone.")
            }
        }
    }
}

// MARK: - Habit Stats View
struct HabitStatsView: View {
    let stats: HabitStats
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                StatCard(
                    title: "Completion Rate",
                    value: "\(Int(stats.completionRate * 100))%",
                    icon: "chart.line.uptrend.xyaxis",
                    color: stats.isOnTrack ? .green : .orange
                )
                
                StatCard(
                    title: "Current Streak",
                    value: "\(stats.currentStreak)",
                    icon: "flame.fill",
                    color: .red
                )
            }
            
            HStack(spacing: 20) {
                StatCard(
                    title: "Total Completions",
                    value: "\(stats.totalCompletions)",
                    icon: "checkmark.circle.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Best Streak",
                    value: "\(stats.longestStreak)",
                    icon: "trophy.fill",
                    color: .yellow
                )
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Habit Detail Row
struct HabitDetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Habit Entry Row
struct HabitEntryRow: View {
    let entry: HabitEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.completedAt, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(entry.completedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Mood
            if let mood = entry.mood {
                Text(mood.emoji)
                    .font(.title3)
            }
            
            // Rating
            if let rating = entry.rating {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(star <= rating ? .yellow : .gray)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Preview
#Preview {
    HabitCheckInView(
        habit: ComprehensiveHabit(
            name: "Morning Meditation",
            goal: "Cultivate inner peace and clarity",
            category: "mindfulness",
            description: "10 minutes of mindful breathing",
            difficulty: "beginner",
            lowLevelSchedule: HabitSchedule(
                span: "day",
                spanValue: 1.0,
                habitSchedule: nil,
                habitRepeatCount: nil,
                program: [
                    HabitProgramSchedule(
                        daysIndexed: [
                            DaysIndexedItem(
                                index: 1,
                                title: "Daily Meditation",
                                content: [
                                    DayStepContent(step: "Sit comfortably for 10 minutes", clock: "07:00")
                                ],
                                reminders: [
                                    HabitReminderNew(time: "07:00", message: "Time for meditation")
                                ]
                            )
                        ],
                        weeksIndexed: [],
                        monthsIndexed: []
                    )
                ]
            ),
            highLevelSchedule: HabitHighLevelSchedule(
                milestones: [
                    HabitMilestone(
                        index: 0,
                        description: "Foundation - Get started",
                        completionCriteria: "streak_of_days",
                        completionCriteriaPoint: 7,
                        rewardMessage: "Great start!"
                    )
                ]
            )
        ),
        habitManager: HabitManager()
    )
}

// MARK: - Habit Reminder Row
struct HabitReminderRow: View {
    let reminder: HabitReminderNew
    @State private var notificationsEnabled = true
    
    var body: some View {
        HStack(spacing: 12) {
            // Reminder icon
            Image(systemName: "bell")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let time = reminder.time {
                        Text(time)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Notification status indicator
                    if notificationsEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "bell.slash")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                if let message = reminder.message {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            checkNotificationStatus()
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
}
