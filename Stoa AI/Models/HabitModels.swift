import Foundation
import FirebaseFirestore

// MARK: - Habit Models

/// Represents a habit goal created by the user or suggested by AI
struct Habit: Codable, Identifiable {
    var id: String
    let title: String
    let description: String
    let category: HabitCategory
    let frequency: HabitFrequency
    let duration: String? // Optional duration (e.g., "30 minutes", "1 hour")
    let createdAt: Date
    let createdBy: String // User ID
    let isActive: Bool
    let motivation: String? // Why the user wants to build this habit
    
    // AI-specific fields
    let isAISuggested: Bool // Whether this habit was suggested by AI
    let aiReasoning: String? // AI's reasoning for suggesting this habit
    let suggestedInMessageId: String? // ID of the chat message where this was suggested
    let program: HabitProgram? // AI-generated program structure
    let trackingMethod: String? // How to track this habit
    let motivationStrategy: String? // Strategy to stay motivated
    let reminders: [HabitReminder]? // Notification reminders
    
    var nextCheckIn: Date {
        switch frequency {
        case .daily:
            return Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        case .weekly:
            return Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.end ?? Date()
        case .custom(let days):
            return Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        }
    }
    
    init(id: String = UUID().uuidString, title: String, description: String, category: HabitCategory, frequency: HabitFrequency, duration: String? = nil, createdAt: Date = Date(), createdBy: String, isActive: Bool = true, motivation: String? = nil, isAISuggested: Bool = false, aiReasoning: String? = nil, suggestedInMessageId: String? = nil, program: HabitProgram? = nil, trackingMethod: String? = nil, motivationStrategy: String? = nil, reminders: [HabitReminder]? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.frequency = frequency
        self.duration = duration
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.isActive = isActive
        self.motivation = motivation
        self.isAISuggested = isAISuggested
        self.aiReasoning = aiReasoning
        self.suggestedInMessageId = suggestedInMessageId
        self.program = program
        self.trackingMethod = trackingMethod
        self.motivationStrategy = motivationStrategy
        self.reminders = reminders
    }
    
    // Convenience initializer for AI-suggested habits
    static func fromAISuggestion(title: String, description: String, category: HabitCategory, frequency: HabitFrequency, duration: String?, motivation: String?, aiReasoning: String?, messageId: String, createdBy: String, program: HabitProgram? = nil, trackingMethod: String? = nil, motivationStrategy: String? = nil, reminders: [HabitReminder]? = nil) -> Habit {
        return Habit(
            title: title,
            description: description,
            category: category,
            frequency: frequency,
            duration: duration,
            createdBy: createdBy,
            motivation: motivation,
            isAISuggested: true,
            aiReasoning: aiReasoning,
            suggestedInMessageId: messageId,
            program: program,
            trackingMethod: trackingMethod,
            motivationStrategy: motivationStrategy,
            reminders: reminders
        )
    }
    
    // Create Habit from backend dictionary (clean JSON from Cloud Function)
    static func fromBackendData(_ data: [String: Any]) throws -> Habit {
        // Convert dictionary to JSON data and use Codable
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // Backend sends ISO8601 strings
        return try decoder.decode(Habit.self, from: jsonData)
    }
}

/// Habit categories for organization
enum HabitCategory: String, CaseIterable, Codable {
    case physical = "Physical"
    case mental = "Mental"
    case spiritual = "Spiritual"
    case social = "Social"
    case productivity = "Productivity"
    case mindfulness = "Mindfulness"
    case learning = "Learning"
    case personalGrowth = "Personal Growth"
    
