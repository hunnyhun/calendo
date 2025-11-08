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
    
    /// Parses habit JSON directly from a dictionary (useful for V3 responses)
    func detectHabitSuggestion(from json: [String: Any], messageId: String, userId: String?) -> ComprehensiveHabit? {
        print("🔍 [HabitDetection] Parsing habit from dictionary...")
        
        // Validate that the dictionary can be serialized to JSON
        guard (try? JSONSerialization.data(withJSONObject: json)) != nil else {
            print("❌ [HabitDetection] Could not convert dictionary to JSON data")
            return nil
        }
        
        // Add id field if missing
        var jsonDict = json
        if jsonDict["id"] == nil {
            jsonDict["id"] = UUID().uuidString
            print("🔍 [HabitDetection] Added missing 'id' field to JSON")
        }
        
        // Re-encode with id
        guard let updatedJsonData = try? JSONSerialization.data(withJSONObject: jsonDict) else {
            print("❌ [HabitDetection] Could not re-encode JSON with id")
            return nil
        }
        
        // Try to decode as comprehensive habit
        do {
            let decoder = JSONDecoder()
            let comprehensiveHabit = try decoder.decode(ComprehensiveHabit.self, from: updatedJsonData)
            print("✅ [HabitDetection] Successfully parsed habit from dictionary: \(comprehensiveHabit.name)")
            return comprehensiveHabit
        } catch {
            print("❌ [HabitDetection] Failed to parse habit from dictionary: \(error.localizedDescription)")
            // Fallback to legacy parsing
            return parseLegacyHabitFromDictionary(jsonDict, messageId: messageId, userId: userId)
        }
    }
    
    /// Helper to parse legacy habit format from dictionary
    private func parseLegacyHabitFromDictionary(_ habitData: [String: Any], messageId: String, userId: String?) -> ComprehensiveHabit? {
        // This is similar to detectLegacyHabit but works with a dictionary directly
        // For now, convert dictionary to JSON string and use text-based detection
        // This ensures consistency with the main detection flow
        guard let jsonData = try? JSONSerialization.data(withJSONObject: habitData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("❌ [HabitDetection] Could not convert dictionary to JSON string")
            return nil
        }
        
        // Use the text-based detection method which has full implementation
        return detectLegacyHabit(in: jsonString, messageId: messageId, userId: userId)
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
            guard var jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ [HabitDetection] JSON is not a dictionary")
                return nil
            }
            
            // Check if it has basic required fields (name or habitName, description)
            let hasName = jsonDict["name"] != nil || jsonDict["habitName"] != nil
            let hasDescription = jsonDict["description"] != nil
            
            guard hasName && hasDescription else {
                print("❌ [HabitDetection] JSON missing basic required fields (name/habitName, description)")
                return nil
            }
            
            // If it has low_level_schedule, try to parse as comprehensive format
            // Otherwise, fall through to legacy format which will handle it
            if jsonDict["low_level_schedule"] != nil {
                // Add id field if missing (backend-generated JSON doesn't include it)
                if jsonDict["id"] == nil {
                    jsonDict["id"] = UUID().uuidString
                    print("🔍 [HabitDetection] Added missing 'id' field to JSON")
                }
                
                // Re-encode with id field
                let updatedJsonData = try JSONSerialization.data(withJSONObject: jsonDict)
                
                // Parse the comprehensive habit structure using JSONDecoder
                let decoder = JSONDecoder()
                let comprehensiveHabit = try decoder.decode(ComprehensiveHabit.self, from: updatedJsonData)
                
                print("✅ [HabitDetection] Successfully detected comprehensive habit: \(comprehensiveHabit.name)")
                return comprehensiveHabit
            } else {
                // No low_level_schedule, will be handled by legacy format
                print("🔍 [HabitDetection] No low_level_schedule found, will use legacy format")
                return nil
            }
            
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ [HabitDetection] Missing key '\(key.stringValue)' in path: \(context.codingPath)")
            // Fall through to legacy parsing
            return nil
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ [HabitDetection] Type mismatch for '\(context.codingPath)': expected \(type)")
            // Fall through to legacy parsing
            return nil
        } catch {
            print("❌ [HabitDetection] Failed to parse comprehensive habit: \(error.localizedDescription)")
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
            if let directHabit = json, (directHabit["name"] != nil || directHabit["habitName"] != nil) {
                // New format - direct habit JSON (supports both "name" and "habitName")
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
            
            // Extract required fields (handle both new and legacy formats, including "habitName" variant)
            let title = habitData["name"] as? String ?? 
                       habitData["habitName"] as? String ?? 
                       habitData["title"] as? String ?? 
                       "New Habit"
            guard let description = habitData["description"] as? String else {
                print("❌ [HabitDetection] Missing required 'description' field in habit suggestion")
                return nil
            }
            // Category is optional for legacy formats, default to "general"
            let categoryString = habitData["category"] as? String ?? "general"
            
            // Extract difficulty from data - handle both string and numeric values
            // Numeric scale: 1-2 = beginner, 3-4 = intermediate, 5 = advanced
            let validDifficulty: String
            if let difficultyNum = habitData["difficulty"] as? Int {
                // Map numeric difficulty (1-5 scale) to string
                switch difficultyNum {
                case 1, 2:
                    validDifficulty = "beginner"
                case 3, 4:
                    validDifficulty = "intermediate"
                case 5:
                    validDifficulty = "advanced"
                default:
                    validDifficulty = "beginner"
                }
                print("🔍 [HabitDetection] Converted numeric difficulty \(difficultyNum) to \(validDifficulty)")
            } else if let difficultyStr = habitData["difficulty"] as? String {
                // Validate string difficulty is one of the allowed values
                validDifficulty = ["beginner", "intermediate", "advanced"].contains(difficultyStr.lowercased()) 
                    ? difficultyStr.lowercased() 
                : "beginner"
            } else {
                validDifficulty = "beginner"
            }
            
            // Create comprehensive habit from legacy data
            // Use goal if available, otherwise use description, or try to extract from schedule info
            let goal: String
            if let goalStr = habitData["goal"] as? String, !goalStr.isEmpty {
                goal = goalStr
            } else if let scheduleStr = habitData["schedule"] as? String, !scheduleStr.isEmpty {
                // If no goal but schedule exists, use description with schedule info
                goal = "\(description) - \(scheduleStr)"
            } else {
                goal = description
            }
            
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
        // Try more specific patterns first, then fall back to generic
        let patterns = ["```json", "```"]
        
        for pattern in patterns {
            // Find all occurrences of the pattern
            var searchRange = text.startIndex..<text.endIndex
            while let startRange = text.range(of: pattern, range: searchRange) {
                print("🔍 [HabitDetection] Found opening fence: \(pattern)")
                let afterStart = text.index(startRange.upperBound, offsetBy: 0)
                let remainingText = String(text[afterStart...])
                
                // Find closing ``` - look for the first one after the opening
                if let endRange = remainingText.range(of: "```") {
                    let jsonContent = String(remainingText[..<endRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("🔍 [HabitDetection] Extracted content length: \(jsonContent.count)")
                    
                    // Validate it's valid JSON first
                    if let jsonData = jsonContent.data(using: .utf8),
                       (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
                    
                    // Check if it contains our habit suggestion (new format) or legacy format
                    // Support both "name" and "habitName" fields
                    if jsonContent.contains("ai_habit_suggestion") || 
                       jsonContent.contains("\"name\":") || 
                       jsonContent.contains("\"habitName\":") ||
                           jsonContent.contains("\"low_level_schedule\"") ||
                           jsonContent.contains("\"high_level_schedule\"") ||
                           jsonContent.contains("\"milestones\"") ||
                       (jsonContent.contains("\"description\":") && (jsonContent.contains("\"goal\":") || jsonContent.contains("\"category\":"))) {
                        print("✅ [HabitDetection] Found valid habit JSON in code fence")
                            return jsonContent
                    } else {
                        print("❌ [HabitDetection] Code fence content doesn't contain habit markers")
                        print("🔍 [HabitDetection] Content preview: \(String(jsonContent.prefix(100)))")
                    }
                    } else {
                        print("❌ [HabitDetection] Code fence content is not valid JSON")
                    }
                    
                    // Move search range past this fence to look for more
                    searchRange = text.index(endRange.upperBound, offsetBy: remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound))..<text.endIndex
                } else {
                    print("❌ [HabitDetection] No closing fence found")
                    break
                }
            }
        }
        
        return nil
    }
    
    private func extractRawJSON(_ text: String) -> String? {
        print("🔍 [HabitDetection] Looking for raw JSON...")
        
        // Look for habit markers (more comprehensive)
        let hasHabitMarkers = text.contains("ai_habit_suggestion") || 
              text.contains("\"name\":") || 
              text.contains("\"habitName\":") ||
                              text.contains("\"low_level_schedule\"") ||
                              text.contains("\"high_level_schedule\"") ||
                              text.contains("\"milestones\"") ||
                              (text.contains("\"description\":") && (text.contains("\"goal\":") || text.contains("\"category\":")))
        
        guard hasHabitMarkers else { 
            print("❌ [HabitDetection] No habit markers found in text")
            return nil 
        }
        
        // Find all potential JSON object starts (opening braces)
        var candidates: [(start: String.Index, priority: Int)] = []
        
        // Priority order: ai_habit_suggestion > low_level_schedule > high_level_schedule > milestones > name > habitName > description
        let markers = [
            ("ai_habit_suggestion", 1),
            ("\"low_level_schedule\"", 2),
            ("\"high_level_schedule\"", 3),
            ("\"milestones\"", 4),
            ("\"name\":", 5),
            ("\"habitName\":", 6),
            ("\"description\":", 7)
        ]
        
        for (marker, priority) in markers {
            if let range = text.range(of: marker) {
                // Find the opening brace before this marker
                let beforeMarker = String(text[..<range.lowerBound])
                if let openBrace = beforeMarker.lastIndex(of: "{") {
                    candidates.append((openBrace, priority))
                }
            }
        }
        
        // Sort by priority (lower is better) and position (earlier is better)
        candidates.sort { first, second in
            if first.priority != second.priority {
                return first.priority < second.priority
            }
            return first.start < second.start
        }
        
        // Try each candidate until we find valid JSON
        for (openBrace, _) in candidates {
            // Extract from this brace to the end (we'll find the matching closing brace)
        let fromBrace = text.index(openBrace, offsetBy: 0)
        let afterBrace = String(text[fromBrace...])
        
            // Count braces to find matching closing brace
        var braceCount = 0
            var inString = false
            var escapeNext = false
        var endIndex: String.Index?
        
        for (index, char) in afterBrace.enumerated() {
                let currentIndex = afterBrace.index(afterBrace.startIndex, offsetBy: index)
                
                if escapeNext {
                    escapeNext = false
                    continue
                }
                
                if char == "\\" {
                    escapeNext = true
                    continue
                }
                
                if char == "\"" && !escapeNext {
                    inString.toggle()
                    continue
                }
                
                if !inString {
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                            endIndex = afterBrace.index(after: currentIndex)
                    break
                        }
                }
            }
        }
        
        if let endIndex = endIndex {
                let jsonString = String(afterBrace[..<endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Validate it's valid JSON
                if let jsonData = jsonString.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
            print("✅ [HabitDetection] Extracted raw JSON of length: \(jsonString.count)")
            return jsonString
                } else {
                    print("⚠️ [HabitDetection] Extracted string is not valid JSON, trying next candidate")
                }
            }
        }
        
        print("❌ [HabitDetection] No valid JSON found in text")
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
        
        // Step 2: Remove code fenced JSON (keep text before and after)
        // Find the first opening fence
        if let codeStart = cleaned.range(of: "```") {
            // Find the closing fence after the opening one
            let afterStart = cleaned.index(codeStart.upperBound, offsetBy: 0)
            let remainingText = String(cleaned[afterStart...])
            
            if let codeEnd = remainingText.range(of: "```") {
                // We have both opening and closing fences
                let beforeCode = String(cleaned[..<codeStart.lowerBound])
                let afterCode = String(remainingText[codeEnd.upperBound...])
                
                // Combine text before and after the code fence
                let combined = (beforeCode + afterCode).trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned = combined
            } else {
                // No closing fence found, just remove from opening fence onwards
                let beforeCode = String(cleaned[..<codeStart.lowerBound])
                cleaned = beforeCode.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Step 3: Remove raw JSON (look for JSON object start) - only if no code fence was found
        // This handles cases where JSON is embedded without code fences
        if cleaned.contains("ai_habit_suggestion") || 
           cleaned.contains("\"name\":") || 
           cleaned.contains("\"habitName\":") ||
           (cleaned.contains("\"description\":") && (cleaned.contains("\"goal\":") || cleaned.contains("\"category\":"))) {
            // Find the first opening brace that starts a JSON object
            if let jsonStart = cleaned.range(of: "{") {
                // Try to find the matching closing brace
                var braceCount = 0
                var inString = false
                var escapeNext = false
                var jsonEnd: String.Index?
                
                for index in cleaned.indices[jsonStart.lowerBound...] {
                    let char = cleaned[index]
                    
                    if escapeNext {
                        escapeNext = false
                        continue
                    }
                    
                    if char == "\\" {
                        escapeNext = true
                        continue
                    }
                    
                    if char == "\"" && !escapeNext {
                        inString.toggle()
                        continue
                    }
                    
                    if !inString {
                        if char == "{" {
                            braceCount += 1
                        } else if char == "}" {
                            braceCount -= 1
                            if braceCount == 0 {
                                jsonEnd = cleaned.index(after: index)
                                break
                            }
                        }
                    }
                }
                
                if let jsonEnd = jsonEnd {
                    // Remove the JSON object but keep text before and after
                    let beforeJson = String(cleaned[..<jsonStart.lowerBound])
                    let afterJson = String(cleaned[jsonEnd...])
                    let combined = (beforeJson + afterJson).trimmingCharacters(in: .whitespacesAndNewlines)
                    cleaned = combined
                } else {
                    // No matching closing brace, just remove from opening brace
                    let beforeJson = String(cleaned[..<jsonStart.lowerBound])
                    cleaned = beforeJson.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Step 4: Clean up any remaining artifacts (extra whitespace, empty lines)
        cleaned = cleaned
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
}
