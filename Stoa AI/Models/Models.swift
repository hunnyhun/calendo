import Foundation
import SwiftUI

// MARK: - Models Module
public enum Models {
    // MARK: - App Features
    public enum Feature: Hashable {
        case chat
        case calendar
        case tasks
        case habits
    }
    
    // MARK: - Auth Status
    public enum AuthStatus: String {
        case unauthenticated
        case authenticated
        
        public var displayText: String { rawValue }
    }
    
    // MARK: - Subscription Tier
    public enum SubscriptionTier: String {
        case free
        case premium
        
        public var displayText: String { rawValue }
    }
    
    // MARK: - User Profile
    public struct UserProfile: Codable {
        public var name: String?
        public var age: Int?
        public var gender: Gender?
        public var goals: [Goal] = []
        public var intentions: [String]? // Free-form intentions/interests
        public var preferredTone: PreferredTone? // Tone/style preference for AI
        public var experienceLevel: ExperienceLevel? // User's experience level
        public var sufferingDuration: SufferingDuration?
        public var hasCompletedProfileSetup: Bool = false
        
        public init() {}
    }
    
    // MARK: - Gender
    public enum Gender: String, CaseIterable, Codable {
        case male = "male"
        case female = "female"
        case nonBinary = "non_binary"
        case preferNotToSay = "prefer_not_to_say"
        
        public var displayName: String {
            switch self {
            case .male: return "Male"
            case .female: return "Female"
            case .nonBinary: return "Non-binary"
            case .preferNotToSay: return "Prefer not to say"
            }
        }
    }
    
    // MARK: - Goal
    public enum Goal: String, CaseIterable, Codable {
        case personalGrowth = "personal_growth"
        case stressReduction = "stress_reduction"
        case emotionalResilience = "emotional_resilience"
        case mindfulness = "mindfulness"
        case betterRelationships = "better_relationships"
        
        public var displayName: String {
            switch self {
            case .personalGrowth: return "Personal Growth"
            case .stressReduction: return "Stress Reduction"
            case .emotionalResilience: return "Emotional Resilience"
            case .mindfulness: return "Mindfulness & Present Moment"
            case .betterRelationships: return "Better Relationships"
            }
        }
        
        public var description: String {
            switch self {
            case .personalGrowth: return "Develop wisdom, virtue, and character through personal growth principles"
            case .stressReduction: return "Learn to manage stress and find inner peace"
            case .emotionalResilience: return "Build strength to handle life's challenges"
            case .mindfulness: return "Practice presence and awareness in daily life"
            case .betterRelationships: return "Improve connections with others through wisdom"
            }
        }
    }


    // MARK: - Preferred Tone
    public enum PreferredTone: String, CaseIterable, Codable {
        case gentle
        case direct
        case motivational
        case neutral
        
        public var displayName: String { rawValue.capitalized }
    }

    // MARK: - Experience Level
    public enum ExperienceLevel: String, CaseIterable, Codable {
        case beginner
        case intermediate
        case advanced
        
        public var displayName: String { rawValue.capitalized }
    }
    
    // MARK: - Suffering Duration
    public enum SufferingDuration: String, CaseIterable, Codable {
        case recentlyStarted = "recently_started"
        case fewMonths = "few_months"
        case sixMonthsToYear = "six_months_to_year"
        case oneToThreeYears = "one_to_three_years"
        case severalYears = "several_years"
        case notApplicable = "not_applicable"
        
        public var displayName: String {
            switch self {
            case .recentlyStarted: return "Recently started"
            case .fewMonths: return "A few months"
            case .sixMonthsToYear: return "6 months to 1 year"
            case .oneToThreeYears: return "1-3 years"
            case .severalYears: return "Several years"
            case .notApplicable: return "Not applicable to me"
            }
        }
        
        public var description: String {
            switch self {
            case .recentlyStarted: return "I've just begun this journey"
            case .fewMonths: return "I've been working on this for a few months"
            case .sixMonthsToYear: return "I've been dealing with this for half a year to a year"
            case .oneToThreeYears: return "This has been an ongoing challenge for 1-3 years"
            case .severalYears: return "I've been facing this for many years"
            case .notApplicable: return "This question doesn't apply to my situation"
            }
        }
    }

    // MARK: - User State
    @Observable public final class UserState {
        public var authStatus: AuthStatus = .unauthenticated
        public var subscriptionTier: SubscriptionTier = .free
        public var userEmail: String?
        public var userId: String?
        public var lastUpdated: Date = Date()
        public var isAnonymous: Bool = true // Default to true
        public var profile: UserProfile = UserProfile()
        
