import Foundation
import RevenueCat

// Debug log
import Firebase
import FirebaseAuth
import FirebaseFunctions // For FunctionsErrorCode

// Chat history date section for UI grouping
enum ChatHistorySection: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case lastWeek = "Last Week"
    case earlier = "Earlier"
    
    var id: String { self.rawValue }
    
    // Add a computed property to return the localized string
    var localizedTitle: String {
        // Use the rawValue as the key for localization
        return self.rawValue.localized
    }
}

// Conversation with section info
struct SectionedChatHistory {
    let section: ChatHistorySection
    var conversations: [ChatHistory]
}

@Observable final class ChatViewModel: StreamingResponseDelegate {
    // MARK: - Properties
    private let cloudService: CloudFunctionService
    var messages: [ChatMessage] = []
    var chatHistory: [ChatHistory] = []
    var sectionedHistory: [SectionedChatHistory] = []
    var isLoading = false
    var isLoadingHistory = false
    var error: String?
    let userStatusManager = UserStatusManager.shared
    var currentConversation: ChatHistory?
    private var hasUnsavedChanges = false
    private var refreshTask: Task<Void, Never>?
    private var conversationSaveTask: Task<Void, Never>?
    private var currentConversationId: String = ""
    var isRateLimited = false
    private var lastLoadTime: Date?
    private let loadThrottleInterval: TimeInterval = 3.0 // seconds
    private var observerSetup = false
    var showAnonymousLimitPrompt = false
    
    // MARK: - Chat Mode Properties
    var currentChatMode: ChatMode = .task
    var showingHabitModeRestriction = false
    
    // MARK: - Chat Mode Functions
    
    func switchChatMode(to mode: ChatMode) {
        // Check if user can access habit mode
        if mode == .habit && !canAccessHabitMode() {
            showingHabitModeRestriction = true
            return
        }
        
        currentChatMode = mode
        
        // Start a new conversation when switching modes
        startNewChat()
        
        print("🔄 [ChatViewModel] Switched to \(mode.displayName) mode")
    }
    
    private func canAccessHabitMode() -> Bool {
        return Auth.auth().currentUser != nil
    }
    
    
    // MARK: - Alert Properties for Popups
    var showAnonymousLimitAlert = false
    var showPremiumLimitAlert = false
    var anonymousLimitAlertMessage = ""
    var premiumLimitAlertMessage = ""
    
    // Streaming properties
    var isStreaming = false
    var currentStreamingMessageId: String?
    
