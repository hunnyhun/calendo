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
            // First try to parse as dictionary to validate structure
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            
            // Check if it has the required structure for comprehensive habit
            guard jsonObject != nil,
                  jsonObject?["name"] != nil,
                  jsonObject?["low_level_schedule"] != nil else {
                print("❌ [HabitDetection] JSON missing required comprehensive habit fields")
                return nil
            }
            
            // Parse the comprehensive habit structure using JSONDecoder
            let decoder = JSONDecoder()
            let comprehensiveHabit = try decoder.decode(ComprehensiveHabit.self, from: jsonData)
            
            print("✅ [HabitDetection] Successfully detected comprehensive habit: \(comprehensiveHabit.name)")
            return comprehensiveHabit
            
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ [HabitDetection] Missing key '\(key.stringValue)' in path: \(context.codingPath)")
            print("🔍 [HabitDetection] JSON that failed to parse: \(String(jsonString.prefix(500)))")
            // Fall through to legacy parsing
            return nil
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ [HabitDetection] Type mismatch for '\(context.codingPath)': expected \(type), got \(context.debugDescription)")
            print("🔍 [HabitDetection] JSON that failed to parse: \(String(jsonString.prefix(500)))")
            // Fall through to legacy parsing
            return nil
        } catch {
            print("❌ [HabitDetection] Failed to parse comprehensive habit: \(error.localizedDescription)")
            print("🔍 [HabitDetection] Error details: \(error)")
            print("🔍 [HabitDetection] JSON that failed to parse: \(String(jsonString.prefix(500)))")
            // Fall through to legacy parsing
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
            
            // Extract difficulty from data, default to "beginner" if not present
            let difficulty = habitData["difficulty"] as? String ?? "beginner"
            // Validate difficulty is one of the allowed values
            let validDifficulty = ["beginner", "intermediate", "advanced"].contains(difficulty.lowercased()) 
                ? difficulty.lowercased() 
                : "beginner"
            
            // Create comprehensive habit from legacy data
            let goal = habitData["goal"] as? String ?? description
            
            // Try to parse high_level_schedule from JSON if it exists
            let highLevelSchedule: HabitHighLevelSchedule
            if let highLevelData = habitData["high_level_schedule"] as? [String: Any],
               let milestonesData = highLevelData["milestones"] as? [[String: Any]] {
                // Parse milestones from JSON
                let milestones = milestonesData.compactMap { milestoneData -> HabitMilestone? in
                    guard let index = milestoneData["index"] as? Int,
                          let description = milestoneData["description"] as? String,
                          let completionCriteria = milestoneData["completion_criteria"] as? String,
                          let completionCriteriaPoint = milestoneData["completion_criteria_point"] as? Double,
                          let rewardMessage = milestoneData["reward_message"] as? String else {
                        return nil
                    }
                    return HabitMilestone(
                        index: index,
                        description: description,
                        completionCriteria: completionCriteria,
                        completionCriteriaPoint: completionCriteriaPoint,
                        rewardMessage: rewardMessage
                    )
                }
                if !milestones.isEmpty {
                    highLevelSchedule = HabitHighLevelSchedule(milestones: milestones)
                    print("✅ [HabitDetection] Parsed \(milestones.count) milestones from JSON")
                } else {
                    // Fallback to default milestone
                    highLevelSchedule = HabitHighLevelSchedule(milestones: [
                        HabitMilestone(
                            index: 0,
                            description: "Establish the habit",
                            completionCriteria: "streak_of_days",
                            completionCriteriaPoint: 7,
                            rewardMessage: "Great start! You're building consistency."
                        )
                    ])
                }
            } else {
                // Create basic milestones for legacy format (now in high_level_schedule)
                highLevelSchedule = HabitHighLevelSchedule(milestones: [
                    HabitMilestone(
                        index: 0,
                        description: "Establish the habit",
                        completionCriteria: "streak_of_days",
                        completionCriteriaPoint: 7,
                        rewardMessage: "Great start! You're building consistency."
                    )
                ])
            }
            
            // Try to parse low_level_schedule from JSON if it exists
            let lowLevelSchedule: HabitSchedule
            if let lowLevelData = habitData["low_level_schedule"] as? [String: Any] {
                // Parse low_level_schedule from JSON
                let span = lowLevelData["span"] as? String ?? "day"
                let spanValue = (lowLevelData["span_value"] as? Double) ?? (lowLevelData["span_value"] as? Int).map(Double.init) ?? 1.0
                let habitSchedule = (lowLevelData["habit_schedule"] as? Double) ?? (lowLevelData["habit_schedule"] as? Int).map(Double.init)
                let habitRepeatCount = (lowLevelData["habit_repeat_count"] as? Double) ?? (lowLevelData["habit_repeat_count"] as? Int).map(Double.init)
                
                // Parse program array
                var program: [HabitProgramSchedule] = []
                if let programData = lowLevelData["program"] as? [[String: Any]] {
                    program = programData.compactMap { programItem -> HabitProgramSchedule? in
                        // Parse days_indexed
                        let daysIndexed = (programItem["days_indexed"] as? [[String: Any]])?.compactMap { dayData -> DaysIndexedItem? in
                            guard let index = dayData["index"] as? Int,
                                  let title = dayData["title"] as? String,
                                  let contentData = dayData["content"] as? [[String: Any]] else {
                                return nil
                            }
                            let content = contentData.compactMap { stepData -> DayStepContent? in
                                guard let step = stepData["step"] as? String else { return nil }
                                let clock = stepData["clock"] as? String
                                return DayStepContent(step: step, clock: clock)
                            }
                            let reminders = (dayData["reminders"] as? [[String: Any]])?.compactMap { reminderData -> HabitReminderNew? in
                                let time = reminderData["time"] as? String
                                let message = reminderData["message"] as? String
                                return HabitReminderNew(time: time, message: message)
                            } ?? []
                            return DaysIndexedItem(index: index, title: title, content: content, reminders: reminders)
                        } ?? []
                        
                        // Parse weeks_indexed
                        let weeksIndexed = (programItem["weeks_indexed"] as? [[String: Any]])?.compactMap { weekData -> WeeksIndexedItem? in
                            guard let index = weekData["index"] as? Int,
                                  let title = weekData["title"] as? String,
                                  let weekDescription = weekData["description"] as? String,
                                  let contentData = weekData["content"] as? [[String: Any]] else {
                                return nil
                            }
                            let content = contentData.compactMap { stepData -> WeekStepContent? in
                                guard let step = stepData["step"] as? String,
                                      let day = stepData["day"] as? String else {
                                    return nil
                                }
                                return WeekStepContent(step: step, day: day)
                            }
                            let reminders = (weekData["reminders"] as? [[String: Any]])?.compactMap { reminderData -> HabitReminderNew? in
                                let time = reminderData["time"] as? String
                                let message = reminderData["message"] as? String
                                return HabitReminderNew(time: time, message: message)
                            } ?? []
                            return WeeksIndexedItem(index: index, title: title, description: weekDescription, content: content, reminders: reminders)
                        } ?? []
                        
                        // Parse months_indexed
                        let monthsIndexed = (programItem["months_indexed"] as? [[String: Any]])?.compactMap { monthData -> MonthsIndexedItem? in
                            guard let index = monthData["index"] as? Int,
                                  let title = monthData["title"] as? String,
                                  let monthDescription = monthData["description"] as? String,
                                  let contentData = monthData["content"] as? [[String: Any]] else {
                                return nil
                            }
                            let content = contentData.compactMap { stepData -> MonthStepContent? in
                                guard let step = stepData["step"] as? String,
                                      let day = stepData["day"] as? String else {
                                    return nil
                                }
                                return MonthStepContent(step: step, day: day)
                            }
                            let reminders = (monthData["reminders"] as? [[String: Any]])?.compactMap { reminderData -> HabitReminderNew? in
                                let time = reminderData["time"] as? String
                                let message = reminderData["message"] as? String
                                return HabitReminderNew(time: time, message: message)
                            } ?? []
                            return MonthsIndexedItem(index: index, title: title, description: monthDescription, content: content, reminders: reminders)
                        } ?? []
                        
                        return HabitProgramSchedule(daysIndexed: daysIndexed, weeksIndexed: weeksIndexed, monthsIndexed: monthsIndexed)
                    }
                }
                
                if !program.isEmpty {
                    lowLevelSchedule = HabitSchedule(
                        span: span,
                        spanValue: spanValue,
                        habitSchedule: habitSchedule,
                        habitRepeatCount: habitRepeatCount,
                        program: program
                    )
                    print("✅ [HabitDetection] Parsed low_level_schedule from JSON: span=\(span), span_value=\(spanValue)")
                } else {
                    // Fallback to default schedule
                    lowLevelSchedule = HabitSchedule(
                        span: span,
                        spanValue: spanValue,
                        habitSchedule: habitSchedule,
                        habitRepeatCount: habitRepeatCount,
                        program: [
                            HabitProgramSchedule(
                                daysIndexed: [
                                    DaysIndexedItem(
                                        index: 1,
                                        title: "Daily Practice",
                                        content: [
                                            DayStepContent(
                                                step: description,
                                                clock: nil
                                            )
                                        ],
                                        reminders: []
                                    )
                                ],
                                weeksIndexed: [],
                                monthsIndexed: []
                            )
                        ]
                    )
                }
            } else {
                // Create a default low-level schedule for legacy habits (daily by default)
                // This ensures habits always have a schedule so they appear on the calendar
                lowLevelSchedule = HabitSchedule(
                    span: "day",
                    spanValue: 1,
                    habitSchedule: nil, // Repeat indefinitely
                    habitRepeatCount: nil,
                    program: [
                        HabitProgramSchedule(
                            daysIndexed: [
                                DaysIndexedItem(
                                    index: 1,
                                    title: "Daily Practice",
                                    content: [
                                        DayStepContent(
                                            step: description,
                                            clock: nil
                                        )
                                    ],
                                    reminders: []
                                )
                            ],
                            weeksIndexed: [],
                            monthsIndexed: []
                        )
                    ]
                )
            }
            
            // Extract createdAt from AI suggestion if available
            let createdAt = habitData["created_at"] as? String
            
            let comprehensiveHabit = ComprehensiveHabit(
                id: UUID().uuidString,
                name: title,
                goal: goal,
                category: categoryString,
                description: description,
                difficulty: validDifficulty,
                lowLevelSchedule: lowLevelSchedule,
                highLevelSchedule: highLevelSchedule,
                createdAt: createdAt,
                startDate: nil, // startDate will be set when user pushes to calendar
                isActive: true // New habits are active by default
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
    
    /// Removes the JSON structure and HABITGEN flags from the text for display purposes
    func cleanTextFromHabitSuggestion(_ text: String) -> String {
        var cleaned = text
        
        // Step 1: Remove HABITGEN flags (case-insensitive, any spacing)
        cleaned = cleaned.replacingOccurrences(
            of: "\\[HABITGEN\\s*=\\s*True\\]",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\\[HABITGEN\\s*=\\s*true\\]",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: "HABITGEN=True",
            with: "",
            options: [.caseInsensitive]
        )
        
        // Step 2: Remove code fenced JSON
        if let codeStart = cleaned.range(of: "```") {
            let beforeCode = String(cleaned[..<codeStart.lowerBound])
            cleaned = beforeCode.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Step 3: Remove raw JSON (look for JSON object start)
        if cleaned.contains("ai_habit_suggestion") || cleaned.contains("\"name\":") {
            // Find all JSON objects and remove them
            if let jsonStart = cleaned.range(of: "{") {
                let beforeJson = String(cleaned[..<jsonStart.lowerBound])
                cleaned = beforeJson.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Step 4: Clean up any remaining artifacts (extra whitespace, empty lines)
        cleaned = cleaned
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
}
