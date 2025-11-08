import Foundation

/// Service for detecting AI-generated task suggestions in chat responses
class TaskDetectionService {
    static let shared = TaskDetectionService()
    
    private init() {}
    
    /// Detects if a chat message contains an AI task suggestion
    func detectTaskSuggestion(in text: String, userId: String?) -> UserTask? {
        print("🔍 [TaskDetection] Looking for task in text...")
        
        // Extract JSON string
        guard let jsonString = extractJSONString(from: text) else {
            print("❌ [TaskDetection] No JSON found")
            return nil
        }
        
        print("🔍 [TaskDetection] Extracted JSON string length: \(jsonString.count)")
        print("🔍 [TaskDetection] JSON preview: \(String(jsonString.prefix(200)))")
        
        // Try to parse as task
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ [TaskDetection] Could not convert JSON string to data")
            return nil
        }
        
        do {
            // Parse the JSON structure - handle both array and single object
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            
            // Handle array of tasks - take the first one
            if let jsonArray = jsonObject as? [[String: Any]], let firstTask = jsonArray.first {
                print("✅ [TaskDetection] Found array of tasks, using first task")
                return parseTaskFromJSON(json: firstTask, userId: userId)
            }
            
            // Handle single task object
            if let json = jsonObject as? [String: Any] {
                return parseTaskFromJSON(json: json, userId: userId)
            }
            
            print("❌ [TaskDetection] JSON is neither array nor object")
            return nil
            
        } catch {
            print("❌ [TaskDetection] Could not parse JSON: \(error.localizedDescription)")
            print("🔍 [TaskDetection] JSON preview: \(String(jsonString.prefix(500)))")
            return nil
        }
    }
    
    /// Parses task JSON directly from a dictionary (useful for V3 responses)
    func detectTaskSuggestion(from json: [String: Any], userId: String?) -> UserTask? {
        print("🔍 [TaskDetection] Parsing task from dictionary...")
        return parseTaskFromJSON(json: json, userId: userId)
    }
    
    /// Internal method to parse task from JSON dictionary
    private func parseTaskFromJSON(json: [String: Any], userId: String?) -> UserTask? {
        do {
            // Extract required fields - support both "name" and "task_name" fields
            let name = json["name"] as? String ?? 
                      json["task_name"] as? String ?? 
                      json["taskName"] as? String
            
            guard let taskName = name,
                  let description = json["description"] as? String else {
                print("❌ [TaskDetection] Missing required fields (name/task_name, description)")
                print("🔍 [TaskDetection] Available keys: \(json.keys.joined(separator: ", "))")
                return nil
            }
            
            // Extract optional fields
            let goal = json["goal"] as? String
            let category = json["category"] as? String
            
            // Parse task_schedule with steps
            var taskSteps: [TaskStep] = []
            guard let taskScheduleDict = json["task_schedule"] as? [String: Any],
                  let stepsArray = taskScheduleDict["steps"] as? [[String: Any]] else {
                print("❌ [TaskDetection] Missing task_schedule.steps")
                return nil
            }
            
            taskSteps = stepsArray.enumerated().compactMap { (idx, stepDict) in
                let index = stepDict["index"] as? Int ?? (idx + 1)
                let title = stepDict["title"] as? String
                let stepDescription = stepDict["description"] as? String
                
                // Handle NSNull values - check if value is NSNull before casting
                let date: String? = {
                    if stepDict["date"] is NSNull { return nil }
                    return stepDict["date"] as? String
                }()
                let time: String? = {
                    if stepDict["time"] is NSNull { return nil }
                    return stepDict["time"] as? String
                }()
                
                let isCompleted = stepDict["isCompleted"] as? Bool ?? false
                
                // Ensure at least title or description is present
                guard title != nil || stepDescription != nil else {
                    print("⚠️ [TaskDetection] Step \(index) missing both title and description, skipping")
                    return nil
                }
                
                // Parse reminders
                var reminders: [TaskReminder] = []
                if let remindersArray = stepDict["reminders"] as? [[String: Any]] {
                    reminders = remindersArray.compactMap { reminderDict in
                        guard let offsetDict = reminderDict["offset"] as? [String: Any],
                              let unitString = offsetDict["unit"] as? String,
                              let unit = ReminderUnit(rawValue: unitString),
                              let value = offsetDict["value"] as? Int else {
                            print("⚠️ [TaskDetection] Invalid reminder structure, skipping")
                            return nil
                        }
                        
                        // Handle NSNull values from JSON
                        let reminderTime: String? = {
                            if reminderDict["time"] is NSNull { return nil }
                            return reminderDict["time"] as? String
                        }()
                        let message: String? = {
                            if reminderDict["message"] is NSNull { return nil }
                            return reminderDict["message"] as? String
                        }()
                        
                        return TaskReminder(
                            offset: ReminderOffset(unit: unit, value: value),
                            time: reminderTime,
                            message: message
                        )
                    }
                }
                
                // Convert date string to Date if available
                var scheduledDate: Date? = nil
                if let dateString = date {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    scheduledDate = formatter.date(from: dateString)
                    
                    // Add time if available
                    if let timeString = time, let baseDate = scheduledDate {
                        let timeFormatter = DateFormatter()
                        timeFormatter.dateFormat = "HH:mm"
                        if let timeValue = timeFormatter.date(from: timeString) {
                            let calendar = Calendar.current
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: timeValue)
                            scheduledDate = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: baseDate)
                        }
                    }
                }
                
                    return TaskStep(
                    index: index,
                    title: title,
                        description: stepDescription,
                    date: date,
                    time: time,
                        isCompleted: isCompleted,
                    scheduledDate: scheduledDate,
                    reminders: reminders
                    )
            }
            
            // Parse createdAt (should be ISO8601 string, like habits)
            // Also check for "createdAt" (camelCase) as fallback
            let createdAt: String?
            if let createdAtString = json["created_at"] as? String {
                createdAt = createdAtString
            } else if let createdAtString = json["createdAt"] as? String {
                createdAt = createdAtString
            } else {
                // If not provided, use current time as ISO8601 string
                createdAt = ISO8601DateFormatter().string(from: Date())
            }
            
            // Create task schedule
            let taskSchedule = TaskSchedule(steps: taskSteps)
            
            // Create UserTask with new structure
            // startDate will be set when user pushes to calendar (like habits)
            let task = UserTask(
                id: UUID().uuidString,
                name: taskName,
                goal: goal,
                category: category,
                description: description,
                createdAt: createdAt,
                completedAt: nil,
                isCompleted: false,
                taskSchedule: taskSchedule,
                createdBy: userId,
                startDate: nil, // startDate will be set when user pushes to calendar
                isActive: true // New tasks are active by default
            )
            
            print("✅ [TaskDetection] Successfully detected task: \(task.name) with \(taskSteps.count) steps")
            return task
            
        } catch {
            print("❌ [TaskDetection] Failed to parse task: \(error.localizedDescription)")
            print("🔍 [TaskDetection] JSON keys available: \(json.keys.joined(separator: ", "))")
            return nil
        }
    }
    
    /// Extracts JSON string from text (handles code fences and raw JSON)
    private func extractJSONString(from text: String) -> String? {
        print("🔍 [TaskDetection] Extracting JSON from text of length: \(text.count)")
        
        // First try to find code-fenced JSON
        print("🔍 [TaskDetection] Looking for code fenced JSON...")
        if let fencedJSON = extractCodeFencedJSON(from: text) {
            return fencedJSON
        }
        
        // Try to find raw JSON
        print("🔍 [TaskDetection] Looking for raw JSON...")
        if let rawJSON = extractRawJSON(from: text) {
            return rawJSON
        }
        
        print("❌ [TaskDetection] No JSON found in text")
        return nil
    }
    
    /// Extracts JSON from code fence (```json ... ``` or ``` ... ```)
    private func extractCodeFencedJSON(from text: String) -> String? {
        print("🔍 [TaskDetection] Looking for code fenced JSON...")
        
        // Look for ```json ... ``` or ``` ... ``` pattern
        let patterns = ["```json", "```"]
        
        for pattern in patterns {
            var searchRange = text.startIndex..<text.endIndex
            while let startRange = text.range(of: pattern, range: searchRange) {
                print("🔍 [TaskDetection] Found opening fence: \(pattern)")
                let afterStart = text.index(startRange.upperBound, offsetBy: 0)
                let remainingText = String(text[afterStart...])
                
                // Find closing ```
                if let endRange = remainingText.range(of: "```") {
                    let jsonContent = String(remainingText[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("🔍 [TaskDetection] Extracted content length: \(jsonContent.count)")
                    
                    // Validate it's valid JSON first
                    if let jsonData = jsonContent.data(using: .utf8),
                       (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
                
                // Check if it looks like task JSON (has task markers)
                        if jsonContent.contains("\"task_name\"") || 
                           jsonContent.contains("\"taskName\"") ||
                           jsonContent.contains("\"task_schedule\"") ||
                           (jsonContent.contains("\"name\"") && jsonContent.contains("\"description\"") && 
                            (jsonContent.contains("\"steps\"") || jsonContent.contains("\"task_schedule\""))) {
                            print("✅ [TaskDetection] Found valid task JSON in code fence")
                            return jsonContent
                        } else {
                            print("❌ [TaskDetection] Code fence content doesn't contain task markers")
                        }
                    } else {
                        print("❌ [TaskDetection] Code fence content is not valid JSON")
                    }
                    
                    // Move search range past this fence
                    searchRange = text.index(endRange.upperBound, offsetBy: remainingText.distance(from: remainingText.startIndex, to: endRange.upperBound))..<text.endIndex
                } else {
                    print("❌ [TaskDetection] No closing fence found")
                    break
                }
            }
        }
        
        return nil
    }
    
    /// Extracts raw JSON from text - handles both arrays and objects
    private func extractRawJSON(from text: String) -> String? {
        print("🔍 [TaskDetection] Looking for raw JSON...")
        
        // Check if text contains task markers (more comprehensive)
        let hasTaskMarkers = text.contains("\"task_name\"") || 
                            text.contains("\"taskName\"") ||
                            text.contains("\"task_schedule\"") ||
                            (text.contains("\"name\"") && text.contains("\"description\"") && 
                             (text.contains("\"steps\"") || text.contains("\"task_schedule\"")))
        
        guard hasTaskMarkers else {
            print("❌ [TaskDetection] No task markers found in text")
            return nil
        }
        
        // Find all potential JSON starts
        var candidates: [String.Index] = []
        
        // Priority markers for tasks
        let markers = ["\"task_schedule\"", "\"task_name\"", "\"taskName\"", "\"name\""]
        
        for marker in markers {
            if let range = text.range(of: marker) {
                // Find the opening brace or bracket before this marker
                let beforeMarker = String(text[..<range.lowerBound])
                if let openBrace = beforeMarker.lastIndex(where: { $0 == "{" || $0 == "[" }) {
                    if !candidates.contains(openBrace) {
                        candidates.append(openBrace)
                    }
                }
            }
        }
        
        // Also try finding the first { or [ if no markers found specific positions
        if candidates.isEmpty {
            if let firstOpen = text.firstIndex(where: { $0 == "{" || $0 == "[" }) {
                candidates.append(firstOpen)
            }
        }
        
        // Try each candidate
        for firstOpen in candidates {
            // Find matching closing brace/bracket with proper string handling
        var depth = 0
            var inString = false
            var escapeNext = false
        var endIndex: String.Index?
        
        for index in text.indices[firstOpen...] {
            let char = text[index]
            
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
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = text.index(after: index)
                    break
                }
            } else if char == "[" {
                depth += 1
            } else if char == "]" {
                depth -= 1
                if depth == 0 {
                    endIndex = text.index(after: index)
                    break
                        }
                }
            }
        }
        
        guard let endIdx = endIndex else {
                continue
        }
        
        let jsonCandidate = String(text[firstOpen..<endIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate it's valid JSON and contains task markers
        if let data = jsonCandidate.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            print("✅ [TaskDetection] Found raw JSON")
            return jsonCandidate
            } else {
                print("⚠️ [TaskDetection] Extracted string is not valid JSON, trying next candidate")
            }
        }
        
        print("❌ [TaskDetection] No valid JSON found in text")
        return nil
    }
    
    /// Removes task JSON and any flags from text for clean display
    func cleanTextFromTaskSuggestion(_ text: String) -> String {
        var cleanedText = text
        
        // Step 1: Remove any task generation flags (if they exist)
        cleanedText = cleanedText.replacingOccurrences(
            of: "\\[TASKGEN\\s*=\\s*True\\]",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleanedText = cleanedText.replacingOccurrences(
            of: "TASKGEN=True",
            with: "",
            options: [.caseInsensitive]
        )
        
        // Step 2: Remove code-fenced JSON (keep text before and after)
        // Find the first opening fence
        if let codeStart = cleanedText.range(of: "```") {
            // Find the closing fence after the opening one
            let afterStart = cleanedText.index(codeStart.upperBound, offsetBy: 0)
            let remainingText = String(cleanedText[afterStart...])
            
            if let codeEnd = remainingText.range(of: "```") {
                // We have both opening and closing fences
                let beforeCode = String(cleanedText[..<codeStart.lowerBound])
                let afterCode = String(remainingText[codeEnd.upperBound...])
                
                // Combine text before and after the code fence
                let combined = (beforeCode + afterCode).trimmingCharacters(in: .whitespacesAndNewlines)
                cleanedText = combined
            } else {
                // No closing fence found, just remove from opening fence onwards
                let beforeCode = String(cleanedText[..<codeStart.lowerBound])
                cleanedText = beforeCode.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Step 3: Remove raw JSON (both new and legacy structures) - only if no code fence was found
        // This handles cases where JSON is embedded without code fences
        if cleanedText.contains("\"task_name\"") || 
           cleanedText.contains("\"taskName\"") ||
           cleanedText.contains("\"task_schedule\"") ||
           (cleanedText.contains("\"name\"") && cleanedText.contains("\"description\"") && 
            (cleanedText.contains("\"steps\"") || cleanedText.contains("\"task_schedule\""))) {
            // Find the first opening brace that starts a JSON object
            if let jsonStart = cleanedText.range(of: "{") {
                // Try to find the matching closing brace
                var braceCount = 0
                var inString = false
                var escapeNext = false
                var jsonEnd: String.Index?
                
                for index in cleanedText.indices[jsonStart.lowerBound...] {
                    let char = cleanedText[index]
                    
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
                                jsonEnd = cleanedText.index(after: index)
                                break
                            }
                        }
                    }
                }
                
                if let jsonEnd = jsonEnd {
                    // Remove the JSON object but keep text before and after
                    let beforeJson = String(cleanedText[..<jsonStart.lowerBound])
                    let afterJson = String(cleanedText[jsonEnd...])
                    let combined = (beforeJson + afterJson).trimmingCharacters(in: .whitespacesAndNewlines)
                    cleanedText = combined
                } else {
                    // No matching closing brace, just remove from opening brace
                    let beforeJson = String(cleanedText[..<jsonStart.lowerBound])
                    cleanedText = beforeJson.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Step 4: Clean up extra whitespace
        cleanedText = cleanedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        return cleanedText
    }
}