    // Custom decoder to handle legacy categories
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        // Handle legacy categories
        switch rawValue {
        case "Virtue Practice":
            self = .personalGrowth
        default:
            if let category = HabitCategory(rawValue: rawValue) {
                self = category
            } else {
                // Default fallback for unknown categories
                self = .personalGrowth
            }
        }
    }
    
    var icon: String {
        switch self {
        case .physical: return "figure.walk"
        case .mental: return "brain.head.profile"
        case .spiritual: return "leaf.fill"
        case .social: return "person.2.fill"
        case .productivity: return "checkmark.circle.fill"
        case .mindfulness: return "heart.fill"
        case .learning: return "book.fill"
        case .personalGrowth: return "star.fill"
        }
    }
    
    var color: String {
        switch self {
        case .physical: return "green"
        case .mental: return "blue"
        case .spiritual: return "purple"
        case .social: return "orange"
        case .productivity: return "red"
        case .mindfulness: return "pink"
        case .learning: return "indigo"
        case .personalGrowth: return "yellow"
        }
    }
}

/// Frequency options for habits
enum HabitFrequency: Codable, Equatable {
    case daily
    case weekly
    case custom(days: Int)
    
    var displayText: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .custom(let days): return "Every \(days) days"
        }
    }
}

/// Represents a habit check-in or completion record
struct HabitEntry: Codable, Identifiable {
    var id: String
    let habitId: String
    let completedAt: Date
    let notes: String?
    let rating: Int? // 1-5 scale for how well they did
    let reflection: String? // Brief reflection on the habit practice
    let mood: HabitMood?
    let createdBy: String // User ID
    
    init(id: String = UUID().uuidString, habitId: String, completedAt: Date = Date(), notes: String? = nil, rating: Int? = nil, reflection: String? = nil, mood: HabitMood? = nil, createdBy: String) {
        self.id = id
        self.habitId = habitId
        self.completedAt = completedAt
        self.notes = notes
        self.rating = rating
        self.reflection = reflection
        self.mood = mood
        self.createdBy = createdBy
    }
}

/// Mood tracking for habit entries
enum HabitMood: String, CaseIterable, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case neutral = "Neutral"
    case challenging = "Challenging"
    case difficult = "Difficult"
    
    var emoji: String {
        switch self {
        case .excellent: return "😊"
        case .good: return "🙂"
        case .neutral: return "😐"
        case .challenging: return "😕"
        case .difficult: return "😔"
        }
    }
}

/// Statistics for habit tracking
struct HabitStats: Codable {
    let habitId: String
    let totalCompletions: Int
    let currentStreak: Int
    let longestStreak: Int
    let completionRate: Double // Percentage
    let lastCompletedAt: Date?
    let averageRating: Double?
    
    var isOnTrack: Bool {
        completionRate >= 0.8 // 80% completion rate
    }
}

// MARK: - New AI Program Models

/// Represents a structured habit program with flexible duration
struct HabitProgram: Codable {
    let durationWeeks: Int
    let phases: [ProgramPhase]
    
    private enum CodingKeys: String, CodingKey {
        case durationWeeks = "duration_weeks"
        case phases
    }
}

/// Represents a phase within a habit program (can span multiple weeks)
struct ProgramPhase: Codable {
    let weekStart: Int
    let weekEnd: Int
    let goal: String
    let instructions: String
    
    private enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case goal
        case instructions
    }
}

/// Represents a weekly goal within a habit program (kept for backward compatibility)
struct WeeklyGoal: Codable {
    let goal: String
    let instructions: String
}

/// Represents a habit reminder notification
struct HabitReminder: Codable {
    let time: String // HH:MM format
    let message: String
    let frequency: String // "daily" or "weekly"
    let type: String? // "main", "preparation", "reflection"
}

// MARK: - New Comprehensive Habit Models

/// Represents a comprehensive habit with the new JSON structure
struct ComprehensiveHabit: Codable, Identifiable {
    let id: String
    let name: String
    let goal: String
    let startDate: String? // ISO 8601 timestamp
    let createdAt: String // ISO 8601 timestamp
    let category: String?
    let description: String
    let motivation: String
    let trackingMethod: String?
    
    let milestones: [HabitMilestone]
    let lowLevelSchedule: HabitSchedule?
    let highLevelSchedule: HabitHighLevelSchedule?
    let reminders: [HabitReminderNew]
    
