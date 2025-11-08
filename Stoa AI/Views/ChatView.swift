import SwiftUI
import UserNotifications
// No need to import StoicColumn as it should be part of the same module

// Extension to dismiss keyboard
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        print("DEBUG: Keyboard dismissed via UIApplication extension")
    }
}

struct ChatView: View {
    // MARK: - Properties
    @Bindable var viewModel: ChatViewModel // Use @Bindable for @Observable view models
    @Environment(\.colorScheme) private var colorScheme
    let userStatusManager = UserStatusManager.shared
    @ObservedObject private var habitManager = HabitManager.shared
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showSidebar = false
    @State private var showPaywall = false
    @Binding var showSidebarCallback: Bool
    @State private var shouldScrollToBottom = false
    @State private var lastScrollTime = Date()
    
    // Navigation binding for bottom bar
    @Binding var selectedFeature: Models.Feature
    
    // State to control sheet presentations
    @State private var showAuthSheet = false
    @State private var showSubscriptionSuccessAlert = false
    @State private var showHabitCreatedAlert = false
    @State private var createdHabitTitle = ""
    @State private var showTaskCreatedAlert = false
    @State private var createdTaskTitle = ""
    @State private var showHabitDuplicateAlert = false
    @State private var showTaskDuplicateAlert = false
    @State private var duplicateHabitTitle = ""
    @State private var duplicateTaskTitle = ""
    @State private var showNotificationPermissionAlert = false
    @State private var navigateToHabitsAfterPermission = false
    
    // --- Add character limit constant ---
    let frontendCharLimit = 1000
    // ---------------------------------
    
    // Computed property for current suggestions based on chat mode
    private var currentSuggestions: [String] {
        switch viewModel.currentChatMode {
        case .task:
            return [
                "I have an exam coming up".localized,
                "I need to buy groceries".localized,
                "I need to make a reservation".localized
            ]
        case .habit:
            return [
                "Create a morning exercise habit".localized,
                "Help me build a daily reading routine".localized,
                "I want to start meditating regularly".localized
            ]
        }
    }
    
    // Debug helper
    private func debugLog(_ message: String) {
        print("[ChatView] \(message)")
    }
    
    // Simple default initializer for preview
    init(viewModel: ChatViewModel, showSidebarCallback: Binding<Bool> = .constant(false), selectedFeature: Binding<Models.Feature> = .constant(.chat)) {
        self.viewModel = viewModel
        self._showSidebarCallback = showSidebarCallback
        self._selectedFeature = selectedFeature
    }
    
    // MARK: - Body
    var body: some View {
        mainContentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(SheetModifiers(
                showAuthSheet: $showAuthSheet,
                showPaywall: $showPaywall,
                viewModel: viewModel
            ))
            .modifier(AlertModifiers(
                showSubscriptionSuccessAlert: $showSubscriptionSuccessAlert,
                showHabitCreatedAlert: $showHabitCreatedAlert,
                showTaskCreatedAlert: $showTaskCreatedAlert,
                showHabitDuplicateAlert: $showHabitDuplicateAlert,
                showTaskDuplicateAlert: $showTaskDuplicateAlert,
                showNotificationPermissionAlert: $showNotificationPermissionAlert,
                navigateToHabitsAfterPermission: $navigateToHabitsAfterPermission,
                createdHabitTitle: createdHabitTitle,
                createdTaskTitle: createdTaskTitle,
                duplicateHabitTitle: duplicateHabitTitle,
                duplicateTaskTitle: duplicateTaskTitle,
                onRequestNotificationPermission: requestNotificationPermission,
                onShowHabitsSheet: { 
                    NotificationCenter.default.post(name: Notification.Name("SwitchToHabitsView"), object: nil)
                }
            ))
            .onAppear {
                Task {
                    await habitManager.loadHabits()
                }
            }
    }
    
    // MARK: - Main Content View
    private var mainContentView: some View {
        ZStack {
            // Main content that responds to keyboard
            mainVStack
            
            // Overlays
            sidebarOverlay
            bottomBlurOverlay
            
            // Navigation bar - hides when keyboard appears for better UX
            VStack {
                Spacer()
                if !isTextFieldFocused {
                    BottomNavigationBar(selectedFeature: $selectedFeature)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.3), value: isTextFieldFocused)
        }
    }
    
