import Foundation

/// Service for importing habits and tasks from shared content
@MainActor
class ImportService: ObservableObject {
    static let shared = ImportService()
    
    @Published var importableHabit: ComprehensiveHabit?
    @Published var importableTask: UserTask?
    @Published var importError: String?
    
    // Store share info for tracking imports
    private var currentShareId: String?
    private var currentShareType: String?
    
    private init() {}
    
    /// Attempts to parse a habit or task from a URL (share link)
    /// Supports both backend-generated links (calendo://share/type/shareId) and client-side links
    func parseFromURL(_ url: URL) async -> Bool {
        importableHabit = nil
        importableTask = nil
        importError = nil
        
        // Check if it's a backend-generated share link (calendo://share/type/shareId)
        if url.scheme == "calendo" && url.host == "share" {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard pathComponents.count >= 2 else {
                importError = "Invalid share link format."
                return false
            }
            
            let type = pathComponents[0] // "habit" or "task"
            let shareId = pathComponents[1]
            
            // Fetch from backend
            do {
                let response = try await CloudFunctionService.shared.getSharedItem(type: type, shareId: shareId)
                guard let itemType = response["type"] as? String,
                      let itemData = response["itemData"] as? [String: Any] else {
                    importError = "Invalid response from server."
                    return false
                }
                
                // Convert to JSON data for parsing
                let jsonData = try JSONSerialization.data(withJSONObject: itemData)
                
                if itemType == "habit" {
                    if let habit = tryParseHabit(from: jsonData) {
                        importableHabit = habit
                        // Store shareId for tracking import later
                        currentShareId = shareId
                        currentShareType = type
                        return true
                    } else {
                        importError = "Could not parse habit from server."
                        return false
                    }
                } else if itemType == "task" {
                    if let task = tryParseTask(from: jsonData) {
                        importableTask = task
                        // Store shareId for tracking import later
                        currentShareId = shareId
                        currentShareType = type
                        return true
                    } else {
                        importError = "Could not parse task from server."
                        return false
                    }
                } else {
                    importError = "Unknown item type: \(itemType)"
                    return false
                }
            } catch {
                importError = "Failed to fetch shared item: \(error.localizedDescription)"
                return false
            }
        }
        
        // Fallback to client-side link parsing (for backward compatibility)
        guard let result = ShareLinkService.shared.parseShareLink(url) else {
            importError = "Invalid share link format."
            return false
        }
        
        switch result.type {
        case .habit:
            if let habit = tryParseHabit(from: result.data) {
                importableHabit = habit
                return true
            } else {
                importError = "Could not parse habit from link."
                return false
            }
        case .task:
            if let task = tryParseTask(from: result.data) {
                importableTask = task
                return true
            } else {
                importError = "Could not parse task from link."
                return false
            }
        }
    }
    
    /// Attempts to parse a habit or task from text (could be from clipboard, paste, or shared content)
    func parseFromText(_ text: String) async -> Bool {
        importableHabit = nil
        importableTask = nil
        importError = nil
        
        // First, try to parse as URL if it looks like a link
        if let url = URL(string: text), url.scheme == "calendo" {
            return await parseFromURL(url)
        }
        
        // Try to extract JSON from text
        guard let jsonString = extractJSONString(from: text) else {
            importError = "No importable data found. Please share a habit or task from the app."
            return false
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            importError = "Could not parse import data."
            return false
        }
        
        // Try to parse as habit first
        if let habit = tryParseHabit(from: jsonData) {
            importableHabit = habit
            return true
        }
        
        // Try to parse as task
        if let task = tryParseTask(from: jsonData) {
            importableTask = task
            return true
        }
        
        importError = "Could not recognize habit or task format."
        return false
    }
    
    /// Parses a habit from JSON data
    private func tryParseHabit(from jsonData: Data) -> ComprehensiveHabit? {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let habit = try decoder.decode(ComprehensiveHabit.self, from: jsonData)
            
            // Create a new habit with fresh ID and reset dates
            return ComprehensiveHabit(
                id: UUID().uuidString,
                name: habit.name,
                goal: habit.goal,
                category: habit.category,
                description: habit.description,
                difficulty: habit.difficulty,
                lowLevelSchedule: habit.lowLevelSchedule,
                highLevelSchedule: habit.highLevelSchedule,
                createdAt: nil, // Will be set when user pushes to calendar
                startDate: nil, // Will be set when user pushes to calendar
                isActive: false // User needs to activate it
            )
        } catch {
            print("❌ [ImportService] Not a habit: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Parses a task from JSON data
    private func tryParseTask(from jsonData: Data) -> UserTask? {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let task = try decoder.decode(UserTask.self, from: jsonData)
            
            // Create a new task with fresh ID and reset dates
            return UserTask(
                id: UUID().uuidString,
                name: task.name,
                goal: task.goal,
                category: task.category,
                description: task.description,
                createdAt: nil, // Will be set when user pushes to calendar
                completedAt: nil,
                isCompleted: false,
                taskSchedule: task.taskSchedule,
                createdBy: nil, // Will be set when user pushes to calendar
                startDate: nil, // Will be set when user pushes to calendar
                isActive: false // User needs to activate it
            )
        } catch {
            print("❌ [ImportService] Not a task: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extracts JSON string from text (handles both code-fenced and raw JSON)
    private func extractJSONString(from text: String) -> String? {
        // Method 1: Look for JSON after "--- Import Data (JSON) ---"
        if let importMarker = text.range(of: "--- Import Data (JSON) ---") {
            let jsonStart = importMarker.upperBound
            let jsonText = String(text[jsonStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidJSON(jsonText) {
                return jsonText
            }
        }
        
        // Method 2: Look for code-fenced JSON
        if let jsonInFence = extractFromCodeFence(text) {
            return jsonInFence
        }
        
        // Method 3: Look for raw JSON object
        if let jsonRaw = extractRawJSON(text) {
            return jsonRaw
        }
        
        return nil
    }
    
    private func extractFromCodeFence(_ text: String) -> String? {
        // Look for ```json or ``` blocks
        let patterns = [
            "```json\\s*\\n([\\s\\S]*?)\\n```",
            "```\\s*\\n([\\s\\S]*?)\\n```"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                let jsonString = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidJSON(jsonString) {
                    return jsonString
                }
            }
        }
        
        return nil
    }
    
    private func extractRawJSON(_ text: String) -> String? {
        // Look for JSON object starting with { and ending with }
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}"),
           startIndex < endIndex {
            let jsonString = String(text[startIndex...endIndex])
            if isValidJSON(jsonString) {
                return jsonString
            }
        }
        
        return nil
    }
    
    private func isValidJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
    
    /// Records the import event for analytics
    func recordImport() async {
        guard let shareId = currentShareId,
              let shareType = currentShareType else {
            return // Not a backend-generated share link
        }
        
        do {
            _ = try await CloudFunctionService.shared.recordShareImport(type: shareType, shareId: shareId)
            print("✅ [ImportService] Recorded import for \(shareType): \(shareId)")
        } catch {
            print("❌ [ImportService] Failed to record import: \(error.localizedDescription)")
            // Don't fail the import if tracking fails
        }
    }
    
    /// Clears the import state
    func clearImport() {
        importableHabit = nil
        importableTask = nil
        importError = nil
        currentShareId = nil
        currentShareType = nil
    }
}

