import SwiftUI

/// Card component that displays an AI-suggested habit with a "Push to Schedule" button
struct HabitSuggestionCard: View {
    let habit: ComprehensiveHabit
    let onPushToSchedule: () -> Void
    @State private var isExpanded = false
    @State private var isProcessing = false
    @Environment(\.colorScheme) private var colorScheme
    
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
    
    // Derive duration from schedule (check first step in days_indexed)
    // Note: The new structure doesn't have duration_minutes, so we return nil
    // This could be extracted from step descriptions if needed in the future
    private var displayDuration: String? {
        // Duration information is not available in the new habit.json structure
        // Return nil to hide the duration label
        return nil
    }
    
    // Break down complex expressions into computed properties
    private var headerSection: some View {
        HStack {
            habitTitleInfo
            Spacer()
            expandButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var habitTitleInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: displayCategory.icon)
                    .foregroundColor(displayCategory.color)
                    .font(.title3)
                
                Text(habit.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            frequencyLabels
        }
    }
    
    private var frequencyLabels: some View {
        HStack(spacing: 12) {
            Label(displayFrequency.displayText, systemImage: "calendar")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let duration = displayDuration {
                Label(duration, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var expandButton: some View {
        Button(action: { 
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var expandableContent: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .padding(.horizontal, 16)
                
                detailsSection
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            descriptionSection
            trackingMethodSection
            remindersSection
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(habit.description)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    // Tracking method is no longer in the new structure
    // This section can be removed or show goal instead
    @ViewBuilder
    private var trackingMethodSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Goal")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(habit.goal)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    
    // Motivation is no longer in the new structure
    // Use description or goal instead
    @ViewBuilder
    private var motivationSection: some View {
        // Section removed as motivation field doesn't exist in new structure
        EmptyView()
    }
    
    // Reminders are now inside indexed items, collect them from all sources
    @ViewBuilder
    private var remindersSection: some View {
        let allReminders = collectAllReminders()
        if !allReminders.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                    Text("Reminders (\(allReminders.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                remindersList(allReminders)
            }
        }
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
    
    private func remindersList(_ reminders: [HabitReminderNew]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(reminders.prefix(3).enumerated()), id: \.offset) { _, reminder in
                HStack(spacing: 8) {
                    if let time = reminder.time {
                        Text(time)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    if let message = reminder.message {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            if reminders.count > 3 {
                Text("+ \(reminders.count - 3) more reminders")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    
    private var pushButton: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)
            
            Button(action: {
                guard !isProcessing else { return }
                isProcessing = true
                onPushToSchedule()
                
                // Reset after a delay to prevent rapid tapping
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isProcessing = false
                }
            }) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                    
                    Text(isProcessing ? "Creating..." : "Activate")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isProcessing ? AnyView(Color.gray) : AnyView(buttonGradient))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(categoryColor.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: categoryColor.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private var buttonGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                categoryColor,
                categoryColor.opacity(0.8)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // Enhanced category colors with better contrast
    private var categoryColor: Color {
        switch displayCategory {
        case .physical:
            return Color.green
        case .mental:
            return Color.blue
        case .spiritual:
            return Color.purple
        case .social:
            return Color.orange
        case .productivity:
            return Color.red
        case .mindfulness:
            return Color.pink
        case .learning:
            return Color.indigo
        case .personalGrowth:
            return Color.yellow
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 8,
                x: 0,
                y: 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        displayCategory.color.opacity(0.3),
                        lineWidth: 1
                    )
            )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            expandableContent
            pushButton
        }
        .background(cardBackground)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        HabitSuggestionCard(
            habit: ComprehensiveHabit(
                name: "Morning Meditation",
                goal: "Cultivate inner peace and clarity",
                category: "mindfulness",
                description: "Start each day with 10 minutes of mindful meditation to cultivate inner peace and clarity",
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
                                        HabitReminderNew(time: "07:00", message: "Time for your morning meditation 🧘"),
                                        HabitReminderNew(time: "06:55", message: "Prepare your meditation space")
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
                            rewardMessage: "Great start! You're building consistency."
                        )
                    ]
                )
            ),
            onPushToSchedule: {
                print("Push to schedule tapped")
            }
        )
        .padding()
        
        Spacer()
    }
    .background(Color(.systemBackground))
}