    // MARK: - Main VStack
    private var mainVStack: some View {
        VStack(spacing: 0) {
            chatToolbar
            
            messagesListView
                .gesture(
                    TapGesture()
                        .onEnded { _ in
                            if isTextFieldFocused {
                                dismissKeyboard()
                            }
                        }
                )
        }
        .background(Color.clear)
        .overlay(darkModeShadow)
        .overlay(chatModeToggleOverlay, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Input area - automatically adjusts with keyboard
            VStack(spacing: 0) {
                inputArea
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                
                // Extend background to cover navigation bar area when keyboard is hidden
                if !isTextFieldFocused {
                    Color(.systemBackground)
                        .frame(height: 54) // Height of navigation bar + padding
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeOut(duration: 0.3), value: isTextFieldFocused)
    }
    
    // MARK: - Chat Mode Toggle (as floating overlay - no background banner)
    private var chatModeToggleOverlay: some View {
        VStack {
            HStack {
                Spacer()
                ChatModeToggle(mode: $viewModel.currentChatMode) { newMode in
                    viewModel.switchChatMode(to: newMode)
                }
                .frame(width: 140, height: 34)
                Spacer()
            }
            .padding(.top, 55) // Position below toolbar with more spacing
            Spacer()
        }
        .background(Color.clear) // No background banner - only toggle visible
    }
    
    // MARK: - Dark Mode Shadow
    private var darkModeShadow: some View {
        Group {
            if colorScheme == .dark {
                Rectangle()
                    .fill(Color.clear)
                    .shadow(color: Color.white.opacity(0.06), radius: 6, x: 0, y: 0)
            }
        }
    }
    
    // MARK: - Sidebar Overlay
    private var sidebarOverlay: some View {
        Group {
            if showSidebarCallback {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeSidebar()
                    }
                    .gesture(sidebarDragGesture)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
    }
    
    // MARK: - Sidebar Drag Gesture
    private var sidebarDragGesture: some Gesture {
        DragGesture()
            .onEnded { gesture in
                if gesture.translation.width < -50 && abs(gesture.translation.height) < 50 {
                    closeSidebar()
                }
            }
    }
    
    // MARK: - Bottom Blur Overlay
    private var bottomBlurOverlay: some View {
        VStack { Spacer() }
            .ignoresSafeArea(edges: .bottom)
            .overlay(bottomBlurContent)
    }
    
    // MARK: - Bottom Blur Content
    private var bottomBlurContent: some View {
        VStack(spacing: 0) {
            Spacer()
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(bottomBlurGradient)
                .frame(height: 120)
                .allowsHitTesting(false)
        }
    }
    
    // MARK: - Bottom Blur Gradient
    private var bottomBlurGradient: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.0), Color.black.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Toolbar View
    private var chatToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Menu button with notification badge
                Button(action: {
                    print("[Navigation] Menu button tapped")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSidebarCallback = true
                    }
                }) {
                    ZStack {
                        // Custom three-line icon with shorter middle and bottom lines
                        VStack(alignment: .leading, spacing: 4) {
                            // Top line - full width
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                                .frame(width: 22, height: 2.5)
                                .cornerRadius(1.25)
                            
                            // Middle line - shorter
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                                .frame(width: 16, height: 2.5)
                                .cornerRadius(1.25)
                            
                            // Bottom line - shorter
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                                .frame(width: 16, height: 2.5)
                                .cornerRadius(1.25)
                        }
                        
                        // Notification badge for unread daily quotes
                        if NotificationManager.shared.unreadNotificationCount > 0 {
                            VStack {
                                HStack {
                                    Spacer()
                                    ZStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 18, height: 18)
                                        
                                        Text("\(NotificationManager.shared.unreadNotificationCount)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                    .offset(x: 8, y: -8)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .frame(width: 36, height: 36)
                
                // Title only
                VStack(spacing: 4) {
                    // Title with better styling
                    Group {
                        if let conversation = viewModel.currentConversation {
                            Text(conversation.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                                .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                        } else {
                            Text("newChat".localized)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.center)
                                .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                        }
                    }
                    
                    
                }
                .id(viewModel.currentConversation?.id ?? "newChat")
                .frame(maxWidth: .infinity, alignment: .center)
                
                // New Chat button
                Button(action: {
                    print("[Navigation] New chat button tapped")
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        viewModel.clearConversation()
                    }
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal)
            .frame(height: 44)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Messages List View
    private var messagesListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    emptyStateView
                    messagesList
                    loadingIndicatorView
                    streamingIndicatorView
                    bottomAnchorView
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .onChange(of: viewModel.messages.count) { _, _ in
                debugLog("Messages count changed, scrolling to bottom")
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: shouldScrollToBottom) { _, shouldScroll in
                if shouldScroll {
                    debugLog("Manual scroll to bottom triggered")
                    withAnimation(.easeOut(duration: 0.25)) {
                    scrollToBottom(proxy)
                    }
                    shouldScrollToBottom = false
                }
            }
            .onChange(of: viewModel.isStreaming) { _, isStreaming in
                if isStreaming {
                    debugLog("Streaming started, enabling auto-scroll")
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _, newText in
                // Auto-scroll during streaming when the last message (AI response) updates
                if viewModel.isStreaming && !(newText?.isEmpty ?? true) {
                    let now = Date()
                    // Throttle scrolling to every 100ms for smooth performance
                    if now.timeIntervalSince(lastScrollTime) > 0.1 {
                        lastScrollTime = now
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("bottomID", anchor: .bottom)
                        }
                    }
                }
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    if isTextFieldFocused {
                        debugLog("Drag detected, dismissing keyboard")
                        isTextFieldFocused = false
                    }
                }
            )
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        Group {
            if viewModel.messages.isEmpty {
                newChatWelcomeView
                    .padding(.top, 40)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }
    
    // MARK: - Messages List
    private var messagesList: some View {
        ForEach(viewModel.messages) { message in
            MessageBubble(
                message: message, 
                isCurrentlyStreaming: viewModel.isStreaming && viewModel.currentStreamingMessageId == message.id,
                onHabitPushToSchedule: handlePushToSchedule,
                onTaskPushToSchedule: handleTaskPushToSchedule
            )
                .id(message.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
        }
    }
    
    // MARK: - Loading Indicator View
    private var loadingIndicatorView: some View {
        Group {
            if viewModel.isLoading && !viewModel.isStreaming {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        SmartAIAvatarView()
                        .padding(.bottom, 4)
                        
                        EnhancedTypingIndicator()
                            .padding(.vertical, 8)
                            .padding(.horizontal, 0)
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.8)),
                    removal: .opacity.animation(.easeOut(duration: 0.2))
                ))
            }
        }
    }
    
    // MARK: - Streaming Indicator View
    private var streamingIndicatorView: some View {
        Group {
            if viewModel.isStreaming && viewModel.currentStreamingMessageId == nil {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            SmartAIAvatarView()
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        VStack(spacing: 8) {
                            StreamingIndicator()
                                .padding(.vertical, 8)
                                .padding(.horizontal, 0)
                            
                            // Add streaming progress bar
                            StreamingProgressBar(isStreaming: viewModel.isStreaming)
                                .padding(.horizontal, 0)
                        }
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.8)),
                    removal: .opacity.animation(.easeOut(duration: 0.2))
                ))
            }
        }
    }
    
    // MARK: - Bottom Anchor View
    private var bottomAnchorView: some View {
        Color.clear
            .frame(height: 1)
            .id("bottomID")
    }
    
    // MARK: - Input Area View
    private var inputArea: some View {
        VStack(spacing: 0) {
            // Error message - show general errors (network, authentication, etc.)
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .multilineTextAlignment(.center)
            }
            
            // Input container
            HStack(alignment: .center, spacing: 8) {
                inputTextField
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            
            // --- Add Character Count (Conditional) ---
            if messageText.count > 700 { // Only show after 700 characters
                Text("\(messageText.count) / \(frontendCharLimit)")
                     .font(.caption)
                     .foregroundColor(messageText.count > frontendCharLimit ? .red : .gray)
                     .frame(maxWidth: .infinity, alignment: .trailing)
                     .padding(.horizontal, 12) // Align roughly with TextField end
                     .padding(.bottom, 6) // Space below input area
                     .transition(.opacity.animation(.easeInOut(duration: 0.2))) // Add animation
            }
            // --- End Character Count ---
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedCorners(tl: 24, tr: 24, bl: 0, br: 0))
        .shadow(color: (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05)), radius: 10, x: 0, y: -12)
        .overlay(
            Group {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                }
            }
        )
    }
    
    // MARK: - Input Text Field
    private var inputTextField: some View {
        ZStack(alignment: .trailing) {
            TextField(
                "Ask anything...",
                text: $messageText,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .padding(.trailing, 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                )
                .lineLimit(1...5)
                .focused($isTextFieldFocused)
                .disabled(viewModel.isLoading)
                .submitLabel(.send)
                .onSubmit {
                    debugLog("Submit triggered, sending message")
                    sendMessage()
                }
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if isLoading {
                        debugLog("Loading started, dismissing keyboard")
                        Task { @MainActor in
                        isTextFieldFocused = false
                        }
                    }
                }
                .onChange(of: messageText) { _, newValue in
                    // Use the constant here
                    if newValue.count > frontendCharLimit {
                        // Use DispatchQueue to avoid modifying state during view update cycle warning
                        DispatchQueue.main.async {
                             messageText = String(newValue.prefix(frontendCharLimit))
                        }
                    }
                }
                .onChange(of: isTextFieldFocused) { _, focused in
                    if focused {
                        debugLog("TextField focused, triggering scroll")
                        // Slight delay to ensure keyboard animation completes before scrolling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            shouldScrollToBottom = true
                        }
                    }
                }
            
            // Send button
            Button(action: sendMessage) {
                Image(systemName: messageText.isEmpty ? "circle" : "arrow.up.circle.fill")
                    .font(.system(size: 24))
                                            .foregroundColor(messageText.isEmpty || viewModel.isLoading ? .gray.opacity(0.5) : Color.brandPrimary)
            }
            .disabled(messageText.isEmpty || viewModel.isLoading)
            .padding(.trailing, 16)
            .scaleEffect(messageText.isEmpty ? 0.8 : 1.0)
            .animation(.spring(response: 0.3), value: messageText.isEmpty)
        }
    }
    
    // MARK: - Helper Methods
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
            proxy.scrollTo("bottomID", anchor: .bottom)
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Debug log
        debugLog("Sending message: \(text)")
        
        // Clear input field immediately
        messageText = ""
        
        // Dismiss keyboard immediately when sending
        dismissKeyboard()
        
        // Trigger scroll to bottom
        shouldScrollToBottom = true
        
        // Send message in the background
        Task {
            await viewModel.sendMessage(text)
        }
    }
    
    // Function to dismiss keyboard
    private func dismissKeyboard() {
        isTextFieldFocused = false
        UIApplication.shared.endEditing()
        debugLog("Keyboard dismissed")
    }
    
    // Function to close sidebar
    private func closeSidebar() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showSidebarCallback = false
        }
        debugLog("Sidebar closed")
    }
    
    // MARK: - Habit Management Functions
    @State private var isCreatingHabit = false
    
    private func handlePushToSchedule(habit: ComprehensiveHabit) {
        // Prevent multiple simultaneous habit creation attempts
        guard !isCreatingHabit else {
            print("⚠️ [ChatView] Habit creation already in progress, ignoring duplicate request")
            return
        }
        
        print("🎯 [ChatView] Pushing habit to schedule: \(habit.name)")
        isCreatingHabit = true
        
        // Habits are AI-created; keep manual editing optional post-suggestion only
        Task {
            // Clear any previous errors
            await MainActor.run {
                habitManager.clearError()
            }
            
            await habitManager.createHabit(habit)
            
            // Check for errors and show appropriate feedback
            await MainActor.run {
                isCreatingHabit = false // Reset the flag
                
                if let error = habitManager.error {
                    // Check if it's a duplication error
                    if error.hasPrefix("DUPLICATE_HABIT:") {
                        let existingHabitName = String(error.dropFirst("DUPLICATE_HABIT:".count))
                        duplicateHabitTitle = existingHabitName
                        showHabitDuplicateAlert = true
                        print("⚠️ [ChatView] Duplicate habit detected: \(existingHabitName)")
                    } else {
                        // Show other errors
                        print("❌ [ChatView] Habit creation failed: \(error)")
                    }
                } else {
                    // Show success feedback
                    createdHabitTitle = habit.name
                    
                    // Check notification permissions and navigate directly
                    checkNotificationPermissionsAndNavigate()
                }
            }
        }
    }
    
    // MARK: - Notification Permission Check
    private func checkNotificationPermissionsAndNavigate() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    // Notifications are enabled, show success alert then navigate
                    showHabitCreatedAlert = true
                    
                case .denied, .notDetermined:
                    // Show success alert first, then ask for permission
                    showHabitCreatedAlert = true
                    navigateToHabitsAfterPermission = true
                    
                case .ephemeral:
                    // Ephemeral notifications - show success alert then navigate
                    showHabitCreatedAlert = true
                    
                @unknown default:
                    // Fallback - show success alert then navigate
                    showHabitCreatedAlert = true
                }
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ [ChatView] Notification permission granted")
                    // Notification permission granted - the system will handle the rest
                } else {
                    print("❌ [ChatView] Notification permission denied")
                }
                
                // Navigate to habits regardless of permission result
                if navigateToHabitsAfterPermission {
                    // Post notification to switch to habits view
                    NotificationCenter.default.post(name: Notification.Name("SwitchToHabitsView"), object: nil)
                    navigateToHabitsAfterPermission = false
                }
            }
        }
    }
    
    // MARK: - Task Management Functions
    @State private var isCreatingTask = false
    
    private func handleTaskPushToSchedule(task: UserTask) {
        // Prevent multiple simultaneous task creation attempts
        guard !isCreatingTask else {
            print("⚠️ [ChatView] Task creation already in progress, ignoring duplicate request")
            return
        }
        
        print("🎯 [ChatView] Pushing task to schedule: \(task.name)")
        isCreatingTask = true
        
        // Tasks are AI-created; keep manual editing optional post-suggestion only
        Task {
            // Clear any previous errors
            await MainActor.run {
                TaskManager.shared.clearError()
            }
            
            await TaskManager.shared.createTask(task)
            
            // Check for errors and show appropriate feedback
            await MainActor.run {
                isCreatingTask = false // Reset the flag
                
                if let error = TaskManager.shared.error {
                    // Check if it's a duplication error
                    if error.hasPrefix("DUPLICATE_TASK:") {
                        let existingTaskName = String(error.dropFirst("DUPLICATE_TASK:".count))
                        duplicateTaskTitle = existingTaskName
                        showTaskDuplicateAlert = true
                        print("⚠️ [ChatView] Duplicate task detected: \(existingTaskName)")
                    } else {
                        // Show other errors
                        print("❌ [ChatView] Task creation failed: \(error)")
                    }
                } else {
                    // Show success feedback
                    createdTaskTitle = task.name
                    showTaskCreatedAlert = true
                    print("✅ [ChatView] Task created successfully: \(task.name)")
                }
            }
        }
    }
    
    // MARK: - Welcome View for New Chat
    private var newChatWelcomeView: some View {
        VStack(spacing: 16) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
            
            VStack(spacing: 4) {
                Text("Welcome to Calendo")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Plan, Track & Achieve")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 18) {
                ForEach(Array(currentSuggestions.enumerated()), id: \.offset) { index, suggestionKey in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            messageText = suggestionKey.localized
                        }
                        sendMessage()
                    }) {
                        Text(suggestionKey.localized)
                            .font(.system(size: 17, weight: .medium))
                            .fontWeight(.medium)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .background(Color.brandPrimary.opacity(0.2))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .cornerRadius(16)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(1.0)
                    .opacity(1.0)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1)),
                        removal: .opacity.animation(.easeOut(duration: 0.2))
                    ))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1), value: viewModel.currentChatMode)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    let isCurrentlyStreaming: Bool
    let onHabitPushToSchedule: ((ComprehensiveHabit) -> Void)?
    let onTaskPushToSchedule: ((UserTask) -> Void)?
    @State private var displayedText: String = ""
    @State private var targetText: String = ""
    @State private var bufferedFullText: String = ""
    @State private var animationTimer: Timer?
    @State private var currentIndex: Int = 0
    
    // Typewriter speed (characters per second) - slower for more natural feel
    private let typewriterSpeed: Double = 40.0
    
    // Convert markdown to AttributedString (enable full Markdown for lists, bold, etc.)
    private func markdownAttributedString(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }

    // Render a markdown block with simple heading/paragraph heuristics
    @ViewBuilder
    private func renderMarkdownBlock(_ block: String) -> some View {
        // Heading heuristics (#, ##, ###) or bold line
        if block.hasPrefix("# ") || block.hasPrefix("## ") || block.hasPrefix("### ") {
            Text(markdownAttributedString(block))
                .font(.title3.weight(.semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if block.trimmingCharacters(in: .whitespaces).hasPrefix("- ") || block.contains("\n- ") || block.trimmingCharacters(in: .whitespaces).hasPrefix("* ") {
            // Bulleted list block
            Text(markdownAttributedString(block))
                .font(.body)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Regular paragraph with italics/bold handled by markdown parser
            Text(markdownAttributedString(block))
                .font(.body)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func startTypewriterAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        displayedText = ""
        currentIndex = 0
        guard !targetText.isEmpty else { return }
        let interval = 1.0 / typewriterSpeed
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if currentIndex < targetText.count {
                let endIndex = targetText.index(targetText.startIndex, offsetBy: currentIndex + 1)
                displayedText = String(targetText[..<endIndex])
                currentIndex += 1
            } else {
                timer.invalidate()
                animationTimer = nil
            }
        }
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var userBubbleGradient: LinearGradient {
        // Brand gradient for user messages (works in light and dark)
        let start = Color.brandPrimary
        let end = Color.brandPrimaryDark
        return LinearGradient(gradient: Gradient(colors: [start, end]), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var aiBubbleBackground: Color {
        // Use requested pink color consistently; in dark mode, tone it slightly
        return colorScheme == .dark ? Color.aiBubblePink.opacity(0.85) : Color.aiBubblePink
    }
    
    private var aiBorderColor: Color {
        if colorScheme == .dark {
            return Color.brandPrimary.opacity(0.25)
        } else {
            return Color.brandPrimary.opacity(0.35)
        }
    }
    
    private var userBorderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if message.isUser {
                userMessageView
            } else {
                aiMessageView
            }
        }
        .onAppear {
            handleViewAppear()
        }
        .onChange(of: message.text) { _, newText in
            handleTextChange(newText: newText)
        }
        .onChange(of: isCurrentlyStreaming) { _, streaming in
            handleStreamingChange(streaming: streaming)
        }
        .onDisappear {
            handleViewDisappear()
        }
    }
    
    // MARK: - User Message View
    private var userMessageView: some View {
        HStack {
            Spacer()
            Text(message.text)
                .padding()
                .background(userBubbleGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.clear, lineWidth: 0)
                )
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .cornerRadius(16)
                .textSelection(.enabled)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)
        }
    }
    
    // MARK: - AI Message View
    private var aiMessageView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                aiMessageHeader
                aiMessageContent
            }
            Spacer()
        }
    }
    
    // MARK: - AI Message Header
    private var aiMessageHeader: some View {
        SmartAIAvatarView()
        .padding(.bottom, 4)
    }
    
    // MARK: - AI Message Content
    @ViewBuilder
    private var aiMessageContent: some View {
        // Show streaming indicator only during active streaming
        // Otherwise, show message content (which includes cards) even if text is empty
        if isCurrentlyStreaming && targetText.isEmpty {
            streamingIndicatorContent
        } else {
            messageContentWithHabit
        }
    }
    
    // MARK: - Streaming Indicator Content
    private var streamingIndicatorContent: some View {
        HStack(spacing: 4) {
            StreamingIndicator()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 0)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)
    }
    
    // MARK: - Message Content with Suggestions
    private var messageContentWithHabit: some View {
        VStack(alignment: .leading, spacing: 12) {
            mainMessageContent
            habitSuggestionContent
            taskSuggestionContent
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 0)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: displayedText.count)
    }
    
    // MARK: - Main Message Content
    private var mainMessageContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Render Markdown with paragraph spacing and heading styles
            let paragraphs = displayedText.components(separatedBy: "\n\n")
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { idx, raw in
                let block = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    renderMarkdownBlock(block)
                    if isCurrentlyStreaming && idx == paragraphs.count - 1 {
                        EnhancedBlinkingCursor()
                    }
                }
            }
        }
    }
    
    // MARK: - Habit Suggestion Content
    @ViewBuilder
    private var habitSuggestionContent: some View {
        // Show card if habit is detected and we're not currently streaming this message
        // Cards should appear immediately after detection completes
        if let habitSuggestion = message.detectedHabitSuggestion {
            // Only hide during active streaming of this specific message
            if !isCurrentlyStreaming {
            HabitSuggestionCard(
                habit: habitSuggestion,
                onPushToSchedule: {
                    // Handle push to schedule action
                    onHabitPushToSchedule?(habitSuggestion)
                }
            )
            .padding(.top, 8)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    // MARK: - Task Suggestion Content
    @ViewBuilder
    private var taskSuggestionContent: some View {
        // Show card if task is detected and we're not currently streaming this message
        // Cards should appear immediately after detection completes
        if let taskSuggestion = message.detectedTaskSuggestion {
            // Only hide during active streaming of this specific message
            if !isCurrentlyStreaming {
            TaskSuggestionCard(
                task: taskSuggestion,
                onPushToSchedule: {
                    // Handle push to schedule action for tasks
                    onTaskPushToSchedule?(taskSuggestion)
                }
            )
            .padding(.top, 8)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    // MARK: - View Lifecycle Handlers
    private func handleViewAppear() {
        bufferedFullText = message.displayText
        if message.isUser {
            displayedText = message.text
        } else {
            // While streaming, keep indicator only; after streaming, show content
            if isCurrentlyStreaming {
                targetText = ""
                displayedText = ""
            } else {
                // Always set targetText to displayText (even if empty) so cards can show
                targetText = message.displayText
                // If not streaming, show the cleaned display text (no JSON)
                displayedText = targetText.isEmpty ? "" : targetText
            }
        }
    }
    
    private func handleTextChange(newText: String) {
        // Always buffer the cleaned display text so JSON is not shown
        bufferedFullText = message.displayText
        if message.isUser {
            displayedText = newText
        } else {
            // During streaming, do not reveal text; buffer only
            if !isCurrentlyStreaming {
                targetText = message.displayText
                startTypewriterAnimation()
            }
        }
    }
    
    private func handleStreamingChange(streaming: Bool) {
        // When streaming ends, animate revealing buffered text
        if !streaming {
            // Streaming just ended: animate the cleaned display text (no JSON)
            targetText = message.displayText
            startTypewriterAnimation()
        }
    }
    
    private func handleViewDisappear() {
        // Clean up timer when view disappears
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animationOffset = 0.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundColor(.gray)
                    .offset(y: sin(animationOffset + Double(index) * 0.5) * 2)
            }
        }
        .onAppear {
            withAnimation(Animation.linear(duration: 1.0).repeatForever()) {
                animationOffset = 2 * .pi
            }
        }
    }
}

// MARK: - Streaming Indicator
struct StreamingIndicator: View {
    @State private var animationOffset = 0.0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 5, height: 5)
                    .foregroundColor(.blue)
                    .opacity(0.3 + 0.7 * sin(animationOffset + Double(index) * 0.8))
                    .scaleEffect(pulseScale)
                    .animation(
                        Animation.easeInOut(duration: 1.2)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationOffset
                    )
            }
        }
        .onAppear {
            animationOffset = 1.0
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
            }
        }
    }
}

