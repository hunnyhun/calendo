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
            // Parse the JSON structure
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            
            guard let json = json else {
                print("❌ [TaskDetection] Could not parse JSON")
                return nil
            }
            
            // Extract required fields
            guard let name = json["name"] as? String,
                  let description = json["description"] as? String else {
                print("❌ [TaskDetection] Missing required fields (name, description)")
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
                let date = stepDict["date"] as? String // YYYY-MM-DD or null
                let time = stepDict["time"] as? String // HH:MM or null
                let isCompleted = stepDict["isCompleted"] as? Bool ?? false
                
                // Parse reminders
                var reminders: [TaskReminder] = []
                if let remindersArray = stepDict["reminders"] as? [[String: Any]] {
                    reminders = remindersArray.compactMap { reminderDict in
                        guard let offsetDict = reminderDict["offset"] as? [String: Any],
                              let unitString = offsetDict["unit"] as? String,
                              let unit = ReminderUnit(rawValue: unitString),
                              let value = offsetDict["value"] as? Int else {
                        return nil
                    }
                        
                        let reminderTime = reminderDict["time"] as? String
                        let message = reminderDict["message"] as? String
                        
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
            let createdAt: String?
            if let createdAtString = json["created_at"] as? String {
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
                name: name,
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
            
            print("✅ [TaskDetection] Successfully detected task: \(task.name)")
            return task
            
        } catch {
            print("❌ [TaskDetection] Failed to parse task: \(error.localizedDescription)")
            print("🔍 [TaskDetection] JSON that failed to parse: \(jsonString)")
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
    
    /// Extracts JSON from code fence (```json ... ```)
    private func extractCodeFencedJSON(from text: String) -> String? {
        // Look for ```json ... ``` pattern
        let pattern = "```json\\s*([\\s\\S]*?)```"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first,
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let jsonRange = match.range(at: 1)
        let jsonString = nsString.substring(with: jsonRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("✅ [TaskDetection] Found JSON in code fence")
        return jsonString
    }
    
    /// Extracts raw JSON from text
    private func extractRawJSON(from text: String) -> String? {
        // Look for { ... } pattern with name, description, and steps
        let pattern = "\\{[\\s\\S]*?\"name\"[\\s\\S]*?\"description\"[\\s\\S]*?\"steps\"[\\s\\S]*?\\}"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first else {
            return nil
        }
        
        let jsonString = nsString.substring(with: match.range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("✅ [TaskDetection] Found raw JSON")
        return jsonString
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
        
        // Step 2: Remove code-fenced JSON
        cleanedText = cleanedText.replacingOccurrences(
            of: "```json[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )
        
        // Step 3: Remove raw JSON (both new and legacy structures)
        cleanedText = cleanedText.replacingOccurrences(
            of: "\\{[\\s\\S]*?\"name\"[\\s\\S]*?\"description\"[\\s\\S]*?(\"task_schedule\"|\"steps\")[\\s\\S]*?\\}",
            with: "",
            options: .regularExpression
        )
        
        // Step 4: Clean up extra whitespace
        cleanedText = cleanedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        return cleanedText
    }
}

