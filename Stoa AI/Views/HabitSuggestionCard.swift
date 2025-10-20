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
                    .foregroundColor(Color(displayCategory.color))
                    .font(.title3)
                
                Text(habit.name)
                    .font(.headline)
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
            motivationSection
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
    
    @ViewBuilder
    private var trackingMethodSection: some View {
        if let trackingMethod = habit.trackingMethod {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tracking Method")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(trackingMethod)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    
    @ViewBuilder
    private var motivationSection: some View {
        if !habit.motivation.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Why This Matters")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(habit.motivation)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var remindersSection: some View {
        if !habit.reminders.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                    Text("Reminders (\(habit.reminders.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                remindersList(habit.reminders)
            }
        }
    }
    
    private func remindersList(_ reminders: [HabitReminderNew]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(reminders.prefix(3).enumerated()), id: \.offset) { _, reminder in
                HStack(spacing: 8) {
                    Text(reminder.time)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(reminder.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
                    
                    Text(isProcessing ? "Creating..." : "Push it")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isProcessing ? AnyView(Color.gray) : AnyView(buttonGradient))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
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
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 8,
                x: 0,
                y: 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color(displayCategory.color).opacity(0.3),
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
                createdAt: ISO8601DateFormatter().string(from: Date()),
                category: "mindfulness",
                description: "Start each day with 10 minutes of mindful meditation to cultivate inner peace and clarity",
                motivation: "To develop mental clarity and emotional resilience through daily practice",
                trackingMethod: "Daily check-in with mood and focus level",
                milestones: [],
                reminders: [
                    HabitReminderNew(time: "07:00", message: "Time for your morning meditation 🧘", frequency: "daily", type: "execution"),
                    HabitReminderNew(time: "06:55", message: "Prepare your meditation space", frequency: "daily", type: "preparation"),
                    HabitReminderNew(time: "21:00", message: "Reflect on today's mindfulness practice", frequency: "daily", type: "reflection")
                ]
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