// Add this custom shape for rounded specific corners
struct RoundedCorners: Shape {
    var tl: CGFloat = 0.0
    var tr: CGFloat = 0.0
    var bl: CGFloat = 0.0
    var br: CGFloat = 0.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.size.width
        let h = rect.size.height
        
        // Make sure we don't exceed the size of the rectangle
        let tl = min(min(self.tl, h/2), w/2)
        let tr = min(min(self.tr, h/2), w/2)
        let bl = min(min(self.bl, h/2), w/2)
        let br = min(min(self.br, h/2), w/2)
        
        path.move(to: CGPoint(x: w / 2.0, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Chat Mode Toggle (Custom Switch)
struct ChatModeToggle: View {
    @Binding var mode: ChatMode
    var onChange: (ChatMode) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var isOn: Bool { mode == .habit }
    
    var body: some View {
        Button(action: {
            let newMode: ChatMode = isOn ? .task : .habit
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                mode = newMode
                onChange(newMode)
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                // Track background
                Group {
                    if isOn {
                        // Habit mode: brand green
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.brandPrimary)
                    } else {
                        // Task mode: system background color
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                }
                .overlay(
                    Group {
                        if isOn {
                            // Habit: white text on brand green
                            Text("Habit")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .transition(.opacity)
                        } else {
                            // Task: adaptive text color - grey in dark mode, black in light mode
                            Text("Task")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(colorScheme == .dark ? .gray : .black)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 8)
                )
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.9) : Color.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .padding(3)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Smart AI Avatar View
struct SmartAIAvatarView: View {
    static var currentAssistantDisplayName: String {
        return "Smart AI"
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            
            Text("Smart AI")
                .font(.caption.weight(.semibold))
                .font(.system(size: 13))
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    NavigationView {
        ChatView(viewModel: ChatViewModel())
    }
} 

// MARK: - Blinking Cursor used in streaming
struct BlinkingCursor: View {
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.8))
            .frame(width: 6, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - Enhanced Blinking Cursor for streaming
struct EnhancedBlinkingCursor: View {
    @State private var visible = true
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Rectangle()
            .fill(Color.blue.opacity(0.8))
            .frame(width: 2, height: 18)
            .opacity(visible ? 1 : 0)
            .scaleEffect(pulseScale)
            .onAppear {
                // Blinking animation
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
                // Subtle pulse animation
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.1
                }
            }
    }
}

// MARK: - Sheet Modifiers
struct SheetModifiers: ViewModifier {
    @Binding var showAuthSheet: Bool
    @Binding var showPaywall: Bool
    let viewModel: ChatViewModel
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAuthSheet) {
                AuthenticationView(onAuthenticationSuccess: {
                    viewModel.startNewChat()
                })
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onPurchaseSuccess: {
                    // Handle purchase success
                })
            }
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Alert Modifiers
struct AlertModifiers: ViewModifier {
    @Binding var showSubscriptionSuccessAlert: Bool
    @Binding var showHabitCreatedAlert: Bool
    @Binding var showTaskCreatedAlert: Bool
    @Binding var showHabitDuplicateAlert: Bool
    @Binding var showTaskDuplicateAlert: Bool
    @Binding var showNotificationPermissionAlert: Bool
    @Binding var navigateToHabitsAfterPermission: Bool
    let createdHabitTitle: String
    let createdTaskTitle: String
    let duplicateHabitTitle: String
    let duplicateTaskTitle: String
    let onRequestNotificationPermission: () -> Void
    let onShowHabitsSheet: () -> Void
    
    func body(content: Content) -> some View {
        content
            .alert("subscriptionSuccessTitle".localized, isPresented: $showSubscriptionSuccessAlert) {
                Button("ok".localized) { }
            } message: {
                Text("subscriptionSuccessMessage".localized)
            }
            .alert("Habit Created! 🎉", isPresented: $showHabitCreatedAlert) {
                Button("View Habits") {
                    if navigateToHabitsAfterPermission {
                        showNotificationPermissionAlert = true
                    } else {
                        onShowHabitsSheet()
                    }
                }
                Button("Later") { 
                    navigateToHabitsAfterPermission = false
                }
            } message: {
                Text("'\(createdHabitTitle)' has been added to your habit schedule. Would you like to view your habits now?")
            }
            .alert("Task Created! ✅", isPresented: $showTaskCreatedAlert) {
                Button("View Tasks") {
                    // Navigate to tasks view
                    NotificationCenter.default.post(name: Notification.Name("SwitchToTasksView"), object: nil)
                }
                Button("Later") { }
            } message: {
                Text("'\(createdTaskTitle)' has been added to your task list. Would you like to view your tasks now?")
            }
            .alert("Habit Already Exists ⚠️", isPresented: $showHabitDuplicateAlert) {
                Button("View Habits") {
                    NotificationCenter.default.post(name: Notification.Name("SwitchToHabitsView"), object: nil)
                }
                Button("OK") { }
            } message: {
                Text("You already have a habit called '\(duplicateHabitTitle)'. Would you like to view your existing habits?")
            }
            .alert("Task Already Exists ⚠️", isPresented: $showTaskDuplicateAlert) {
                Button("View Tasks") {
                    NotificationCenter.default.post(name: Notification.Name("SwitchToTasksView"), object: nil)
                }
                Button("OK") { }
            } message: {
                Text("You already have a task called '\(duplicateTaskTitle)'. Would you like to view your existing tasks?")
            }
            .alert("Enable Notifications? 🔔", isPresented: $showNotificationPermissionAlert) {
                Button("Enable") {
                    onRequestNotificationPermission()
                }
                Button("Skip") {
                    onShowHabitsSheet()
                    navigateToHabitsAfterPermission = false
                }
            } message: {
                Text("Get reminders for '\(createdHabitTitle)' to stay on track with your habit!")
            }
    }
}

