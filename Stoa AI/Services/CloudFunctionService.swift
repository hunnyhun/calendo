import Foundation
import FirebaseAuth
import FirebaseFunctions

// Rule: Always add debug logs & comment in the code for easier debug and readabilty
// Rule: The fewer lines of code is better

// Custom error enum for better error handling
enum CloudFunctionError: Error {
    case notAuthenticated
    case serverError(String)
    case parseError
    case networkError(Error)
    case rateLimitExceeded(message: String)
    
    var localizedDescription: String {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .serverError(let message):
            return "Server error: \(message)"
        case .parseError:
            return "Failed to parse server response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimitExceeded(let message):
            return message
        }
    }
}

// Streaming response delegate
protocol StreamingResponseDelegate: AnyObject {
    func streamingDidStart(conversationId: String?)
    func streamingDidReceiveChunk(text: String)
    func streamingDidEnd(fullText: String)
    func streamingDidComplete(response: [String: Any])
    func streamingDidFail(error: CloudFunctionError)
}

@Observable class CloudFunctionService: @unchecked Sendable {
    // Service instance
    private var functions: Functions
    
    // MARK: - Singleton
    static let shared = CloudFunctionService()
    
    // Streaming properties
    weak var streamingDelegate: StreamingResponseDelegate?
    private var currentStreamingTask: URLSessionDataTask?
    
    init() {
        // Debug log
        print("🌩️ CloudFunctionService initialized")
        
        // Initialize Firebase Functions with region
        self.functions = Functions.functions(region: "us-central1")
        
        // Debug: Log auth state
        if let user = Auth.auth().currentUser {
            print("🌩️ User authenticated: \(user.uid)")
        } else {
            print("🌩️ No authenticated user")
        }
        
        // Add debug for available functions
        print("🌩️ Using Firebase Functions region: us-central1")
    }
    
    // MARK: - Chat History
    func getChatHistory() async throws -> [[String: Any]] {
        // Debug log
        print("🌩️ Getting chat history")
        
        do {
            // Check authentication
            guard let user = Auth.auth().currentUser else {
                print("🌩️ No authenticated user found")
                throw CloudFunctionError.notAuthenticated
            }
            
            // Debug: Log auth token
            print("🌩️ User ID: \(user.uid)")
            
            // Try to get a token for debugging
            let tokenResult = try await user.getIDTokenResult()
            print("🌩️ User has valid token: \(tokenResult.token.prefix(10))...")
            
            // Call the v2 Cloud Function - ensure exact name match
            let result = try await functions.httpsCallable("getChatHistoryV2").call()
            
            // Parse response
            guard let conversations = result.data as? [[String: Any]] else {
                print("🌩️ Failed to parse chat history response")
                throw CloudFunctionError.parseError
            }
            
            // Debug log
            print("🌩️ Successfully fetched chat history with \(conversations.count) conversations")
            return conversations
        } catch {
            // Handle all other errors
            print("🌩️ Function error detail: \(error)")

            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain { // Use FunctionsErrorDomain constant
                // Check the specific error code
                if let code = FunctionsErrorCode(rawValue: nsError.code) {
                     // Extract the message description provided by the SDK
                     let errorMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? nsError.localizedDescription

                    switch code {
                    case .resourceExhausted:
                         print("🌩️ [getChatHistory] Resource exhausted error detected. Message: \(errorMessage)")
                         // Throw the single rate limit error with the message we received
                         throw CloudFunctionError.rateLimitExceeded(message: errorMessage)

                    case .unauthenticated:
                         print("🌩️ [getChatHistory] Unauthenticated error from Functions")
                         throw CloudFunctionError.notAuthenticated // Map to your custom error

                    // Handle other specific codes if necessary
                    // case .invalidArgument:
                    //     print("🌩️ [getChatHistory] Invalid argument error: \(errorMessage)")
                    //     throw CloudFunctionError.serverError("Invalid request data: \(errorMessage)")

                    default:
                        // Handle other Firebase function errors
                        print("🌩️ [getChatHistory] Firebase Functions server error (\(code.rawValue)): \(errorMessage)")
                        throw CloudFunctionError.serverError(errorMessage)
                    }
                } else {
                    // Fallback for unknown Firebase function errors
                     print("🌩️ [getChatHistory] Unknown Firebase Functions error code: \(nsError.code)")
                    throw CloudFunctionError.serverError(nsError.localizedDescription)
                }
            } else {
                // Handle non-Firebase network errors
                 print("🌩️ [getChatHistory] Network error: \(error.localizedDescription)")
                throw CloudFunctionError.networkError(error)
            }
        }
    }
    