    // MARK: - Init
    init(cloudService: CloudFunctionService = CloudFunctionService()) {
        self.cloudService = cloudService
        
        // Generate initial conversation ID with timestamp for better uniqueness
        let timestamp = ISO8601DateFormatter().string(from: Date())
        self.currentConversationId = "\(timestamp)-\(UUID().uuidString.prefix(8))"
        
        print("[Chat] ViewModel initialized with conversation ID: \(currentConversationId)")
        
        // Set up observer for user state changes
        setupSubscriptionObserver()
        // Listen for requests to switch to Habit mode
        NotificationCenter.default.addObserver(forName: Notification.Name("SwitchToHabitMode"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if self.currentChatMode != .habit {
                self.switchChatMode(to: .habit)
            }
        }
    }
    
    deinit {
        refreshTask?.cancel()
        conversationSaveTask?.cancel()
    }
    
    // MARK: - Chat History Management
    func loadChatHistory() {
        // Throttle frequent calls
        if let lastTime = lastLoadTime,
           Date().timeIntervalSince(lastTime) < loadThrottleInterval {
            return
        }
        
        // Update last load time
        lastLoadTime = Date()
        
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        print("[Chat] Loading chat history")
        refreshTask = Task {
            do {
                // Show loading state immediately
                await MainActor.run {
                    self.isLoadingHistory = true
                    self.error = nil
                }
                
                // Load history using cloud functions
                let historyData = try await cloudService.getChatHistory()
                
                // Parse the history data into ChatHistory objects
                var history: [ChatHistory] = []
                for historyItem in historyData {
                    if let id = historyItem["id"] as? String {
                        // Try to get messages from the response
                        if let messagesData = historyItem["messages"] as? [[String: Any]] {
                            
                            // Extract title from first user message or use default
                            let title = historyItem["title"] as? String ?? "Conversation"
                            
                            // Get timestamp - enhanced handling for Firestore timestamp formats
                            let timestamp: TimeInterval
                            
                            // Try multiple formats that might come from Firebase
                            if let ts = historyItem["timestamp"] as? TimeInterval {
                                timestamp = ts
                            } else if let ts = historyItem["timestamp"] as? Double {
                                timestamp = ts
                            } else if let lastUpdated = historyItem["lastUpdated"] as? [String: Any],
                                  let seconds = lastUpdated["_seconds"] as? TimeInterval {
                                timestamp = seconds
                            } else if let lastUpdated = historyItem["lastUpdated"] as? [String: Any],
                                  let seconds = lastUpdated["seconds"] as? TimeInterval {
                                timestamp = seconds
                            } else if let lastUpdatedStr = historyItem["lastUpdated"] as? String,
                                  let date = ISO8601DateFormatter().date(from: lastUpdatedStr) {
                                timestamp = date.timeIntervalSince1970
                            } else {
                                // Default to current time
                                timestamp = Date().timeIntervalSince1970
                            }
                            
                            // Parse messages
                            var messages: [ChatMessage] = []
                            for messageItem in messagesData {
                                // Extract message data based on Firebase format
                                if let content = messageItem["content"] as? String,
                                   let role = messageItem["role"] as? String {
                                    
                                    // Get timestamp, defaulting to current if not available
                                    let msgTimestamp: Date
                                    if let ts = messageItem["timestamp"] as? String {
                                        msgTimestamp = ISO8601DateFormatter().date(from: ts) ?? Date()
                                    } else {
                                        msgTimestamp = Date()
                                    }
                                    
                                    // Create message with Firebase format mapping
                                    let message = ChatMessage(
                                        id: messageItem["id"] as? String ?? UUID().uuidString,
                                        text: content,
                                        isUser: role == "user",
                                        timestamp: msgTimestamp
                                    )
                                    messages.append(message)
                                }
                            }
                            
                            // Create chat history object with proper timestamp
                            if !messages.isEmpty {
                                // Create Date from timestamp
                                let date = Date(timeIntervalSince1970: timestamp)
                                
                            // Parse mode if provided by backend
                            let modeRaw = historyItem["chatMode"] as? String
                            let parsedMode = modeRaw.flatMap { ChatMode(rawValue: $0) }
                                
                                let chatHistory = ChatHistory(
                                    id: id,
                                    title: title,
                                    timestamp: date,
                                    messages: messages,
                                    mode: parsedMode
                                )
                                history.append(chatHistory)
                            }
                        }
                    }
                }
                
                print("[Chat] Parsed \(history.count) conversations")
                
                // Check if task was cancelled
                if Task.isCancelled { return }
                
                // Create a local copy to avoid reference capture issues
                let localHistory = history
                
                // Group conversations by date sections
                let groupedHistory = createSectionedHistory(localHistory)
                
                await MainActor.run {
                    self.isLoadingHistory = false
                    self.chatHistory = localHistory
                    self.sectionedHistory = groupedHistory
                    
                    // Try to match current messages with a conversation if needed
                    matchCurrentMessagesToConversation(localHistory)
                    
                    // Cache the history for faster subsequent loads
                    Task {
                        await cacheHistory(localHistory)
                    }
                }
            } catch {
                print("[Chat] Error loading chat history: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.isLoadingHistory = false
                        self.error = "Failed to load chat history: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // Group conversations by date section
    private func createSectionedHistory(_ conversations: [ChatHistory]) -> [SectionedChatHistory] {
        // Get reference dates
        let now = Date()
        
        // Create calendar with explicit timezone to avoid time shift issues
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        
        // Create empty sectioned data
        var sections: [ChatHistorySection: [ChatHistory]] = [
            .today: [],
            .yesterday: [],
            .lastWeek: [],
            .earlier: []
        ]
        
        // Categorize each conversation
        for conversation in conversations {
            let date = conversation.timestamp
            let isToday = calendar.isDateInToday(date)
            let isYesterday = calendar.isDateInYesterday(date)
            
            // Check which section this conversation belongs to
            if isToday {
                sections[.today]?.append(conversation)
            } else if isYesterday {
                sections[.yesterday]?.append(conversation)
            } else if date >= lastWeek && date < yesterday {
                sections[.lastWeek]?.append(conversation)
            } else {
                sections[.earlier]?.append(conversation)
            }
        }
        
        // Sort conversations within each section - newest first
        for section in ChatHistorySection.allCases {
            sections[section]?.sort { $0.timestamp > $1.timestamp }
        }
        
        // Convert to array format and remove empty sections
        return ChatHistorySection.allCases
            .map { section in
                SectionedChatHistory(
                    section: section,
                    conversations: sections[section] ?? []
                )
            }
            .filter { !$0.conversations.isEmpty }
    }
    
    // Update sections after adding a new conversation
    private func updateSections() {
        sectionedHistory = createSectionedHistory(chatHistory)
    }
    
    // Subscribe to subscription changes
    private func setupSubscriptionObserver() {
        // Prevent multiple registrations
        guard !observerSetup else { return }
        observerSetup = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserStateChange),
            name: Notification.Name("UserStateChanged"),
            object: nil
        )
    }
    
    @objc private func handleUserStateChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            print("ERROR: [Chat] Invalid user state change notification data")
            return
        }
        
        if let authStatus = userInfo["authStatus"] as? String,
           let isAnonymous = userInfo["isAnonymous"] as? Bool {

            print("[Chat] Handling user state change: Auth=\(authStatus), Anonymous=\(isAnonymous)")

            if authStatus == "authenticated" && !isAnonymous {
                // User is fully authenticated (not anonymous)
                print("[Chat] User is fully authenticated. Clearing state and loading history.")
                self.messages = [] // Clear the current chat window
                self.showAnonymousLimitPrompt = false // Reset the prompt flag
                self.isRateLimited = false // Also reset premium limit flag
                self.error = nil // Clear any lingering errors
                self.currentConversation = nil // Reset current conversation reference
                
                // Clear alert properties
                self.showAnonymousLimitAlert = false
                self.showPremiumLimitAlert = false
                self.anonymousLimitAlertMessage = ""
                self.premiumLimitAlertMessage = ""
                
                 // Generate a new conversation ID for the newly logged-in user
                let timestamp = ISO8601DateFormatter().string(from: Date())
                self.currentConversationId = "\(timestamp)-\(UUID().uuidString.prefix(8))"
                print("[Chat] Generated new conversation ID for logged-in user: \(self.currentConversationId)")

                // Load history (existing logic)
                loadChatHistory()

                 // Dismissal of AuthView sheet should happen implicitly in ChatView
                 // as showAnonymousLimitPrompt is now false.

            } else if authStatus == "authenticated" && isAnonymous {
                // User is anonymous
                print("[Chat] User is anonymous. Clearing local history.")
                self.chatHistory = []
                self.sectionedHistory = []
                self.isLoadingHistory = false
                
                // Clear any limit-related alerts for anonymous users
                self.showPremiumLimitAlert = false
                self.premiumLimitAlertMessage = ""
                self.showAnonymousLimitAlert = false
                self.anonymousLimitAlertMessage = ""
                self.currentConversation = nil // Reset current conversation if they were viewing one
                // Keep existing conversation ID for anonymous session

            } else {
                // User is unauthenticated
                print("[Chat] User is unauthenticated. Clearing local history and messages.")
                self.chatHistory = []
                self.sectionedHistory = []
                self.isLoadingHistory = false
                self.messages = [] // Clear messages on sign out
                self.showAnonymousLimitPrompt = false // Ensure prompt is hidden
                self.isRateLimited = false
                self.error = nil
                self.currentConversation = nil
                
                // Clear alert properties
                self.showAnonymousLimitAlert = false
                self.showPremiumLimitAlert = false
                self.anonymousLimitAlertMessage = ""
                self.premiumLimitAlertMessage = ""
                
                 // Generate new conversation ID for logged-out state
                let timestamp = ISO8601DateFormatter().string(from: Date())
                 self.currentConversationId = "\(timestamp)-\(UUID().uuidString.prefix(8))"
            }
        } else {
            print("ERROR: [Chat] Invalid user state change notification data")
        }
    }
    
    private func matchCurrentMessagesToConversation(_ history: [ChatHistory]) {
        // Only try to match if we have messages but no current conversation
        if currentConversation == nil && !messages.isEmpty && !history.isEmpty {
            // Get the most recent conversation
            if let mostRecent = history.first {
                // Check if the messages match what we have
                if mostRecent.messages.count >= messages.count {
                    // Check if the last few messages match
                    let recentMessages = Array(mostRecent.messages.suffix(messages.count))
                    let messagesMatch = zip(recentMessages, messages).allSatisfy { recent, current in
                        recent.text == current.text && recent.isUser == current.isUser
                    }
                    
                    if messagesMatch {
                        setCurrentConversation(mostRecent, source: "auto-match")
                    }
                }
            }
        }
    }

    // Infer chat mode from messages by scanning for ai_habit_suggestion or task JSON
    private func inferMode(from messages: [ChatMessage]) -> ChatMode {
        for msg in messages where !msg.isUser {
            if msg.text.contains("\"ai_habit_suggestion\"") || msg.cleanedText != nil || msg.detectedHabitSuggestion != nil {
                return .habit
            }
            if msg.text.contains("\"name\"") && msg.text.contains("\"description\"") && msg.text.contains("\"steps\"") || msg.detectedTaskSuggestion != nil {
                return .task
            }
        }
        return .task
    }
    
    // MARK: - Message Sending
    func sendMessage(_ text: String) async {
        print("[ChatVM] 🚀 Starting to send message: '\(text)'")
        
        // Guard against concurrent requests
        guard !isLoading else {
            print("[ChatVM] ⚠️ Already loading, ignoring new message")
            return
        }
        
        // Set up streaming delegate at the start of message sending
        cloudService.streamingDelegate = self
        
        // Update UI state
        isLoading = true
        isStreaming = true
        setErrorMessage(nil)
        
        print("[ChatVM] ✅ UI state updated, isLoading: \(isLoading), isStreaming: \(isStreaming)")
        
        // Create and add user message
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            text: text,
            isUser: true,
            timestamp: Date()
        )
        messages.append(userMessage)
        hasUnsavedChanges = true
        
        // Don't create placeholder AI message - let streaming handle it
        // We'll show the streaming indicator instead
        
        // Call cloud function and handle response
        do {
            print("[ChatVM] 📡 Making API call with streaming...")
            
            // Make the API call with streaming support (always use streaming now)
            let _ = try await cloudService.sendMessageWithStreaming(
                message: text,
                conversationId: currentConversation?.id,
                enableStreaming: true,  // Always enable streaming
                chatMode: currentChatMode.rawValue
            )
            
            // Don't process responseData here for streaming - it's handled in delegate methods
            print("[ChatVM] ✅ Streaming API call completed successfully")
            
        } catch let error as CloudFunctionError {
            handleChatError(error)
            
            // Remove streaming message if it was added
            if let messageId = currentStreamingMessageId {
                removeMessageWithId(messageId)
            }
        } catch {
            print("[ChatVM] ❌ Error in sendMessage: \(error.localizedDescription)")
            setErrorMessage("Unexpected error: \(error.localizedDescription)")
            
            // Remove streaming message if it was added
            if let messageId = currentStreamingMessageId {
                removeMessageWithId(messageId)
            }
            
            // Reset loading state on error
            isLoading = false
            isStreaming = false
            currentStreamingMessageId = nil
        }
        
        // Don't reset loading states here - let the streaming delegate handle it
    }
    
