import Foundation

/// Service for detecting AI-generated habit suggestions in chat responses
class HabitDetectionService {
    static let shared = HabitDetectionService()
    
    private init() {}
    
    /// Detects if a chat message contains an AI habit suggestion
    /// Returns the new ComprehensiveHabit model directly
    func detectHabitSuggestion(in text: String, messageId: String, userId: String?) -> ComprehensiveHabit? {
        print("🔍 [HabitDetection] Looking for habit in text...")
        
        // First try to detect new comprehensive habit format
        if let comprehensiveHabit = detectComprehensiveHabit(in: text, messageId: messageId, userId: userId) {
            return comprehensiveHabit
        }
        
        // Fallback to old format for backward compatibility
        return detectLegacyHabit(in: text, messageId: messageId, userId: userId)
    }
    
    /// Detects new comprehensive habit format
    private func detectComprehensiveHabit(in text: String, messageId: String, userId: String?) -> ComprehensiveHabit? {
        print("🔍 [HabitDetection] Looking for comprehensive habit format...")
        
        // Extract JSON string
        guard let jsonString = extractJSONString(from: text) else {
            print("❌ [HabitDetection] No JSON found")
            return nil
        }
        
        print("🔍 [HabitDetection] Extracted JSON string length: \(jsonString.count)")
        print("🔍 [HabitDetection] JSON preview: \(String(jsonString.prefix(200)))")
        
        // Try to parse as comprehensive habit
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ [HabitDetection] Could not convert JSON string to data")
            return nil
        }
        