    // MARK: - Get Habits
    func getHabits() async throws -> [[String: Any]] {
        // Debug log
        print("🌩️ Getting habits from backend")
        
        do {
            // Check authentication
            guard let user = Auth.auth().currentUser else {
                print("🌩️ No authenticated user found")
                throw CloudFunctionError.notAuthenticated
            }
            
            // Debug: Log auth token
            print("🌩️ User ID: \(user.uid)")
            
            // Try to get a token for debugging
            let tokenResult = try await user.getIDTokenResult()
            print("🌩️ User has valid token: \(tokenResult.token.prefix(10))...")
            
            // Call the getHabitsV2 Cloud Function
            let result = try await functions.httpsCallable("getHabitsV2").call()
            
            // Extract the data from the result
            guard let habits = result.data as? [[String: Any]] else {
                print("🌩️ Invalid response format from getHabitsV2")
                throw CloudFunctionError.parseError
            }
            
            print("🌩️ Successfully fetched habits with \(habits.count) habits")
            return habits
        } catch {
            // Handle all other errors
            print("🌩️ Function error detail: \(error)")

            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain {
                // Check the specific error code
                if let code = FunctionsErrorCode(rawValue: nsError.code) {
                     // Extract the message description provided by the SDK
                     let errorMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? nsError.localizedDescription

                    switch code {
                    case .resourceExhausted:
                         print("🌩️ [getHabits] Resource exhausted error detected. Message: \(errorMessage)")
                         throw CloudFunctionError.serverError("Service temporarily unavailable: \(errorMessage)")
                    case .unauthenticated:
                         print("🌩️ [getHabits] Authentication error: \(errorMessage)")
                         throw CloudFunctionError.notAuthenticated

                    default:
                        // Handle other Firebase function errors
                        print("🌩️ [getHabits] Firebase Functions server error (\(code.rawValue)): \(errorMessage)")
                        throw CloudFunctionError.serverError(errorMessage)
                    }
                } else {
                    // Fallback for unknown Firebase function errors
                     print("🌩️ [getHabits] Unknown Firebase Functions error code: \(nsError.code)")
                    throw CloudFunctionError.serverError(nsError.localizedDescription)
                }
            } else {
                // Handle non-Firebase network errors
                 print("🌩️ [getHabits] Network error: \(error.localizedDescription)")
                throw CloudFunctionError.networkError(error)
            }
        }
    }
    
