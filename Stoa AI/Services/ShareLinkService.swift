import Foundation

/// Service for generating and parsing shareable links for habits and tasks
class ShareLinkService {
    static let shared = ShareLinkService()
    
    private let baseURLScheme = "calendo"
    private let baseURLHost = "import"
    
    private init() {}
    
    // MARK: - Generate Share Links
    
    /// Generates a shareable link for a habit
    func generateHabitLink(_ habit: ComprehensiveHabit) -> URL? {
        do {
            let encoder = JSONEncoder()
            // No formatting = compact JSON (no extra whitespace)
            let jsonData = try encoder.encode(habit)
            let base64String = jsonData.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            
            var components = URLComponents()
            components.scheme = baseURLScheme
            components.host = baseURLHost
            components.path = "/habit"
            components.queryItems = [
                URLQueryItem(name: "data", value: base64String)
            ]
            
            return components.url
        } catch {
            print("❌ [ShareLinkService] Error encoding habit: \(error)")
            return nil
        }
    }
    
    /// Generates a shareable link for a task
    func generateTaskLink(_ task: UserTask) -> URL? {
        do {
            let encoder = JSONEncoder()
            // No formatting = compact JSON (no extra whitespace)
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(task)
            let base64String = jsonData.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            
            var components = URLComponents()
            components.scheme = baseURLScheme
            components.host = baseURLHost
            components.path = "/task"
            components.queryItems = [
                URLQueryItem(name: "data", value: base64String)
            ]
            
            return components.url
        } catch {
            print("❌ [ShareLinkService] Error encoding task: \(error)")
            return nil
        }
    }
    
    // MARK: - Parse Share Links
    
    /// Parses a shareable link and extracts the habit or task data
    func parseShareLink(_ url: URL) -> (type: ShareType, data: Data)? {
        guard url.scheme == baseURLScheme,
              url.host == baseURLHost else {
            return nil
        }
        
        let path = url.path
        guard path == "/habit" || path == "/task" else {
            return nil
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let dataItem = queryItems.first(where: { $0.name == "data" }),
              let base64String = dataItem.value else {
            return nil
        }
        
        // Decode base64 (restore URL-safe characters)
        let restoredBase64 = base64String
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let padding = String(repeating: "=", count: (4 - restoredBase64.count % 4) % 4)
        let paddedBase64 = restoredBase64 + padding
        
        guard let data = Data(base64Encoded: paddedBase64) else {
            return nil
        }
        
        let type: ShareType = path == "/habit" ? .habit : .task
        return (type: type, data: data)
    }
    
    enum ShareType {
        case habit
        case task
    }
    
    // MARK: - Generate Universal Links (for web sharing)
    
    /// Generates a universal link that can be shared via web
    /// This would require a backend endpoint to handle the link
    func generateUniversalLink(for habit: ComprehensiveHabit) -> String {
        // For now, return the custom scheme link as a string
        // In production, this could be a web URL that redirects to the app
        if let url = generateHabitLink(habit) {
            return url.absoluteString
        }
        return ""
    }
    
    func generateUniversalLink(for task: UserTask) -> String {
        // For now, return the custom scheme link as a string
        // In production, this could be a web URL that redirects to the app
        if let url = generateTaskLink(task) {
            return url.absoluteString
        }
        return ""
    }
}