        do {
            // Parse the comprehensive habit structure
            let comprehensiveHabit = try JSONDecoder().decode(ComprehensiveHabit.self, from: jsonData)
            
            print("✅ [HabitDetection] Successfully detected comprehensive habit: \(comprehensiveHabit.name)")
            return comprehensiveHabit
            
        } catch {
            print("❌ [HabitDetection] Failed to parse comprehensive habit: \(error.localizedDescription)")
            print("🔍 [HabitDetection] JSON that failed to parse: \(jsonString)")
            return nil
        }
    }
    
    /// Detects legacy habit format for backward compatibility
    private func detectLegacyHabit(in text: String, messageId: String, userId: String?) -> ComprehensiveHabit? {
        print("🔍 [HabitDetection] Looking for legacy habit format...")
        
        // Extract JSON string using simple method
        guard let jsonString = extractJSONString(from: text) else {
            print("❌ [HabitDetection] No JSON found")
            return nil
        }
        
        print("✅ [HabitDetection] Found JSON, parsing...")
        
        // Try to parse the JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ [HabitDetection] Could not convert JSON string to data")
            return nil
        }
        
        do {
            // Parse the JSON structure
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            
            // Check if it's the new format (direct habit JSON) or legacy format (with ai_habit_suggestion wrapper)
            let habitData: [String: Any]
            if let directHabit = json, directHabit["name"] != nil {
                // New format - direct habit JSON
                habitData = directHabit
                print("✅ [HabitDetection] Detected new format (direct habit JSON)")
            } else if let wrappedHabit = json?["ai_habit_suggestion"] as? [String: Any] {
                // Legacy format - with ai_habit_suggestion wrapper
                habitData = wrappedHabit
                print("✅ [HabitDetection] Detected legacy format (ai_habit_suggestion wrapper)")
            } else {
                print("❌ [HabitDetection] No valid habit format found in JSON")
                return nil
            }
            
            // Extract required fields (handle both new and legacy formats)
            let title = habitData["name"] as? String ?? habitData["title"] as? String ?? "New Habit"
            guard let description = habitData["description"] as? String,
                  let categoryString = habitData["category"] as? String else {
                print("❌ [HabitDetection] Missing required fields in habit suggestion")
                return nil
            }
            
            // Extract optional fields
            let motivation = habitData["motivation"] as? String
            let trackingMethod = habitData["tracking_method"] as? String
            
            // Parse reminders
            var reminders: [HabitReminder]? = nil
            if let remindersArray = habitData["reminders"] as? [[String: Any]] {
                reminders = parseReminders(from: remindersArray)
            }
            
            // Create comprehensive habit from legacy data
            let goal = habitData["goal"] as? String ?? description
            let comprehensiveMotivation = motivation ?? "Build this habit for personal growth"
            let comprehensiveTrackingMethod = trackingMethod
            
            // Create basic milestones for legacy format
            let milestones = [
                HabitMilestone(
                    id: "legacy-milestone-1",
                    description: "Establish the habit",
                    completionCriteria: "Complete the habit for 7 consecutive days",
                    rewardMessage: "Great start! You're building consistency.",
                    targetDays: 7
                )
            ]
            
            // Convert legacy reminders to new format
            let newReminders = (reminders ?? []).map { reminder in
                HabitReminderNew(
                    time: reminder.time,
                    message: reminder.message,
                    frequency: reminder.frequency,
                    type: reminder.type ?? "execution"
                )
            }
            
            let comprehensiveHabit = ComprehensiveHabit(
                id: UUID().uuidString,
                name: title,
                goal: goal,
                startDate: nil,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                category: categoryString,
                description: description,
                motivation: comprehensiveMotivation,
                trackingMethod: comprehensiveTrackingMethod,
                milestones: milestones,
                lowLevelSchedule: nil,
                highLevelSchedule: nil,
                reminders: newReminders
            )
            
            print("✅ [HabitDetection] Successfully converted legacy habit to comprehensive format: \(title)")
            return comprehensiveHabit
            
        } catch {
            print("❌ [HabitDetection] JSON parsing error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Simple JSON extraction - much more reliable
    private func extractJSONString(from text: String) -> String? {
        print("🔍 [HabitDetection] Extracting JSON from text of length: \(text.count)")
        
        // Method 1: Look for code fenced JSON
        if let jsonInFence = extractFromCodeFence(text) {
            print("✅ [HabitDetection] Found JSON in code fence")
            return jsonInFence
        }
        
        // Method 2: Look for raw JSON
        if let jsonRaw = extractRawJSON(text) {
            print("✅ [HabitDetection] Found raw JSON")
            return jsonRaw
        }
        
        print("❌ [HabitDetection] No JSON found in text")
        return nil
    }
    
    private func extractFromCodeFence(_ text: String) -> String? {
        print("🔍 [HabitDetection] Looking for code fenced JSON...")
        
        // Find ```json or ``` followed by JSON
        let patterns = ["```json", "```"]
        
        for pattern in patterns {
            if let startRange = text.range(of: pattern) {
                print("🔍 [HabitDetection] Found opening fence: \(pattern)")
                let afterStart = text.index(startRange.upperBound, offsetBy: 0)
                let remainingText = String(text[afterStart...])
                
                // Find closing ```
                if let endRange = remainingText.range(of: "```") {
                    let jsonContent = String(remainingText[..<endRange.lowerBound])
                    print("🔍 [HabitDetection] Extracted content length: \(jsonContent.count)")
                    
                    // Check if it contains our habit suggestion (new format) or legacy format
                    if jsonContent.contains("ai_habit_suggestion") || jsonContent.contains("\"name\":") {
                        print("✅ [HabitDetection] Found valid habit JSON in code fence")
                        return jsonContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        print("❌ [HabitDetection] Code fence content doesn't contain habit markers")
                        print("🔍 [HabitDetection] Content preview: \(String(jsonContent.prefix(100)))")
                    }
                } else {
                    print("❌ [HabitDetection] No closing fence found")
                }
            }
        }
        
        return nil
    }
    
    private func extractRawJSON(_ text: String) -> String? {
        print("🔍 [HabitDetection] Looking for raw JSON...")
        
        // Look for { followed by ai_habit_suggestion (legacy) or "name": (new format)
        guard text.contains("ai_habit_suggestion") || text.contains("\"name\":") else { 
            print("❌ [HabitDetection] No habit markers found in text")
            return nil 
        }
        
        // Find the first { before the habit key
        let habitKey = text.contains("ai_habit_suggestion") ? "ai_habit_suggestion" : "\"name\":"
        guard let habitRange = text.range(of: habitKey) else { 
            print("❌ [HabitDetection] Habit key not found: \(habitKey)")
            return nil 
        }
        let beforeHabit = String(text[..<habitRange.lowerBound])
        
        // Find the last { in the text before the habit key
        guard let openBrace = beforeHabit.lastIndex(of: "{") else { 
            print("❌ [HabitDetection] No opening brace found before habit key")
            return nil 
        }
        
        // Now find the matching closing brace
        let fromBrace = text.index(openBrace, offsetBy: 0)
        let afterBrace = String(text[fromBrace...])
        
        // Simple brace counting
        var braceCount = 0
        var endIndex: String.Index?
        
        for (index, char) in afterBrace.enumerated() {
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    endIndex = afterBrace.index(afterBrace.startIndex, offsetBy: index)
                    break
                }
            }
        }
        
        if let endIndex = endIndex {
            let jsonString = String(afterBrace[..<afterBrace.index(after: endIndex)])
            print("✅ [HabitDetection] Extracted raw JSON of length: \(jsonString.count)")
            return jsonString
        }
        
        print("❌ [HabitDetection] No matching closing brace found")
        return nil
    }

    /// Strips leading/trailing markdown code fences (``` or ```json) from a string
    private func stripCodeFences(_ input: String) -> String {
        var output = input
        if output.hasPrefix("```json") {
            if let firstFenceEnd = output.range(of: "\n") {
                output = String(output[firstFenceEnd.upperBound...])
            } else {
                output = output.replacingOccurrences(of: "```json", with: "")
            }
        } else if output.hasPrefix("```") {
            if let firstFenceEnd = output.range(of: "\n") {
                output = String(output[firstFenceEnd.upperBound...])
            } else {
                output = output.replacingOccurrences(of: "```", with: "")
            }
        }
        if output.hasSuffix("```") {
            if let lastFenceRange = output.range(of: "```", options: .backwards) {
                output.removeSubrange(lastFenceRange)
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Parses category string to HabitCategory enum
    private func parseCategory(from string: String) -> HabitCategory {
        let lowercased = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch lowercased {
        case "physical": return .physical
        case "mental": return .mental
        case "spiritual": return .spiritual
        case "social": return .social
        case "productivity": return .productivity
        case "mindfulness": return .mindfulness
        case "learning": return .learning
        case "virtue", "personal_growth": return .personalGrowth
        default: return .personalGrowth // Default to personal growth
        }
    }
    
    /// Parses frequency string to HabitFrequency enum
    private func parseFrequency(from string: String) -> HabitFrequency {
        let lowercased = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch lowercased {
        case "daily": return .daily
        case "weekly": return .weekly
        default:
            // Try to parse custom frequency (e.g., "every 3 days")
            if let days = extractNumberFromFrequency(lowercased) {
                return .custom(days: days)
            }
            return .daily // Default to daily
        }
    }
    
    /// Extracts number from frequency strings like "every 3 days"
    private func extractNumberFromFrequency(_ string: String) -> Int? {
        let regex = try? NSRegularExpression(pattern: #"every\s+(\d+)\s+days?"#, options: .caseInsensitive)
        let range = NSRange(location: 0, length: string.utf16.count)
        
        if let match = regex?.firstMatch(in: string, options: [], range: range),
           let numberRange = Range(match.range(at: 1), in: string) {
            return Int(string[numberRange])
        }
        
        return nil
    }
    
    /// Parses program structure from JSON (supports both old and new formats)
    private func parseProgram(from data: [String: Any]) -> HabitProgram? {
        // Try new flexible format first
        if let durationWeeks = data["duration_weeks"] as? Int,
           let phasesArray = data["phases"] as? [[String: Any]] {
            
            let phases = phasesArray.compactMap { phaseData -> ProgramPhase? in
                guard let weekStart = phaseData["week_start"] as? Int,
                      let weekEnd = phaseData["week_end"] as? Int,
                      let goal = phaseData["goal"] as? String,
                      let instructions = phaseData["instructions"] as? String else {
                    print("❌ [HabitDetection] Invalid phase data: \(phaseData)")
                    return nil
                }
                
                return ProgramPhase(
                    weekStart: weekStart,
                    weekEnd: weekEnd,
                    goal: goal,
                    instructions: instructions
                )
            }
            
            if !phases.isEmpty {
                return HabitProgram(durationWeeks: durationWeeks, phases: phases)
            }
        }
        
        // Fallback to old 4-week format for backward compatibility
        if let week1Data = data["week_1"] as? [String: Any],
           let week1Goal = week1Data["goal"] as? String,
           let week1Instructions = week1Data["instructions"] as? String,
           let week2Data = data["week_2"] as? [String: Any],
           let week2Goal = week2Data["goal"] as? String,
           let week2Instructions = week2Data["instructions"] as? String,
           let week3Data = data["week_3"] as? [String: Any],
           let week3Goal = week3Data["goal"] as? String,
           let week3Instructions = week3Data["instructions"] as? String,
           let week4Data = data["week_4"] as? [String: Any],
           let week4Goal = week4Data["goal"] as? String,
           let week4Instructions = week4Data["instructions"] as? String {
            
            // Convert old format to new format
            let phases = [
                ProgramPhase(weekStart: 1, weekEnd: 1, goal: week1Goal, instructions: week1Instructions),
                ProgramPhase(weekStart: 2, weekEnd: 2, goal: week2Goal, instructions: week2Instructions),
                ProgramPhase(weekStart: 3, weekEnd: 3, goal: week3Goal, instructions: week3Instructions),
                ProgramPhase(weekStart: 4, weekEnd: 4, goal: week4Goal, instructions: week4Instructions)
            ]
            
            return HabitProgram(durationWeeks: 4, phases: phases)
        }
        
        print("❌ [HabitDetection] Invalid program structure - neither new nor old format")
        return nil
    }
    
    /// Parses reminders array from JSON
    private func parseReminders(from data: [[String: Any]]) -> [HabitReminder] {
        return data.compactMap { reminderData in
            guard let time = reminderData["time"] as? String,
                  let message = reminderData["message"] as? String,
                  let frequency = reminderData["frequency"] as? String else {
                print("❌ [HabitDetection] Invalid reminder data: \(reminderData)")
                return nil
            }
            
            let type = reminderData["type"] as? String // Optional field
            
            return HabitReminder(time: time, message: message, frequency: frequency, type: type)
        }
    }
    
    /// Removes the JSON structure from the text for display purposes
    func cleanTextFromHabitSuggestion(_ text: String) -> String {
        // Simple approach: remove everything after we detect JSON
        
        // Method 1: Remove code fenced JSON
        if let codeStart = text.range(of: "```") {
            let cleanText = String(text[..<codeStart.lowerBound])
            return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Method 2: Remove raw JSON
        if text.contains("ai_habit_suggestion") || text.contains("\"name\":") {
            if let jsonStart = text.range(of: "{") {
                let cleanText = String(text[..<jsonStart.lowerBound])
                return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}