    func getTasks() async throws -> [[String: Any]] {
        // Debug log
        print("🌩️ Getting tasks from backend")
        
        do {
            // Check authentication
            guard let user = Auth.auth().currentUser else {
                print("🌩️ No authenticated user found")
                throw CloudFunctionError.notAuthenticated
            }
            
            // Debug: Log auth token
            print("🌩️ User ID: \(user.uid)")
            
            // Try to get a token for debugging
            let tokenResult = try await user.getIDTokenResult()
            print("🌩️ User has valid token: \(tokenResult.token.prefix(10))...")
            
            // Call the getTasksV2 Cloud Function
            let result = try await functions.httpsCallable("getTasksV2").call()
            
            // Extract the data from the result
            guard let tasks = result.data as? [[String: Any]] else {
                print("🌩️ Invalid response format from getTasksV2")
                throw CloudFunctionError.parseError
            }
            
            print("🌩️ Successfully fetched tasks with \(tasks.count) tasks")
            return tasks
        } catch {
            // Handle all other errors
            print("🌩️ Function error detail: \(error)")

            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain {
                // Check the specific error code
                if let code = FunctionsErrorCode(rawValue: nsError.code) {
                     // Extract the message description provided by the SDK
                     let errorMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? nsError.localizedDescription

                    switch code {
                    case .resourceExhausted:
                         print("🌩️ [getTasks] Resource exhausted error detected. Message: \(errorMessage)")
                         throw CloudFunctionError.serverError("Service temporarily unavailable: \(errorMessage)")
                    case .unauthenticated:
                         print("🌩️ [getTasks] Authentication error: \(errorMessage)")
                         throw CloudFunctionError.notAuthenticated

                    default:
                        // Handle other Firebase function errors
                        print("🌩️ [getTasks] Firebase function error: \(code.rawValue) - \(errorMessage)")
                        throw CloudFunctionError.serverError("Function error: \(errorMessage)")
                    }
                } else {
                    // Handle unknown error codes
                    print("🌩️ [getTasks] Unknown Firebase function error: \(nsError.code) - \(nsError.localizedDescription)")
                    throw CloudFunctionError.serverError("Unknown function error: \(nsError.localizedDescription)")
                }
            } else {
                // Handle non-Firebase errors (network, etc.)
                print("🌩️ [getTasks] Non-Firebase error: \(error)")
                throw CloudFunctionError.networkError(error)
            }
        }
    }
    
    // MARK: - Send Message (Non-streaming - backward compatibility)
    func sendMessage(message: String, conversationId: String? = nil) async throws -> [String: Any] {
        return try await sendMessageWithStreaming(message: message, conversationId: conversationId, enableStreaming: false)
    }
    
    // MARK: - Send Message with V3 (LangChain) Support
    func sendMessageV3(message: String, conversationId: String? = nil, enableStreaming: Bool = false, chatMode: String = "task", useFunctionCalling: Bool = false) async throws -> [String: Any] {
        // Debug log
        print("🌩️ Sending message via V3 (LangChain) (streaming: \(enableStreaming)): \(message)")
        
        // Check authentication
        guard let user = Auth.auth().currentUser else {
            print("🌩️ No authenticated user found")
            throw CloudFunctionError.notAuthenticated
        }
        
        // Debug: Log auth token and user info
        print("🌩️ User ID: \(user.uid)")
        
        // Get auth token
        let tokenResult = try await user.getIDTokenResult()
        print("🌩️ User has valid token: \(tokenResult.token.prefix(10))...")
        
        // Prepare request data
        var requestData: [String: Any] = [
            "message": message,
            "stream": enableStreaming,
            "chatMode": chatMode,
            "useFunctionCalling": useFunctionCalling
        ]
        
        // Add conversation ID if provided
        if let conversationId = conversationId {
            requestData["conversationId"] = conversationId
            print("🌩️ Using conversation ID: \(conversationId)")
        }
        
        print("🌩️ Chat mode: \(chatMode), Function calling: \(useFunctionCalling)")
        
        // Debug: Log request data
        print("🌩️ Request data: \(requestData)")
        
        if enableStreaming {
            return try await performStreamingRequestV3(requestData: requestData, authToken: tokenResult.token)
        } else {
            return try await performRegularRequestV3(requestData: requestData, authToken: tokenResult.token)
        }
    }
    