        public var isAuthenticated: Bool {
            authStatus == .authenticated
        }
        
        public var isPremium: Bool {
            subscriptionTier == .premium
        }
        
        public init() {}
    }
    
    // MARK: - Calendar Data Models
    
    /// Calendar note for a specific date
    public struct CalendarNote: Codable, Identifiable {
        public let id: String
        public let date: Date
        public let note: String
        public let createdAt: Date
        public let updatedAt: Date
        
        public init(id: String = UUID().uuidString, date: Date, note: String) {
            self.id = id
            self.date = date
            self.note = note
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
    
    /// Aggregated data for a calendar day
    public struct CalendarDayData: Codable {
        public let date: Date
        public let habitsCompleted: Int
        public let totalHabits: Int
        public let hasQuote: Bool
        public let note: CalendarNote?
        public let habitSteps: [CalendarHabitStep]
        public let taskItems: [CalendarTaskItem]
        
        public init(date: Date, habitsCompleted: Int = 0, totalHabits: Int = 0, hasQuote: Bool = false, note: CalendarNote? = nil, habitSteps: [CalendarHabitStep] = [], taskItems: [CalendarTaskItem] = []) {
            self.date = date
            self.habitsCompleted = habitsCompleted
            self.totalHabits = totalHabits
            self.hasQuote = hasQuote
            self.note = note
            self.habitSteps = habitSteps
            self.taskItems = taskItems
        }
    }
    
    /// Calendar scale for different view modes
    public enum CalendarScale: String, CaseIterable {
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"
        case yearly = "yearly"
        
        public var displayName: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
    }
    
    // MARK: - Habit Access Control
    
    /// User status for habit access control
    public enum UserStatus {
        case anonymous
        case loggedIn(isPremium: Bool)
    }
    
    /// Result of habit access check
    public enum HabitAccessResult {
        case allowed
        case requiresLogin
        case requiresPremium(currentCount: Int)
    }
    
    /// Helper for checking habit access permissions
    public struct HabitAccessHelper {
        public static func canCreateHabit(userStatus: UserStatus, currentHabitCount: Int) -> HabitAccessResult {
            switch userStatus {
            case .anonymous:
                return .requiresLogin
            case .loggedIn(let isPremium):
                if isPremium {
                    return .allowed
                } else {
                    return currentHabitCount >= 1 ? .requiresPremium(currentCount: currentHabitCount) : .allowed
                }
            }
        }
        
        public static func canAccessHabitMode(userStatus: UserStatus) -> Bool {
            switch userStatus {
            case .anonymous:
                return false
            case .loggedIn:
                return true
            }
        }
    }
    
    // MARK: - Calendar Integration Models
    
    /// Represents a habit step scheduled for a specific calendar day
    public struct CalendarHabitStep: Codable, Identifiable {
        public let id: String
        public let habitId: String
        public let habitName: String
        public let stepDescription: String
        public let time: String? // e.g., "6 PM", "18:00"
        public let isCompleted: Bool
        
        public init(id: String = UUID().uuidString, habitId: String, habitName: String, stepDescription: String, time: String? = nil, isCompleted: Bool = false) {
            self.id = id
            self.habitId = habitId
            self.habitName = habitName
            self.stepDescription = stepDescription
            self.time = time
            self.isCompleted = isCompleted
        }
    }
    
    /// Represents a task item scheduled for a specific calendar day
    public struct CalendarTaskItem: Codable, Identifiable {
        public let id: String
        public let taskId: String
        public let taskName: String
        public let itemType: CalendarTaskItemType
        public let description: String
        public let daysRemaining: Int? // For deadlines
        public let scheduledDate: Date?
        public let isCompleted: Bool
        
        public init(id: String = UUID().uuidString, taskId: String, taskName: String, itemType: CalendarTaskItemType, description: String, daysRemaining: Int? = nil, scheduledDate: Date? = nil, isCompleted: Bool = false) {
            self.id = id
            self.taskId = taskId
            self.taskName = taskName
            self.itemType = itemType
            self.description = description
            self.daysRemaining = daysRemaining
            self.scheduledDate = scheduledDate
            self.isCompleted = isCompleted
        }
    }
    
    /// Type of task item for calendar display
    public enum CalendarTaskItemType: String, Codable {
        case currentStep = "current_step"
        case deadline = "deadline"
        case scheduledStep = "scheduled_step"
        
        public var displayName: String {
            switch self {
            case .currentStep: return "Current Step"
            case .deadline: return "Deadline"
            case .scheduledStep: return "Scheduled Step"
            }
        }
    }
} 
