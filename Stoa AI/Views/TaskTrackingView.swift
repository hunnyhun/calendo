import SwiftUI
import FirebaseAuth

// MARK: - Main Task Tracking View
struct TaskTrackingView: View {
    @ObservedObject private var taskManager = TaskManager.shared
    @StateObject private var importService = ImportService.shared
    let userStatusManager = UserStatusManager.shared
    var onNavigateBack: (() -> Void)? = nil
    
    @State private var showingTaskCreation = false
    @State private var showingTaskDetail: UserTask?
    @State private var selectedTab = 0
    @State private var showingAuthView = false
    @State private var showingImportAlert = false
    @State private var showingImportSheet = false
    @State private var shareLink: URL?
    
    private var userStatus: Models.UserStatus {
        if userStatusManager.state.isAuthenticated {
            return .loggedIn(isPremium: userStatusManager.state.isPremium)
        } else {
            return .anonymous
        }
    }
    
    private var canAccessTasks: Bool {
        // Tasks are available to all authenticated users (no premium restriction)
        return userStatusManager.state.isAuthenticated
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button, title and add button
            HStack {
                // Back button
                Button(action: {
                    onNavigateBack?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Back")
                            .font(.headline)
                    }
                    .foregroundColor(.brandPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Tasks")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Import button
                    Button(action: {
                        checkClipboardForImport()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                            .foregroundColor(.brandPrimary)
                    }
                    
                    // Add button
                Button(action: {
                    handleTaskCreation()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.brandPrimary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
                
                // Custom tab toggle
                ViewTypeToggle(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                // Content based on selected tab
                if canAccessTasks {
                    TabView(selection: $selectedTab) {
                        // Active tasks
                        ActiveTasksView(
                            taskManager: taskManager,
                            onCreateTask: handleTaskCreation
                        )
                        .tag(0)
                        
                        // All tasks
                        AllTasksView(
                            taskManager: taskManager,
                            showingTaskDetail: $showingTaskDetail
                        )
                        .tag(1)
                        
                        // Completed tasks
                        CompletedTasksView(
                            taskManager: taskManager,
                            showingTaskDetail: $showingTaskDetail
                        )
                        .tag(2)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                } else {
                    // Show login required view
                    VStack(spacing: 24) {
                        Spacer()
                        
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 80))
                            .foregroundColor(.brandPrimary)
                        
                        VStack(spacing: 12) {
                            Text("Sign In Required")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Create an account to access task management and organize your work")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        Button(action: {
                            showingAuthView = true
                        }) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Sign Up or Log In")
                            }
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                }
            }
            .onAppear {
                if canAccessTasks {
                    Task {
                        await taskManager.loadTasks()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ImportFromDeepLink"))) { notification in
                if let userInfo = notification.userInfo,
                   let url = userInfo["url"] as? URL {
                    Task {
                        if await importService.parseFromURL(url) {
                            if importService.importableTask != nil {
                                showingImportSheet = true
                            } else {
                                showingImportAlert = true
                            }
                        } else {
                            showingImportAlert = true
                        }
                    }
                }
            }
            .sheet(item: $showingTaskDetail) { task in
                TaskDetailView(task: task, taskManager: taskManager)
            }
            .sheet(isPresented: $showingAuthView) {
                AuthenticationView()
            }
            .sheet(isPresented: $showingImportSheet) {
                if let task = importService.importableTask {
                    ImportTaskView(task: task, taskManager: taskManager) {
                        importService.clearImport()
                        showingImportSheet = false
                    }
                }
            }
            .alert("Import Error", isPresented: $showingImportAlert) {
                Button("OK", role: .cancel) {
                    importService.clearImport()
                }
            } message: {
                Text(importService.importError ?? "Could not import task.")
            }
        }
        
        // MARK: - Helper Functions
        
        func checkClipboardForImport() {
            let pasteboard = UIPasteboard.general
            if let clipboardText = pasteboard.string, !clipboardText.isEmpty {
                Task {
                    if await importService.parseFromText(clipboardText) {
                        if importService.importableTask != nil {
                            showingImportSheet = true
                        } else {
                            showingImportAlert = true
                        }
                    } else {
                        showingImportAlert = true
                    }
                }
            } else {
                importService.importError = "Clipboard is empty. Please copy a shared task first."
                showingImportAlert = true
            }
        }
        
        private func handleTaskCreation() {
            if canAccessTasks {
                // Navigate to chat in task mode
                NotificationCenter.default.post(name: Notification.Name("SwitchToTaskMode"), object: nil)
            } else {
                showingAuthView = true
            }
        }
    }

// MARK: - Active Tasks View
struct ActiveTasksView: View {
    @ObservedObject var taskManager: TaskManager
    let onCreateTask: () -> Void
    @State private var showingDeleteAlert: UserTask?
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @State private var shareLink: URL?
    
    private var activeTasks: [UserTask] {
        let filtered = taskManager.tasks.filter { $0.isActive && !$0.isCompleted }
        print("🔍 [ActiveTasksView] activeTasks computed - Total tasks: \(taskManager.tasks.count), Active: \(filtered.count)")
        print("🔍 [ActiveTasksView] Task states: \(taskManager.tasks.map { "\($0.name): isActive=\($0.isActive), isCompleted=\($0.isCompleted)" })")
        return filtered
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if activeTasks.isEmpty {
                    EmptyTasksView(onCreateTask: onCreateTask)
                } else {
                    ForEach(activeTasks) { task in
                        TaskCard(
                            task: task,
                            stats: taskManager.getStats(for: task),
                            onToggleCompletion: {
                                Task {
                                    await taskManager.toggleTaskCompletion(task)
                                }
                            },
                            onToggleStep: { stepId in
                                Task {
                                    await taskManager.toggleStepCompletion(task, stepId: stepId)
                                }
                            },
                            onToggleActive: {
                                Task {
                                    await taskManager.toggleTaskActive(task)
                                }
                            },
                            onDelete: {
                                showingDeleteAlert = task
                            },
                            onShare: {
                                Task { @MainActor in
                                    let shareResult = await taskManager.shareTask(task)
                                    shareText = shareResult.text
                                    shareLink = shareResult.link
                                    showingShareSheet = true
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                showingDeleteAlert = task
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                Task {
                                    await taskManager.toggleTaskActive(task)
                                }
                            } label: {
                                Label(task.isActive ? "Deactivate" : "Activate", systemImage: task.isActive ? "pause.circle" : "play.circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .alert(item: $showingDeleteAlert) { task in
            Alert(
                title: Text("Delete Task"),
                message: Text("Are you sure you want to delete \"\(task.name)\"? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await taskManager.deleteTask(task)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = shareLink {
                ShareSheet(activityItems: [shareText, link])
            } else {
                ShareSheet(activityItems: [shareText])
            }
        }
    }
}

// MARK: - All Tasks View
struct AllTasksView: View {
    @ObservedObject var taskManager: TaskManager
    @Binding var showingTaskDetail: UserTask?
    @State private var showingDeleteAlert: UserTask?
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @State private var shareLink: URL?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(taskManager.tasks) { task in
                    TaskSummaryCard(
                        task: task,
                        stats: taskManager.getStats(for: task),
                        onTap: {
                            showingTaskDetail = task
                        },
                        onToggleActive: {
                            Task {
                                await taskManager.toggleTaskActive(task)
                            }
                        },
                        onDelete: {
                            showingDeleteAlert = task
                        },
                        onShare: {
                            Task { @MainActor in
                                let shareResult = await taskManager.shareTask(task)
                                shareText = shareResult.text
                                shareLink = shareResult.link
                                showingShareSheet = true
                            }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            showingDeleteAlert = task
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            Task {
                                await taskManager.toggleTaskActive(task)
                            }
                        } label: {
                            Label(task.isActive ? "Deactivate" : "Activate", systemImage: task.isActive ? "pause.circle" : "play.circle")
                        }
                        .tint(.orange)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .alert(item: $showingDeleteAlert) { task in
            Alert(
                title: Text("Delete Task"),
                message: Text("Are you sure you want to delete \"\(task.name)\"? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await taskManager.deleteTask(task)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = shareLink {
                ShareSheet(activityItems: [shareText, link])
            } else {
                ShareSheet(activityItems: [shareText])
            }
        }
    }
}

// MARK: - Completed Tasks View
struct CompletedTasksView: View {
    @ObservedObject var taskManager: TaskManager
    @Binding var showingTaskDetail: UserTask?
    @State private var showingDeleteAlert: UserTask?
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @State private var shareLink: URL?
    
    private var completedTasks: [UserTask] {
        taskManager.tasks.filter { $0.isCompleted }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if completedTasks.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        VStack(spacing: 8) {
                            Text("No Completed Tasks")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Complete some tasks to see them here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(40)
                } else {
                    ForEach(completedTasks) { task in
                        TaskSummaryCard(
                            task: task,
                            stats: taskManager.getStats(for: task),
                            onTap: {
                                showingTaskDetail = task
                            },
                            onToggleActive: {
                                Task {
                                    await taskManager.toggleTaskActive(task)
                                }
                            },
                            onDelete: {
                                showingDeleteAlert = task
                            },
                            onShare: {
                                Task { @MainActor in
                                    let shareResult = await taskManager.shareTask(task)
                                    shareText = shareResult.text
                                    shareLink = shareResult.link
                                    showingShareSheet = true
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                showingDeleteAlert = task
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                Task {
                                    await taskManager.toggleTaskActive(task)
                                }
                            } label: {
                                Label(task.isActive ? "Deactivate" : "Activate", systemImage: task.isActive ? "pause.circle" : "play.circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .alert(item: $showingDeleteAlert) { task in
            Alert(
                title: Text("Delete Task"),
                message: Text("Are you sure you want to delete \"\(task.name)\"? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await taskManager.deleteTask(task)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = shareLink {
                ShareSheet(activityItems: [shareText, link])
            } else {
                ShareSheet(activityItems: [shareText])
            }
        }
    }
}

// MARK: - Task Card
struct TaskCard: View {
    let task: UserTask
    let stats: TaskStats
    let onToggleCompletion: () -> Void
    let onToggleStep: (String) -> Void
    let onToggleActive: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    @State private var isExpanded = false
    
    // Convert string category to HabitCategory for display
    private var displayCategory: HabitCategory {
        guard let categoryString = task.category?.lowercased() else {
            return .personalGrowth
        }
        switch categoryString {
        case "physical", "fitness", "health":
            return .physical
        case "mental", "mindfulness", "meditation":
            return .mindfulness
        case "spiritual", "spirituality":
            return .spiritual
        case "social", "relationships":
            return .social
        case "productivity", "work", "career":
            return .productivity
        case "learning", "education", "study":
            return .learning
        default:
            return .personalGrowth
        }
    }
    
    private var categoryIcon: some View {
        Image(systemName: displayCategory.icon)
            .font(.title2)
            .foregroundColor(displayCategory.color)
            .frame(width: 40, height: 40)
            .background(displayCategory.color.opacity(0.1))
            .clipShape(Circle())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                categoryIcon
                
                Button(action: onToggleCompletion) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(task.isCompleted ? .green : .gray)
                }
                .padding(.top, 2) // Align with text baseline
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .strikethrough(task.isCompleted)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Show category if available, otherwise show steps
                    if task.category != nil {
                        Text(displayCategory.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !task.steps.isEmpty {
                        Text("\(stats.completedSteps)/\(stats.totalSteps) steps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // Invisible spacer to maintain height when no steps
                        Text(" ")
                            .font(.caption)
                            .opacity(0)
                    }
                }
                .frame(minHeight: 44) // Ensure consistent minimum height
                
                Spacer()
                
                HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                    .padding(.top, 2) // Align with text baseline
                    
                    Menu {
                        Button(action: onToggleActive) {
                            Label(task.isActive ? "Deactivate" : "Activate", systemImage: task.isActive ? "pause.circle" : "play.circle")
                        }
                        
                        Button(action: onShare) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2) // Align with text baseline
                }
            }
            
            // Description - always reserve space to maintain consistent height
            ZStack(alignment: .topLeading) {
                // Invisible placeholder to maintain height
                Text(" ")
                    .font(.body)
                    .opacity(0)
                    .lineLimit(2)
                
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: !isExpanded)
                }
            }
            .frame(minHeight: isExpanded ? nil : 40) // Fixed minimum height when collapsed
            
            // Steps (if expanded and has steps)
            if isExpanded && !task.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    ForEach(task.steps) { step in
                        HStack {
                            Button(action: {
                                onToggleStep(step.id)
                            }) {
                                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(step.isCompleted ? .green : .gray)
                                    .font(.caption)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.displayTitle)
                                .font(.body)
                                .foregroundColor(step.isCompleted ? .secondary : .primary)
                                .strikethrough(step.isCompleted)
                                
                                if let date = step.date {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                        Text(date)
                                            .font(.caption2)
                                        if let time = step.time {
                                            Text("• \(time)")
                                                .font(.caption2)
                                        }
                                    }
                                    .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(task.isCompleted ? Color.green.opacity(0.05) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(task.isCompleted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .opacity(task.isActive ? 1.0 : 0.6)
    }
}

// MARK: - Task Summary Card
struct TaskSummaryCard: View {
    let task: UserTask
    let stats: TaskStats
    let onTap: () -> Void
    let onToggleActive: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    
    // Convert string category to HabitCategory for display
    private var displayCategory: HabitCategory {
        guard let categoryString = task.category?.lowercased() else {
            return .personalGrowth
        }
        switch categoryString {
        case "physical", "fitness", "health":
            return .physical
        case "mental", "mindfulness", "meditation":
            return .mindfulness
        case "spiritual", "spirituality":
            return .spiritual
        case "social", "relationships":
            return .social
        case "productivity", "work", "career":
            return .productivity
        case "learning", "education", "study":
            return .learning
        default:
            return .personalGrowth
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: displayCategory.icon)
                        .font(.title3)
                        .foregroundColor(displayCategory.color)
                    
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .green : .gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .strikethrough(task.isCompleted)
                        
                        if task.category != nil {
                            Text(displayCategory.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !task.steps.isEmpty {
                            Text("\(stats.completedSteps)/\(stats.totalSteps) steps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                    if task.isCompleted {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Completed")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            if let completedAt = task.completedAt {
                                Text(completedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            }
                        }
                        
                        Menu {
                            Button(action: onToggleActive) {
                                Label(task.isActive ? "Deactivate" : "Activate", systemImage: task.isActive ? "pause.circle" : "play.circle")
                            }
                            
                            Button(action: onShare) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(task.isCompleted ? Color.green.opacity(0.05) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(task.isCompleted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
            .opacity(task.isActive ? 1.0 : 0.6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Empty Tasks View
struct EmptyTasksView: View {
    let onCreateTask: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Tasks Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Start organizing your work with task management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Create Your First Task") {
                onCreateTask()
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.brandPrimary)
            .clipShape(Capsule())
        }
        .padding(40)
    }
}

// MARK: - Task Detail View (Stub)
struct TaskDetailView: View {
    let task: UserTask
    @ObservedObject var taskManager: TaskManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Task Details")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Coming Soon")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // This will be expanded in future iterations
                VStack(spacing: 16) {
                    Text("📝 Edit task details")
                    Text("📊 View completion statistics")
                    Text("🔄 Task history and timeline")
                    Text("📋 Manage task steps")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
            .padding(40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Dismiss the sheet
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    TaskTrackingView()
}