    // MARK: - Send Message with Streaming Support
    func sendMessageWithStreaming(message: String, conversationId: String? = nil, enableStreaming: Bool = false, chatMode: String = "task") async throws -> [String: Any] {
        // Debug log
        print("🌩️ Sending message (streaming: \(enableStreaming)): \(message)")
        
        // Check authentication
        guard let user = Auth.auth().currentUser else {
            print("🌩️ No authenticated user found")
            throw CloudFunctionError.notAuthenticated
        }
        
        // Debug: Log auth token and user info
        print("🌩️ User ID: \(user.uid)")
        
        // Get auth token
        let tokenResult = try await user.getIDTokenResult()
        print("🌩️ User has valid token: \(tokenResult.token.prefix(10))...")
        
        // Prepare request data
        var requestData: [String: Any] = [
            "message": message,
            "stream": enableStreaming,
            "chatMode": chatMode
        ]
        
        // Add conversation ID if provided
        if let conversationId = conversationId {
            requestData["conversationId"] = conversationId
            print("🌩️ Using conversation ID: \(conversationId)")
        }
        
        print("🌩️ Chat mode: \(chatMode)")
        
        // Debug: Log request data
        print("🌩️ Request data: \(requestData)")
        
        if enableStreaming {
            return try await performStreamingRequest(requestData: requestData, authToken: tokenResult.token)
        } else {
            return try await performRegularRequest(requestData: requestData, authToken: tokenResult.token)
        }
    }
    
    // MARK: - Regular HTTP Request V3
    private func performRegularRequestV3(requestData: [String: Any], authToken: String) async throws -> [String: Any] {
        let url = URL(string: "https://us-central1-\(getProjectId()).cloudfunctions.net/processChatMessageV3")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        } catch {
            print("🌩️ Failed to serialize request data")
            throw CloudFunctionError.parseError
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudFunctionError.networkError(NSError(domain: "InvalidResponse", code: 0))
            }
            