    // MARK: - StreamingResponseDelegate Methods
    func streamingDidStart(conversationId: String?) {
        print("[Chat] Streaming started")
        
        // Don't use async dispatch - create the message immediately to avoid race condition
            if let conversationId = conversationId {
                self.currentConversationId = conversationId
            }
            
            let aiMessage = ChatMessage(
                id: UUID().uuidString,
                text: "",
                isUser: false,
                timestamp: Date()
            )
            self.currentStreamingMessageId = aiMessage.id
            self.messages.append(aiMessage)
            
            // Simulate typing sound for better UX
            StreamingEffects.simulateTypingSound()
            
            print("[Chat] AI message created with ID: \(aiMessage.id)")
    }
    
    func streamingDidReceiveChunk(text: String) {
        // Ensure we're on main thread for UI updates
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.streamingDidReceiveChunk(text: text)
            }
            return
        }
        
        print("[ChatVM] 📥 Received chunk: '\(text.prefix(50))...' (length: \(text.count))")
        
        guard let messageId = currentStreamingMessageId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else {
            let idText = currentStreamingMessageId ?? "nil"
            print("[ChatVM] ⚠️ Warning: Received chunk '\(text)' but no streaming message found or messageId \(idText) not in messages.")
            return
        }
        
        let currentMessage = messages[index]
        let newFullText = currentMessage.text + text
        
        // Filter out JSON content for display during streaming
        let cleanedText = filterJSONFromStreamingText(newFullText)
        
        var updatedMessage = ChatMessage(
            id: currentMessage.id,
            text: newFullText, // Keep full text for final parsing
            isUser: currentMessage.isUser,
            timestamp: currentMessage.timestamp
        )
        
        // Set cleaned text for display (without JSON)
        updatedMessage.cleanedText = cleanedText
        
        // Preserve any previously detected habit
        updatedMessage.detectedHabitSuggestion = currentMessage.detectedHabitSuggestion
        
        messages[index] = updatedMessage
        
        // Simulate subtle typing sound for each chunk (but throttle it)
        if text.count > 3 { // Only for substantial chunks
            StreamingEffects.simulateTypingSound()
        }
    }
    
    // MARK: - Simple JSON Filtering for Streaming
    private func filterJSONFromStreamingText(_ text: String) -> String {
        // Simple approach: just remove everything after we see JSON starting
        
        // Method 1: Look for code fence (most common)
        if let codeStart = text.range(of: "```") {
            return String(text[..<codeStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Method 2: Look for JSON object start with our key
        if text.contains("ai_habit_suggestion") {
            // Find the opening brace before ai_habit_suggestion
            if let jsonStart = text.range(of: "{") {
                return String(text[..<jsonStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return text
    }
    
    
    func streamingDidEnd(fullText: String) {
        print("[Chat] Streaming ended with full text length: \(fullText.count)")
        // Note: Habit detection moved to streamingDidComplete where the full message with JSON is available
    }
    
    func streamingDidComplete(response: [String: Any]) {
        print("[Chat] Streaming completed")
        
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update conversation ID if provided
            if let newConversationId = response["conversationId"] as? String {
                self.currentConversationId = newConversationId
            }
            
            // Save updated conversation with title from backend
            self.saveConversation(withTitle: response["title"] as? String)
            
            // Check for suggestions in the complete message based on current chat mode
            if let messageId = self.currentStreamingMessageId,
               let index = self.messages.firstIndex(where: { $0.id == messageId }),
               let userId = self.userStatusManager.state.userId,
               let completeMessage = response["message"] as? String {
                
                print("[Chat] Checking for \(self.currentChatMode.displayName.lowercased()) suggestions in complete message (length: \(completeMessage.count))")
                
                // Detect suggestions based on current chat mode
                if self.currentChatMode == .habit {
                    // In habit mode, only check for habit suggestions
                    if let detectedHabit = HabitDetectionService.shared.detectHabitSuggestion(
                        in: completeMessage,
                        messageId: messageId,
                        userId: userId
                    ) {
                        print("✅ [Chat] Detected habit suggestion: \(detectedHabit.name)")
                        
                        // Update the message with detected habit and cleaned text
                        var updatedMessage = self.messages[index]
                        updatedMessage.detectedHabitSuggestion = detectedHabit
                        updatedMessage.cleanedText = HabitDetectionService.shared.cleanTextFromHabitSuggestion(completeMessage)
                        self.messages[index] = updatedMessage
                    } else {
                        print("❌ [Chat] No habit suggestion detected in complete message")
                    }
                } else if self.currentChatMode == .task {
                    // In task mode, only check for task suggestions
                    if let detectedTask = TaskDetectionService.shared.detectTaskSuggestion(
                        in: completeMessage,
                        userId: userId
                    ) {
                        print("✅ [Chat] Detected task suggestion: \(detectedTask.name)")
                        
                        // Update the message with detected task and cleaned text
                        var updatedMessage = self.messages[index]
                        updatedMessage.detectedTaskSuggestion = detectedTask
                        updatedMessage.cleanedText = TaskDetectionService.shared.cleanTextFromTaskSuggestion(completeMessage)
                        self.messages[index] = updatedMessage
                    } else {
                        print("❌ [Chat] No task suggestion detected in complete message")
                    }
                }
            }
            
            // Reset all streaming and loading states
            self.isLoading = false
            self.isStreaming = false
            self.currentStreamingMessageId = nil
            
            print("[Chat] All streaming states reset - isLoading: \(self.isLoading), isStreaming: \(self.isStreaming)")
        }
    }
    
    func streamingDidFail(error: CloudFunctionError) {
        print("[Chat] Streaming failed: \(error.localizedDescription)")
        
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.handleChatError(error)
            
            // Remove the streaming message
            if let messageId = self.currentStreamingMessageId {
                self.removeMessageWithId(messageId)
            }
            
            // Reset all streaming and loading states
            self.isLoading = false
            self.isStreaming = false
            self.currentStreamingMessageId = nil
            
            print("[Chat] All streaming states reset after error - isLoading: \(self.isLoading), isStreaming: \(self.isStreaming)")
        }
    }
    
    // MARK: - Helper Methods
    private func removeMessageWithId(_ messageId: String) {
        messages.removeAll { $0.id == messageId }
    }
    
    private func handleChatError(_ error: CloudFunctionError) {
        switch error {
        case .rateLimitExceeded(let message):
            // Check if user is anonymous or authenticated
            if userStatusManager.state.isAnonymous {
                // Anonymous user - show login popup
                anonymousLimitAlertMessage = message
                showAnonymousLimitAlert = true
                showAnonymousLimitPrompt = false // Clear inline prompt
            } else {
                // Authenticated user - show subscription popup
                premiumLimitAlertMessage = message
                showPremiumLimitAlert = true
                isRateLimited = false // Clear inline rate limit flag
            }
        case .notAuthenticated:
            setErrorMessage("Authentication required")
        case .serverError(let message):
            if message.contains("anonymous") {
                // Anonymous user limit - show login popup
                anonymousLimitAlertMessage = message
                showAnonymousLimitAlert = true
                showAnonymousLimitPrompt = false // Clear inline prompt
            } else if message.contains("free tier") || message.contains("upgrade to premium") {
                // Authenticated free user limit - show subscription popup
                premiumLimitAlertMessage = message
                showPremiumLimitAlert = true
                isRateLimited = false // Clear inline rate limit flag
            } else {
                setErrorMessage(message)
            }
        case .networkError, .parseError:
            setErrorMessage("Network error. Please check your connection.")
        }
    }
    
    // Helper method to set error message
    private func setErrorMessage(_ message: String?) {
        // Assign error message to the property
        self.error = message
        // Also log it for debugging
        if let message = message {
            print("[Chat] Error: \(message)")
        }
        // Ensure anonymous prompt isn't shown for general errors
        // self.showAnonymousLimitPrompt = false // Don't reset here, let the view handle dismissal
    }
    
    // MARK: - Saving Conversation
    private func saveConversation(withTitle title: String? = nil) {
        // Cancel any pending save task
        conversationSaveTask?.cancel()
        
        // Create a new save task
        conversationSaveTask = Task {
            // Use provided title or generate one locally if not available
            let finalTitle = title ?? generateTitle()
            
            // Create a conversation object
            let conversation = ChatHistory(
                id: currentConversationId,
                title: finalTitle,
                timestamp: Date(),
                messages: messages,
                mode: currentChatMode
            )
            
            // If we're updating an existing conversation, replace it
            if let index = chatHistory.firstIndex(where: { $0.id == currentConversationId }) {
                chatHistory[index] = conversation
            } else {
                // Otherwise add it to the beginning
                chatHistory.insert(conversation, at: 0)
            }
            
            // Set as current conversation
            currentConversation = conversation
            
            // Update sections
            updateSections()
            
            // Cache history
            await cacheHistory(chatHistory)
            
            // Reset unsaved flag
            hasUnsavedChanges = false
        }
    }
    
    // MARK: - Load Conversation
    func loadConversation(_ history: ChatHistory) {
        setCurrentConversation(history, source: "user selection")
    }
    
    // Private helper to consolidate conversation loading logic
    private func setCurrentConversation(_ history: ChatHistory, source: String) {
        // Set current conversation
        currentConversation = history
        currentConversationId = history.id
        
        // Process messages for suggestions based on chat mode before setting them
        if history.mode == .habit {
            messages = processMessagesForHabitSuggestions(history.messages)
        } else if history.mode == .task {
            messages = processMessagesForTaskSuggestions(history.messages)
        } else {
            messages = history.messages
        }
        
        // Update chat mode to match the conversation's mode
        if let storedMode = history.mode {
            currentChatMode = storedMode
            print("🔄 [ChatViewModel] Set conversation (\(source)) with \(storedMode.displayName) mode")
        } else {
            // Fallback: infer mode from messages if no stored mode
            currentChatMode = inferMode(from: history.messages)
            print("🔄 [ChatViewModel] Set conversation (\(source)) with inferred \(currentChatMode.displayName) mode")
        }
        
        // Reset state
        isLoading = false
        error = nil
        hasUnsavedChanges = false
    }
    
    // Process messages to detect habit suggestions that weren't processed before
    private func processMessagesForHabitSuggestions(_ messages: [ChatMessage]) -> [ChatMessage] {
        return messages.map { message in
            // Skip user messages and messages that already have habit suggestions
            guard !message.isUser && message.detectedHabitSuggestion == nil else {
                return message
            }
            
            // Try to detect habit suggestion in the message text
            if let detectedHabit = HabitDetectionService.shared.detectHabitSuggestion(
                in: message.text,
                messageId: message.id,
                userId: userStatusManager.state.userId
            ) {
                print("✅ [ChatViewModel] Detected habit suggestion in old message: \(detectedHabit.name)")
                
                // Create updated message with detected habit and cleaned text
                var updatedMessage = message
                updatedMessage.detectedHabitSuggestion = detectedHabit
                updatedMessage.cleanedText = HabitDetectionService.shared.cleanTextFromHabitSuggestion(message.text)
                return updatedMessage
            }
            
            return message
        }
    }
    
    // Process messages to detect task suggestions that weren't processed before
    private func processMessagesForTaskSuggestions(_ messages: [ChatMessage]) -> [ChatMessage] {
        return messages.map { message in
            // Skip user messages and messages that already have task suggestions
            guard !message.isUser && message.detectedTaskSuggestion == nil else {
                return message
            }
            
            // Try to detect task suggestion in the message text
            if let detectedTask = TaskDetectionService.shared.detectTaskSuggestion(
                in: message.text,
                userId: userStatusManager.state.userId
            ) {
                print("✅ [ChatViewModel] Detected task suggestion in old message: \(detectedTask.name)")
                
                // Create updated message with detected task and cleaned text
                var updatedMessage = message
                updatedMessage.detectedTaskSuggestion = detectedTask
                updatedMessage.cleanedText = TaskDetectionService.shared.cleanTextFromTaskSuggestion(message.text)
                return updatedMessage
            }
            
            return message
        }
    }
    
    // Cache history for faster loading
    private func cacheHistory(_ history: [ChatHistory]) async {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(history)
            UserDefaults.standard.set(data, forKey: "cached_chat_history")
        } catch {
            print("[Chat] Failed to cache chat history: \(error.localizedDescription)")
        }
    }
    
    // Load cached history
    private func loadCachedHistory() -> [ChatHistory]? {
        guard let data = UserDefaults.standard.data(forKey: "cached_chat_history") else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let history = try decoder.decode([ChatHistory].self, from: data)
            return history
        } catch {
            print("[Chat] Failed to load cached history: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Helper Methods
    private func generateTitle() -> String {
        // Use the first user message to generate a title
        if let firstUserMessage = messages.first(where: { $0.isUser })?.text {
            // Limit title length and clean up
            let words = firstUserMessage.split(separator: " ")
            if words.count <= 5 {
                return firstUserMessage
            } else {
                return words.prefix(5).joined(separator: " ") + "..."
            }
        }
        
        // Fallback title - now localized
        return "newConversation".localized
    }
    
    // MARK: - Conversation Management
    func clearConversation() {
        // Reset messages
        messages = []
        
        // Generate new conversation ID
        let timestamp = ISO8601DateFormatter().string(from: Date())
        currentConversationId = "\(timestamp)-\(UUID().uuidString.prefix(8))"
        
        // Reset current conversation
        currentConversation = nil
    }
    
    // For backward compatibility
    func startNewChat() {
        clearConversation()
    }
    
    
    // MARK: - Alert Action Methods
    func handleAnonymousLimitLogin() {
        // Clear the alert
        showAnonymousLimitAlert = false
        anonymousLimitAlertMessage = ""
        
        // The login action will be handled by the view showing AuthenticationView
        print("[Chat] Anonymous user requested login due to limit")
    }
    
    func handlePremiumLimitSubscribe() {
        // Clear the alert
        showPremiumLimitAlert = false
        premiumLimitAlertMessage = ""
        
        // The subscription action will be handled by the view showing PaywallView
        print("[Chat] Authenticated user requested subscription due to limit")
    }
    
    func dismissAnonymousLimitAlert() {
        showAnonymousLimitAlert = false
        anonymousLimitAlertMessage = ""
    }
    
    func dismissPremiumLimitAlert() {
        showPremiumLimitAlert = false
        premiumLimitAlertMessage = ""
    }
    
} 


