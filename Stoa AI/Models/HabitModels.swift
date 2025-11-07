import Foundation
import SwiftUI
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
    
    var color: Color {
        switch self {
        case .physical: return Color.green
        case .mental: return Color.blue
        case .spiritual: return Color.purple
        case .social: return Color.orange
        case .productivity: return Color.red
        case .mindfulness: return Color.pink
        case .learning: return Color.indigo
        case .personalGrowth: return Color.yellow
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

/// Represents a comprehensive habit matching habit.json structure exactly
struct ComprehensiveHabit: Codable, Identifiable {
    let id: String // Generated for Swift Identifiable, not in JSON
    let name: String
    let goal: String
    let category: String
    let description: String
    let difficulty: String // "beginner" | "intermediate" | "advanced"
    
    let lowLevelSchedule: HabitSchedule
    let highLevelSchedule: HabitHighLevelSchedule
    
    // Date tracking fields
    let createdAt: String? // ISO 8601 string - when AI created/suggested the habit
    let startDate: String? // ISO 8601 string - when user pushed it to calendar
    
    // Active state
    let isActive: Bool // Whether the habit is currently active
    
    // Computed property to access milestones from highLevelSchedule
    var milestones: [HabitMilestone] {
        return highLevelSchedule.milestones
    }
    
    // Check if habit is completable (has a finite duration)
    var isCompletable: Bool {
        return lowLevelSchedule.habitSchedule != nil
    }
    
    // Check if habit is completed (has reached its end date)
    var isCompleted: Bool {
        guard isCompletable,
              let habitSchedule = lowLevelSchedule.habitSchedule,
              let startDateString = startDate else {
            return false // Infinite habits or habits without start date cannot be completed
        }
        
        // Parse start date
        let formatter = ISO8601DateFormatter()
        guard let startDate = formatter.date(from: startDateString) else {
            return false
        }
        
        // Calculate end date
        let calendar = Calendar.current
        guard let endDate = calendar.date(byAdding: .day, value: Int(habitSchedule), to: startDate) else {
            return false
        }
        
        // Check if current date is past the end date
        return Date() >= endDate
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, goal, category, description, difficulty
        case lowLevelSchedule = "low_level_schedule"
        case highLevelSchedule = "high_level_schedule"
        case createdAt = "created_at"
        case startDate = "start_date"
        case isActive
    }
    
    init(id: String = UUID().uuidString, name: String, goal: String, category: String, description: String, difficulty: String, lowLevelSchedule: HabitSchedule, highLevelSchedule: HabitHighLevelSchedule, createdAt: String? = nil, startDate: String? = nil, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.goal = goal
        self.category = category
        self.description = description
        self.difficulty = difficulty
        self.lowLevelSchedule = lowLevelSchedule
        self.highLevelSchedule = highLevelSchedule
        self.createdAt = createdAt
        self.startDate = startDate
        self.isActive = isActive
    }
    
    // Convenience initializer to parse from backend JSON
    static func fromBackendJSON(_ data: [String: Any]) throws -> ComprehensiveHabit {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // Handle ISO8601 date strings
        return try decoder.decode(ComprehensiveHabit.self, from: jsonData)
    }
}

/// Represents a habit milestone matching habit.json structure
struct HabitMilestone: Codable, Identifiable {
    let id: String // Generated for Swift Identifiable, not in JSON
    let index: Int // Index in the milestones array
    let description: String
    let completionCriteria: String // "streak_of_days" | "streak_of_weeks" | "streak_of_months" | "percentage"
    let completionCriteriaPoint: Double // Number value for the criteria (can be fractional)
    let rewardMessage: String
    
    private enum CodingKeys: String, CodingKey {
        case id, index, description
        case completionCriteria = "completion_criteria"
        case completionCriteriaPoint = "completion_criteria_point"
        case rewardMessage = "reward_message"
    }
    
    init(id: String = UUID().uuidString, index: Int = 0, description: String, completionCriteria: String, completionCriteriaPoint: Double, rewardMessage: String) {
        self.id = id
        self.index = index
        self.description = description
        self.completionCriteria = completionCriteria
        self.completionCriteriaPoint = completionCriteriaPoint
        self.rewardMessage = rewardMessage
    }
}

/// Represents a low-level habit schedule (repetitive) matching habit.json structure
struct HabitSchedule: Codable {
    let span: String // "day" | "week" | "month" | "year"
    let spanValue: Double // Multiplier for the span (e.g., 1 for daily, 2 for every 2 weeks) - number type
    let habitSchedule: Double? // Total duration in days (null = infinite) - number type
    let habitRepeatCount: Double? // How many times the cycle repeats (null = infinite) - number type
    let program: [HabitProgramSchedule]
    
    private enum CodingKeys: String, CodingKey {
        case span, program
        case spanValue = "span_value"
        case habitSchedule = "habit_schedule"
        case habitRepeatCount = "habit_repeat_count"
    }
}

/// Represents a program within a schedule (new structure with indexed arrays)
struct HabitProgramSchedule: Codable {
    let daysIndexed: [DaysIndexedItem]
    let weeksIndexed: [WeeksIndexedItem]
    let monthsIndexed: [MonthsIndexedItem]
    
    private enum CodingKeys: String, CodingKey {
        case daysIndexed = "days_indexed"
        case weeksIndexed = "weeks_indexed"
        case monthsIndexed = "months_indexed"
    }
}

/// Days indexed item
struct DaysIndexedItem: Codable {
    let index: Int
    let title: String
    let content: [DayStepContent]
    let reminders: [HabitReminderNew]
}

/// Weeks indexed item matching habit.json structure
struct WeeksIndexedItem: Codable {
    let index: Int
    let title: String
    let description: String
    let content: [WeekStepContent]
    let reminders: [HabitReminderNew]
}

/// Months indexed item matching habit.json structure
struct MonthsIndexedItem: Codable {
    let index: Int
    let title: String
    let description: String
    let content: [MonthStepContent]
    let reminders: [HabitReminderNew]
}

/// Step content for daily habits matching habit.json structure
struct DayStepContent: Codable {
    let step: String
    let clock: String? // "00:00" format or null (if null, means anytime in day it can be done)
}

/// Step content for weekly habits matching habit.json structure
struct WeekStepContent: Codable {
    let step: String
    let day: String // "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday" | "Sunday"
}

/// Step content for monthly habits matching habit.json structure
struct MonthStepContent: Codable {
    let step: String
    let day: String // "start_of_month" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "10" | "11" | "12" | "13" | "14" | "15" | "16" | "17" | "18" | "19" | "20" | "21" | "22" | "23" | "24" | "25" | "26" | "27" | "28" | "end_of_month"
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
    let milestones: [HabitMilestone]
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

/// Represents a habit reminder matching habit.json structure
struct HabitReminderNew: Codable, Identifiable {
    let id: String // Generated for Swift Identifiable, not in JSON
    let time: String? // "00:00" format or null
    let message: String? // String or null
    
    init(id: String = UUID().uuidString, time: String? = nil, message: String? = nil) {
        self.id = id
        self.time = time
        self.message = message
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, time, message
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
    let goal: String?
    let category: String?
    let description: String
    let createdAt: String? // ISO 8601 string - when AI created/suggested the task
    let completedAt: Date?
    let isCompleted: Bool
    let taskSchedule: TaskSchedule?
    let createdBy: String?
    let startDate: String? // ISO 8601 string - when user pushed it to calendar
    let isActive: Bool // Whether the task is currently active
    
    // Computed property for convenience - returns steps from taskSchedule
    var steps: [TaskStep] {
        return taskSchedule?.steps ?? []
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case goal
        case category
        case description
        case createdAt
        case completedAt
        case isCompleted
        case taskSchedule = "task_schedule"
        case createdBy
        case startDate
        case isActive
    }
}

/// Task schedule containing steps
struct TaskSchedule: Codable {
    let steps: [TaskStep]
    
    init(steps: [TaskStep] = []) {
        self.steps = steps
    }
}

/// Represents a step within a multi-step task
struct TaskStep: Codable, Identifiable {
    let id: String
    let index: Int?
    let title: String?
    let description: String?
    let date: String? // YYYY-MM-DD format or null
    let time: String? // HH:MM format or null
    let isCompleted: Bool
    let scheduledDate: Date? // Computed from date+time for calendar display
    let reminders: [TaskReminder]
    
    // Computed property to get Date from date string
    var dateValue: Date? {
        guard let dateString = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }
    
    // Computed property to get full Date+Time
    var scheduledDateTime: Date? {
        guard let dateValue = dateValue else { return nil }
        guard let timeString = time else { return dateValue }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        let dateTimeString = "\(date ?? "") \(timeString)"
        return formatter.date(from: dateTimeString) ?? dateValue
    }
    
    init(id: String = UUID().uuidString, index: Int? = nil, title: String? = nil, description: String? = nil, date: String? = nil, time: String? = nil, isCompleted: Bool = false, scheduledDate: Date? = nil, reminders: [TaskReminder] = []) {
        self.id = id
        self.index = index
        self.title = title
        self.description = description
        self.date = date
        self.time = time
        self.isCompleted = isCompleted
        self.reminders = reminders
        
        // Compute scheduledDate from date+time if not provided
        if let scheduledDate = scheduledDate {
        self.scheduledDate = scheduledDate
        } else if let dateString = date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            var computedDate = formatter.date(from: dateString)
            
            // Add time if available
            if let timeString = time, let baseDate = computedDate {
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                if let timeValue = timeFormatter.date(from: timeString) {
                    let calendar = Calendar.current
                    let timeComponents = calendar.dateComponents([.hour, .minute], from: timeValue)
                    computedDate = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: baseDate)
                }
            }
            self.scheduledDate = computedDate
        } else {
            self.scheduledDate = nil
        }
    }
    
    // Display title (uses title if available, otherwise description)
    var displayTitle: String {
        return title ?? description ?? "Step"
    }
    
    // Display description (uses description if available)
    var displayDescription: String {
        return description ?? title ?? ""
    }
}

/// Task reminder structure
struct TaskReminder: Codable, Identifiable {
    let id: String
    let offset: ReminderOffset
    let time: String? // HH:MM format or null
    let message: String? // Optional reminder message
    
    init(id: String = UUID().uuidString, offset: ReminderOffset, time: String? = nil, message: String? = nil) {
        self.id = id
        self.offset = offset
        self.time = time
        self.message = message
    }
}

/// Reminder offset (days, weeks, or months before step date)
struct ReminderOffset: Codable {
    let unit: ReminderUnit
    let value: Int // Positive number representing units before the step date
    
    init(unit: ReminderUnit, value: Int) {
        self.unit = unit
        self.value = value
    }
}

enum ReminderUnit: String, Codable {
    case days
    case weeks
    case months
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