            print("🌩️ V3 Response status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 429 {
                // Handle rate limiting
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    throw CloudFunctionError.rateLimitExceeded(message: errorMessage)
                } else {
                    throw CloudFunctionError.rateLimitExceeded(message: "Rate limit exceeded")
                }
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    throw CloudFunctionError.serverError(errorMessage)
                } else {
                    throw CloudFunctionError.serverError("HTTP \(httpResponse.statusCode)")
                }
            }
            
            guard let responseData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🌩️ Failed to parse V3 response")
                throw CloudFunctionError.parseError
            }
            
            print("🌩️ Successfully received V3 response: \(responseData)")
            
            // V3 response format: { response, conversationId, intent, confidence, json, needsClarification }
            // Map to expected format for compatibility
            var mappedResponse: [String: Any] = responseData
            
            // If there's a 'response' field, also add it as 'message' for backward compatibility
            if let responseText = responseData["response"] as? String {
                mappedResponse["message"] = responseText
            }
            
            return mappedResponse
            
        } catch {
            print("🌩️ Network error: \(error.localizedDescription)")
            throw CloudFunctionError.networkError(error)
        }
    }
    
    // MARK: - Streaming HTTP Request V3
    private func performStreamingRequestV3(requestData: [String: Any], authToken: String) async throws -> [String: Any] {
        let url = URL(string: "https://us-central1-\(getProjectId()).cloudfunctions.net/processChatMessageV3")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        } catch {
            print("🌩️ Failed to serialize request data")
            throw CloudFunctionError.parseError
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    print("🌩️ V3 Streaming request failed: \(error.localizedDescription)")
                    continuation.resume(throwing: CloudFunctionError.networkError(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: CloudFunctionError.networkError(NSError(domain: "InvalidResponse", code: 0)))
                    return
                }
                
                print("🌩️ V3 Streaming response status code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 429 {
                    continuation.resume(throwing: CloudFunctionError.rateLimitExceeded(message: "Rate limit exceeded"))
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    continuation.resume(throwing: CloudFunctionError.serverError("HTTP \(httpResponse.statusCode)"))
                    return
                }
                
                guard let data = data else {
                    continuation.resume(throwing: CloudFunctionError.parseError)
                    return
                }
                
                // Process streaming data (same format as V2)
                self?.processStreamingData(data, continuation: continuation)
            }
            
            currentStreamingTask = task
            task.resume()
        }
    }
    
    // MARK: - Regular HTTP Request
    private func performRegularRequest(requestData: [String: Any], authToken: String) async throws -> [String: Any] {
        let url = URL(string: "https://us-central1-\(getProjectId()).cloudfunctions.net/processChatMessageV2")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        } catch {
            print("🌩️ Failed to serialize request data")
            throw CloudFunctionError.parseError
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudFunctionError.networkError(NSError(domain: "InvalidResponse", code: 0))
            }
            
            print("🌩️ Response status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 429 {
                // Handle rate limiting
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    throw CloudFunctionError.rateLimitExceeded(message: errorMessage)
                } else {
                    throw CloudFunctionError.rateLimitExceeded(message: "Rate limit exceeded")
                }
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    throw CloudFunctionError.serverError(errorMessage)
                } else {
                    throw CloudFunctionError.serverError("HTTP \(httpResponse.statusCode)")
                }
            }
            
            guard let responseData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🌩️ Failed to parse response")
                throw CloudFunctionError.parseError
            }
            
            print("🌩️ Successfully received response: \(responseData)")
            return responseData
            
        } catch {
            print("🌩️ Network error: \(error.localizedDescription)")
            throw CloudFunctionError.networkError(error)
        }
    }
    
    // MARK: - Streaming HTTP Request
    private func performStreamingRequest(requestData: [String: Any], authToken: String) async throws -> [String: Any] {
        let url = URL(string: "https://us-central1-\(getProjectId()).cloudfunctions.net/processChatMessageV2")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        } catch {
            print("🌩️ Failed to serialize request data")
            throw CloudFunctionError.parseError
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    print("🌩️ Streaming request failed: \(error.localizedDescription)")
                    continuation.resume(throwing: CloudFunctionError.networkError(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: CloudFunctionError.networkError(NSError(domain: "InvalidResponse", code: 0)))
                    return
                }
                
                print("🌩️ Streaming response status code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 429 {
                    continuation.resume(throwing: CloudFunctionError.rateLimitExceeded(message: "Rate limit exceeded"))
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    continuation.resume(throwing: CloudFunctionError.serverError("HTTP \(httpResponse.statusCode)"))
                    return
                }
                
                guard let data = data else {
                    continuation.resume(throwing: CloudFunctionError.parseError)
                    return
                }
                
                // Process streaming data
                self?.processStreamingData(data, continuation: continuation)
            }
            
            currentStreamingTask = task
            task.resume()
        }
    }
    
    // MARK: - Process Streaming Data
    private func processStreamingData(_ data: Data, continuation: CheckedContinuation<[String: Any], Error>) {
        let dataString = String(data: data, encoding: .utf8) ?? ""
        print("🌩️ Received streaming data: \(dataString)")
        
        let lines = dataString.components(separatedBy: .newlines)
        var continuationResolved = false
        
        for line in lines {
            // Parse SSE format: "data: {json}"
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6)) // Remove "data: " prefix
                print("🌩️ Processing SSE line: \(jsonString)")
                
                guard let jsonData = jsonString.data(using: .utf8),
                      let eventData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let type = eventData["type"] as? String,
                      let eventPayload = eventData["data"] as? [String: Any] else { // Renamed to eventPayload for clarity
                    print("🌩️ Failed to parse SSE line: \(line)")
                    continue
                }
                
                print("🌩️ Parsed event - type: \(type), data: \(eventPayload)")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    switch type {
                    case "start":
                        let conversationId = eventPayload["conversationId"] as? String
                        print("🌩️ Streaming started with conversationId: \(conversationId ?? "nil")")
                        self.streamingDelegate?.streamingDidStart(conversationId: conversationId)
                        
                    case "chunk":
                        if let textChunk = eventPayload["text"] as? String {
                            print("🌩️ Received chunk: '\(textChunk)'")
                            // Directly send the chunk to the delegate
                            self.streamingDelegate?.streamingDidReceiveChunk(text: textChunk)
                        }
                        
                    case "end":
                        if let fullText = eventPayload["fullText"] as? String {
                            print("🌩️ Streaming ended with full text length: \(fullText.count)")
                            self.streamingDelegate?.streamingDidEnd(fullText: fullText)
                        }
                        
                    case "complete":
                        print("🌩️ Streaming completed")
                        self.streamingDelegate?.streamingDidComplete(response: eventPayload)
                        
                        if !continuationResolved {
                            print("🌩️ Resolving continuation with final response")
                            continuation.resume(returning: eventPayload)
                            continuationResolved = true
                        } else {
                            print("🌩️ Warning: Continuation already resolved, skipping")
                        }
                        
                    case "error":
                        if let message = eventPayload["message"] as? String {
                            print("🌩️ Streaming error: \(message)")
                            
                            // Check if this is a rate limit error
                            let error: CloudFunctionError
                            if message.contains("limit") || message.contains("exceeded") {
                                error = CloudFunctionError.rateLimitExceeded(message: message)
                            } else {
                                error = CloudFunctionError.serverError(message)
                            }
                            
                            self.streamingDelegate?.streamingDidFail(error: error)
                            if !continuationResolved {
                                continuation.resume(throwing: error)
                                continuationResolved = true
                            }
                        }
                        
                    default:
                        print("🌩️ Unknown streaming event type: \(type)")
                    }
                }
            }
        }
    }
    
    // MARK: - Cancel Streaming
    func cancelStreaming() {
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        print("🌩️ Streaming request cancelled")
    }
    
    // MARK: - Helper Methods
    private func getProjectId() -> String {
        // Get project ID from Firebase configuration
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let projectId = plist["PROJECT_ID"] as? String {
            return projectId
        }
        
        // Fallback - you should replace this with your actual project ID if the above doesn't work
        return "stoa-ai-hh" // Replace with your actual Firebase project ID
    }
    
    // MARK: - Delete Account
    func deleteAccountAndData() async throws {
        // Debug log
        print("🌩️ Deleting account and data")
        
        do {
            // Check authentication
            guard let user = Auth.auth().currentUser else {
                print("🌩️ No authenticated user found for deletion")
                throw CloudFunctionError.notAuthenticated
            }
            
            // Debug: Log user ID being deleted
            print("🌩️ Requesting deletion for User ID: \(user.uid)")
            
            // Try to get a token for debugging (optional, but good practice)
            let tokenResult = try await user.getIDTokenResult()
            print("🌩️ User has valid token for deletion request: \(tokenResult.token.prefix(10))...")
            
            // Call the Cloud Function - ensure exact name match
            // No parameters needed for this call
            let result = try await functions.httpsCallable("deleteAccountAndData").call()
            
            // Parse response data - expecting { success: true }
            guard let responseData = result.data as? [String: Any], responseData["success"] as? Bool == true else {
                // Check if there's an error message in the response (though the function throws HttpsError on failure)
                let message = (result.data as? [String: Any])?["message"] as? String ?? "Unknown error during deletion."
                print("🌩️ Failed to confirm successful deletion from backend: \(result.data)")
                throw CloudFunctionError.serverError(message)
            }
            
            // Debug log on success from cloud function
            print("🌩️ Successfully deleted account data via cloud function for user \(user.uid)")
            
        } catch let error as CloudFunctionError {
            // Re-throw our custom errors
            print("🌩️ Error deleting account: \(error.localizedDescription)")
            throw error
        } catch {
            // Handle all other errors
            print("🌩️ Function error detail during deletion: \(error)")
            
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain { // Check if it's a Functions error
                if let code = FunctionsErrorCode(rawValue: nsError.code) {
                    switch code {
                    case .unauthenticated:
                        print("🌩️ Unauthenticated error from Functions during deletion")
                        throw CloudFunctionError.notAuthenticated
                    // Add other specific codes if needed (e.g., internal, unavailable)
                    default:
                        let message = (nsError.userInfo[FunctionsErrorDetailsKey] as? String) ?? nsError.localizedDescription
                        print("🌩️ Firebase Functions server error during deletion: \(message)")
                        throw CloudFunctionError.serverError(message)
                    }
                } else {
                    print("🌩️ Unknown Firebase Functions error code during deletion: \(nsError.code)")
                    throw CloudFunctionError.serverError(nsError.localizedDescription)
                }
            } else {
                // Handle non-Firebase network errors
                print("🌩️ Network error during deletion: \(error.localizedDescription)")
                throw CloudFunctionError.networkError(error)
            }
        }
    }
    
    // MARK: - Update User Profile
    func updateUserProfile(_ profile: [String: Any]) async throws {
        // Debug log
        print("🌩️ Updating user profile via callable function")
        
        // Ensure auth
        guard Auth.auth().currentUser != nil else {
            throw CloudFunctionError.notAuthenticated
        }
        
        do {
            let result = try await functions.httpsCallable("updateUserProfile").call(profile)
            if let response = result.data as? [String: Any], (response["success"] as? Bool) == true {
                print("🌩️ Profile update success")
            } else {
                print("🌩️ Unexpected response from updateUserProfile: \(result.data)")
            }
        } catch {
            print("🌩️ updateUserProfile failed: \(error.localizedDescription)")
            throw CloudFunctionError.serverError(error.localizedDescription)
        }
    }
    
    // MARK: - Share Links
    func createShareLink(type: String, itemId: String) async throws -> [String: Any] {
        print("🌩️ Creating share link for \(type): \(itemId)")
        
        guard Auth.auth().currentUser != nil else {
            throw CloudFunctionError.notAuthenticated
        }
        
        do {
            let result = try await functions.httpsCallable("createShareLink").call([
                "type": type,
                "itemId": itemId
            ])
            
            guard let response = result.data as? [String: Any] else {
                throw CloudFunctionError.parseError
            }
            
            print("🌩️ Successfully created share link: \(response["shareUrl"] ?? "unknown")")
            return response
        } catch {
            print("🌩️ createShareLink failed: \(error.localizedDescription)")
            throw CloudFunctionError.serverError(error.localizedDescription)
        }
    }
    
    func getSharedItem(type: String, shareId: String) async throws -> [String: Any] {
        print("🌩️ Getting shared item: \(type)/\(shareId)")
        
        do {
            let result = try await functions.httpsCallable("getSharedItem").call([
                "type": type,
                "shareId": shareId
            ])
            
            guard let response = result.data as? [String: Any] else {
                throw CloudFunctionError.parseError
            }
            
            print("🌩️ Successfully retrieved shared item")
            return response
        } catch {
            print("🌩️ getSharedItem failed: \(error.localizedDescription)")
            throw CloudFunctionError.serverError(error.localizedDescription)
        }
    }
    
    func recordShareImport(type: String, shareId: String) async throws -> [String: Any] {
        print("🌩️ Recording share import: \(type)/\(shareId)")
        
        guard Auth.auth().currentUser != nil else {
            throw CloudFunctionError.notAuthenticated
        }
        
        do {
            let result = try await functions.httpsCallable("recordShareImport").call([
                "type": type,
                "shareId": shareId
            ])
            
            guard let response = result.data as? [String: Any] else {
                throw CloudFunctionError.parseError
            }
            
            print("🌩️ Successfully recorded share import")
            return response
        } catch {
            print("🌩️ recordShareImport failed: \(error.localizedDescription)")
            throw CloudFunctionError.serverError(error.localizedDescription)
        }
    }
} 