    init(id: String = UUID().uuidString, name: String, goal: String, startDate: String? = nil, createdAt: String, category: String? = nil, description: String, motivation: String, trackingMethod: String? = nil, milestones: [HabitMilestone], lowLevelSchedule: HabitSchedule? = nil, highLevelSchedule: HabitHighLevelSchedule? = nil, reminders: [HabitReminderNew]) {
        self.id = id
        self.name = name
        self.goal = goal
        self.startDate = startDate
        self.createdAt = createdAt
        self.category = category
        self.description = description
        self.motivation = motivation
        self.trackingMethod = trackingMethod
        self.milestones = milestones
        self.lowLevelSchedule = lowLevelSchedule
        self.highLevelSchedule = highLevelSchedule
        self.reminders = reminders
    }
}

/// Represents a habit milestone
struct HabitMilestone: Codable, Identifiable {
    let id: String
    let description: String
    let completionCriteria: String
    let rewardMessage: String
    let targetDays: Int?
    
    private enum CodingKeys: String, CodingKey {
        case id, description
        case completionCriteria = "completion_criteria"
        case rewardMessage = "reward_message"
        case targetDays = "target_days"
    }
}

/// Represents a low-level habit schedule (repetitive)
struct HabitSchedule: Codable {
    let span: String // "daily", "weekly", "monthly", "yearly", "every-n-days", etc.
    let spanInterval: Int? // How many times to repeat (null = infinite)
    let program: [HabitProgramSchedule]
    
    private enum CodingKeys: String, CodingKey {
        case span
        case spanInterval = "span_interval"
        case program
    }
}

/// Represents a program within a schedule
struct HabitProgramSchedule: Codable {
    let steps: [HabitStep]
}

/// Represents a step in a habit schedule
struct HabitStep: Codable, Identifiable {
    let id: String
    let time: String? // HH:MM format for daily
    let day: String? // Day of week for weekly
    let dayOfMonth: Int? // Day of month for monthly
    let dayOfYear: String? // Day of year for yearly
    let intervalDays: Int? // For every-n-days
    let instructions: String
    let feedback: String
    let durationMinutes: Int?
    let difficulty: String? // "easy", "medium", "hard", "expert"
    
    private enum CodingKeys: String, CodingKey {
        case id, time, day, instructions, feedback, difficulty
        case dayOfMonth = "day_of_month"
        case dayOfYear = "day_of_year"
        case intervalDays = "interval_days"
        case durationMinutes = "duration_minutes"
    }
}

/// Represents a high-level habit schedule (progressive)
struct HabitHighLevelSchedule: Codable {
    let program: [HabitPhase]
}

/// Represents a phase in a high-level schedule
struct HabitPhase: Codable, Identifiable {
    let id: String
    let phase: String // "foundation", "building", "mastery"
    let durationWeeks: Int
    let goal: String
    let steps: [HabitPhaseStep]
    
    private enum CodingKeys: String, CodingKey {
        case id, phase, goal, steps
        case durationWeeks = "duration_weeks"
    }
}

/// Represents a step in a habit phase
struct HabitPhaseStep: Codable, Identifiable {
    let id: String
    let instructions: String
    let feedback: String
    let successCriteria: String
    let durationMinutes: Int?
    let difficulty: String? // "easy", "medium", "hard", "expert"
    
    private enum CodingKeys: String, CodingKey {
        case id, instructions, feedback, difficulty
        case successCriteria = "success_criteria"
        case durationMinutes = "duration_minutes"
    }
}

/// Represents a new habit reminder with additional fields
struct HabitReminderNew: Codable, Identifiable {
    let id: String
    let time: String // HH:MM format
    let message: String
    let frequency: String // "daily", "weekly", "monthly", "once"
    let type: String // "preparation", "execution", "reflection", "motivation"
    let daysBefore: Int? // Optional: how many days before to remind
    
