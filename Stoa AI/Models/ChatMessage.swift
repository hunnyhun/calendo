import Foundation

// MARK: - Message Type
enum MessageType {
    case user
    case ai
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: String
    var text: String  // Full message text (includes JSON for history reloading)
    let isUser: Bool
    let timestamp: Date
    var detectedHabitSuggestion: ComprehensiveHabit?
    var detectedTaskSuggestion: UserTask?
    var cleanedText: String? // Text with habit/task JSON removed for display
    
    // Computed property for debugging
    var debugDescription: String {
        return "Message(id: \(id), isUser: \(isUser), text: \(text.prefix(20))..., timestamp: \(timestamp), hasHabit: \(detectedHabitSuggestion != nil), hasTask: \(detectedTaskSuggestion != nil))"
    }
    
    // Get the text to display (cleaned if habit was detected)
    var displayText: String {
        return cleanedText ?? text
    }
    
    // Initialize with basic properties
    init(id: String, text: String, isUser: Bool, timestamp: Date) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
        self.detectedHabitSuggestion = nil
        self.cleanedText = nil
    }
    
    // For Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // For Equatable
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id
    }
    
    // For JSON conversion
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "text": text,
            "isUser": isUser,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }
}

// MARK: - Chat History
struct ChatHistory: Identifiable, Codable {
    let id: String
    let title: String
    let timestamp: Date
    let messages: [ChatMessage]
    var mode: ChatMode?
    
    // Computed property for debugging
    var debugDescription: String {
        return "ChatHistory(id: \(id), title: \(title), messages: \(messages.count))"
    }
    
    // Computed property for last message
    var lastMessage: String {
        return messages.last?.text.prefix(30).appending(messages.last?.text.count ?? 0 > 30 ? "..." : "") ?? "No messages"
    }
    
    // For JSON conversion (manual dictionary for Firestore writes)
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "timestamp": timestamp.timeIntervalSince1970,
            "messages": messages.map { $0.toDictionary() }
        ]
        if let mode = mode?.rawValue {
            dict["mode"] = mode
        }
        return dict
    }

} 
