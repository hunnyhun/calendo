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
            
            // Parse steps
            var taskSteps: [TaskStep] = []
            if let stepsArray = json["steps"] as? [[String: Any]] {
                taskSteps = stepsArray.compactMap { stepDict in
                    guard let stepDescription = stepDict["description"] as? String else {
                        return nil
                    }
                    let isCompleted = stepDict["isCompleted"] as? Bool ?? false
                    return TaskStep(
                        id: UUID().uuidString,
                        description: stepDescription,
                        isCompleted: isCompleted,
                        scheduledDate: nil
                    )
                }
            }
            
            // Parse dates
            let createdAt: Date
            if let createdAtString = json["created_at"] as? String {
                let formatter = ISO8601DateFormatter()
                createdAt = formatter.date(from: createdAtString) ?? Date()
            } else {
                createdAt = Date()
            }
            
            // Create UserTask
            let task = UserTask(
                id: UUID().uuidString,
                name: name,
                description: description,
                createdAt: createdAt,
                completedAt: nil,
                isCompleted: false,
                steps: taskSteps,
                createdBy: userId ?? "unknown",
                deadline: nil,
                startDate: nil
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
    
    /// Removes task JSON from text for clean display
    func cleanTextFromTaskSuggestion(_ text: String) -> String {
        // Remove code-fenced JSON
        var cleanedText = text.replacingOccurrences(
            of: "```json[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )
        
        // Remove raw JSON
        cleanedText = cleanedText.replacingOccurrences(
            of: "\\{[\\s\\S]*?\"name\"[\\s\\S]*?\"description\"[\\s\\S]*?\"steps\"[\\s\\S]*?\\}",
            with: "",
            options: .regularExpression
        )
        
        // Clean up extra whitespace
        cleanedText = cleanedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        return cleanedText
    }
}