    init(id: String = UUID().uuidString, time: String, message: String, frequency: String, type: String, daysBefore: Int? = nil) {
        self.id = id
        self.time = time
        self.message = message
        self.frequency = frequency
        self.type = type
        self.daysBefore = daysBefore
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, time, message, frequency, type
        case daysBefore = "days_before"
    }
}

extension Habit {
    // JSON format that AI should use in responses
    static func getAIJSONFormat() -> String {
        return """
        {
          "ai_habit_suggestion": {
            "title": "Morning Meditation",
            "description": "Start each day with 10 minutes of mindful meditation to cultivate inner peace and clarity",
            "category": "mindfulness",
            "frequency": "daily",
            "duration": "10 minutes",
            "program": {
              "duration_weeks": 8,
              "phases": [
                { "week_start": 1, "week_end": 2, "goal": "Establish routine", "instructions": "Focus on consistency, 5-10 minutes daily" },
                { "week_start": 3, "week_end": 4, "goal": "Deepen practice", "instructions": "Full 10 minutes, focus on breath awareness" },
                { "week_start": 5, "week_end": 6, "goal": "Build mindfulness", "instructions": "Add body scan and loving-kindness" },
                { "week_start": 7, "week_end": 8, "goal": "Integrate insights", "instructions": "Apply mindfulness throughout daily activities" }
              ]
            },
            "tracking_method": "Daily check-in with mood, focus level, and duration",
            "motivation_strategy": "Start small, build momentum, celebrate weekly progress",
            "reminders": [
              { "time": "07:00", "message": "Time for your morning meditation 🧘", "frequency": "daily", "type": "main" },
              { "time": "06:55", "message": "Prepare your meditation space", "frequency": "daily", "type": "preparation" },
              { "time": "21:00", "message": "Reflect on today's mindfulness practice", "frequency": "daily", "type": "reflection" }
            ],
            "motivation": "To develop mental clarity and emotional resilience through daily practice",
            "ai_reasoning": "Based on your request for stress management, daily meditation will help you build inner calm and focus"
          }
        }
        """
    }
}

/// Chat mode for habit-focused conversations
enum ChatMode: String, CaseIterable, Codable {
    case task = "task"
    case habit = "habit"
    
    var displayName: String {
        switch self {
        case .task: return "Task Management"
        case .habit: return "Habit Building"
        }
    }
    
    // Note: System prompts are now managed in the backend for consistency
    // This is kept for reference only - actual prompts are in backend/functions-v2/src/index.ts
    
    var icon: String {
        switch self {
        case .task: return "checklist"
        case .habit: return "target"
        }
    }
}

// MARK: - Task Models

/// Represents a task that can be one-time or multi-step
struct UserTask: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let createdAt: Date
    let completedAt: Date?
    let isCompleted: Bool
    let steps: [TaskStep]
    let createdBy: String // User ID
    let deadline: Date? // Optional task deadline
    let startDate: Date? // When task should start
    
    init(id: String = UUID().uuidString, name: String, description: String, createdAt: Date = Date(), completedAt: Date? = nil, isCompleted: Bool = false, steps: [TaskStep] = [], createdBy: String, deadline: Date? = nil, startDate: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.isCompleted = isCompleted
        self.steps = steps
        self.createdBy = createdBy
        self.deadline = deadline
        self.startDate = startDate
    }
}

/// Represents a step within a multi-step task
struct TaskStep: Codable, Identifiable {
    let id: String
    let description: String
    let isCompleted: Bool
    let scheduledDate: Date? // Auto-calculated date for step completion
    
    init(id: String = UUID().uuidString, description: String, isCompleted: Bool = false, scheduledDate: Date? = nil) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
        self.scheduledDate = scheduledDate
    }
}

/// Statistics for task completion
struct TaskStats: Codable {
    let taskId: String
    let totalSteps: Int
    let completedSteps: Int
    let completionRate: Double
    let isCompleted: Bool
    let completedAt: Date?
    
    var progressPercentage: Double {
        return completionRate * 100
    }
}


