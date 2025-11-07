import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class TaskManager: ObservableObject {
    static let shared = TaskManager()
    
    @Published var tasks: [UserTask] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private var tasksListener: ListenerRegistration?
    private var isLoadingTasks = false // Prevent concurrent loads
    
    init() {}
    
    // Clear error state
    func clearError() {
        error = nil
    }
    
    // MARK: - Data Loading
    
    func loadTasks() async {
        guard Auth.auth().currentUser?.uid != nil else {
            print("❌ [TaskManager] loadTasks - No authenticated user")
            return
        }
        
        // Prevent concurrent loads
        if isLoadingTasks {
            print("⚠️ [TaskManager] loadTasks - Already loading, skipping duplicate call")
            return
        }
        
        isLoadingTasks = true
        isLoading = true
        
        print("🔄 [TaskManager] loadTasks - Starting task load...")
        
        // Use backend function instead of direct Firestore
        _Concurrency.Task {
            do {
                let tasksData = try await CloudFunctionService.shared.getTasks()
                
                await MainActor.run {
                    do {
                        // Convert backend data to UserTask objects
                        let loadedTasks = try tasksData.compactMap { data -> UserTask? in
                            let jsonData = try JSONSerialization.data(withJSONObject: data)
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .iso8601
                            return try decoder.decode(UserTask.self, from: jsonData)
                        }
                        
                        // Deduplicate by ID (keep first occurrence)
                        var seenIds = Set<String>()
                        let deduplicatedTasks = loadedTasks.filter { task in
                            if seenIds.contains(task.id) {
                                print("⚠️ [TaskManager] loadTasks - Found duplicate task ID: \(task.id) (\(task.name)), removing duplicate")
                                return false
                            }
                            seenIds.insert(task.id)
                            return true
                        }
                        
                        self.tasks = deduplicatedTasks
                        print("✅ [TaskManager] loadTasks - Loaded \(deduplicatedTasks.count) tasks from backend (removed \(loadedTasks.count - deduplicatedTasks.count) duplicates)")
                        print("📋 [TaskManager] loadTasks - Task IDs: \(deduplicatedTasks.map { $0.id })")
                        print("📊 [TaskManager] loadTasks - Task isActive states: \(deduplicatedTasks.map { "\($0.name): isActive=\($0.isActive), isCompleted=\($0.isCompleted)" })")
                        self.error = nil
                    } catch {
                        print("❌ [TaskManager] loadTasks - Error parsing tasks: \(error.localizedDescription)")
                        self.error = error.localizedDescription
                        self.tasks = []
                    }
                    self.isLoading = false
                    self.isLoadingTasks = false
                }
            } catch {
                await MainActor.run {
                    print("❌ [TaskManager] loadTasks - Error loading from backend: \(error.localizedDescription)")
                    self.error = error.localizedDescription
                    self.isLoading = false
                    self.isLoadingTasks = false
                }
            }
        }
    }
    
    // MARK: - Task Management
    
    func createTask(_ task: UserTask) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Please sign in to create tasks"
            return
        }
        
        // Refresh tasks list to ensure we have the latest data
        await loadTasks()
        
        // Check if task with same name already exists (case-insensitive)
        let existingTask = tasks.first { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == task.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        
        if let existing = existingTask {
            error = "DUPLICATE_TASK:\(existing.name)"
            print("⚠️ [TaskManager] Duplicate task prevented: '\(task.name)' (existing: '\(existing.name)')")
            return
        }
        
        do {
            // Set startDate when user pushes to calendar (now)
            // Preserve createdAt if it exists (from AI), otherwise set it to now
            let now = ISO8601DateFormatter().string(from: Date())
            let createdAtToUse = task.createdAt ?? now
            let startDateToUse = now // Always set startDate to now when user pushes to calendar
            
            // If startDate is being set for the first time (was nil, now has value), make it active
            let shouldBeActive = task.startDate == nil ? true : task.isActive
            
            let taskToSave = UserTask(
                id: task.id,
                name: task.name,
                goal: task.goal,
                category: task.category,
                description: task.description,
                createdAt: createdAtToUse,
                completedAt: task.completedAt,
                isCompleted: task.isCompleted,
                taskSchedule: task.taskSchedule,
                createdBy: task.createdBy ?? userId,
                startDate: startDateToUse,
                isActive: shouldBeActive
            )
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let taskData = try encoder.encode(taskToSave)
            let taskDict = try JSONSerialization.jsonObject(with: taskData) as! [String: Any]
            
            // Debug: Print what we're saving
            print("💾 [TaskManager] Saving task data: \(taskDict)")
            
            let _ = try await db.collection("users").document(userId).collection("tasks").addDocument(data: taskDict)
            print("✅ [TaskManager] Created task: \(task.name)")
            
            // Reload tasks to reflect the new addition
            await loadTasks()
            
        } catch {
            print("❌ [TaskManager] Error creating task: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func updateTask(_ task: UserTask) async {
        print("💾 [TaskManager] updateTask called for: \(task.name) (ID: \(task.id))")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ [TaskManager] updateTask failed: No authenticated user")
            error = "Please sign in to update tasks"
            return
        }
        
        let taskId = task.id
        print("🔍 [TaskManager] updateTask - User ID: \(userId), Task ID: \(taskId), isActive: \(task.isActive)")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let taskData = try encoder.encode(task)
            let taskDict = try JSONSerialization.jsonObject(with: taskData) as! [String: Any]
            
            print("💾 [TaskManager] updateTask - Saving to Firestore...")
            try await db.collection("users").document(userId).collection("tasks").document(taskId).setData(taskDict)
            print("✅ [TaskManager] updateTask - Successfully updated task: \(task.name)")
            
            // Reload tasks to reflect the update
            print("🔄 [TaskManager] updateTask - Reloading tasks...")
            await loadTasks()
            print("✅ [TaskManager] updateTask - Tasks reloaded, update complete")
        } catch {
            print("❌ [TaskManager] updateTask - Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func deleteTask(_ task: UserTask) async {
        print("🗑️ [TaskManager] deleteTask called for: \(task.name) (ID: \(task.id))")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ [TaskManager] deleteTask failed: No authenticated user")
            error = "Please sign in to delete tasks"
            return
        }
        
        let taskId = task.id
        print("🔍 [TaskManager] deleteTask - User ID: \(userId), Task ID: \(taskId)")
        
        do {
            print("💾 [TaskManager] deleteTask - Deleting from Firestore...")
            try await db.collection("users").document(userId).collection("tasks").document(taskId).delete()
            print("✅ [TaskManager] deleteTask - Successfully deleted task: \(task.name)")
            
            // Reload tasks to reflect the deletion
            print("🔄 [TaskManager] deleteTask - Reloading tasks...")
            await loadTasks()
            print("✅ [TaskManager] deleteTask - Tasks reloaded, deletion complete")
        } catch {
            print("❌ [TaskManager] deleteTask - Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func toggleTaskActive(_ task: UserTask) async {
        let newActiveState = !task.isActive
        print("🔄 [TaskManager] toggleTaskActive called for: \(task.name) (ID: \(task.id))")
        print("📊 [TaskManager] toggleTaskActive - Current state: \(task.isActive ? "ACTIVE" : "INACTIVE") → New state: \(newActiveState ? "ACTIVE" : "INACTIVE")")
        
        let updatedTask = UserTask(
            id: task.id,
            name: task.name,
            goal: task.goal,
            category: task.category,
            description: task.description,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            isCompleted: task.isCompleted,
            taskSchedule: task.taskSchedule,
            createdBy: task.createdBy,
            startDate: task.startDate,
            isActive: newActiveState
        )
        
        await updateTask(updatedTask)
        print("✅ [TaskManager] toggleTaskActive - Toggle complete for: \(task.name)")
    }
    
    func shareTask(_ task: UserTask) async -> (text: String, link: URL?) {
        // Create human-readable text
        var shareText = "✅ \(task.name)\n\n"
        
        if let goal = task.goal {
            shareText += "🎯 Goal: \(goal)\n"
        }
        if let category = task.category {
            shareText += "📂 Category: \(category)\n"
        }
        shareText += "📝 Description: \(task.description)\n\n"
        
        if let taskSchedule = task.taskSchedule, !taskSchedule.steps.isEmpty {
            shareText += "📋 Steps:\n"
            for (index, step) in taskSchedule.steps.enumerated() {
                let stepTitle = step.displayTitle
                shareText += "\(index + 1). \(stepTitle)"
                if let date = step.date {
                    shareText += " - \(date)"
                    if let time = step.time {
                        shareText += " at \(time)"
                    }
                }
                shareText += "\n"
            }
        }
        
        // Generate shareable link via backend
        var shareLink: URL?
        do {
            let response = try await CloudFunctionService.shared.createShareLink(type: "task", itemId: task.id)
            if let shareUrlString = response["shareUrl"] as? String,
               let url = URL(string: shareUrlString) {
                shareLink = url
                shareText += "\n\n🔗 Import Link:\n\(shareUrlString)"
            }
        } catch {
            print("❌ [TaskManager] Error creating share link: \(error.localizedDescription)")
            // Fallback to client-side link if backend fails
            shareLink = ShareLinkService.shared.generateTaskLink(task)
            if let link = shareLink {
                shareText += "\n\n🔗 Import Link:\n\(link.absoluteString)"
            }
        }
        
        return (text: shareText, link: shareLink)
    }
    
    // MARK: - Task Completion
    
    func toggleTaskCompletion(_ task: UserTask) async {
        let updatedTask = UserTask(
            id: task.id,
            name: task.name,
            goal: task.goal,
            category: task.category,
            description: task.description,
            createdAt: task.createdAt,
            completedAt: task.isCompleted ? nil : Date(),
            isCompleted: !task.isCompleted,
            taskSchedule: task.taskSchedule,
            createdBy: task.createdBy,
            startDate: task.startDate,
            isActive: task.isActive
        )
        
        await updateTask(updatedTask)
    }
    
    func toggleStepCompletion(_ task: UserTask, stepId: String) async {
        let updatedSteps = task.steps.map { step in
            if step.id == stepId {
                return TaskStep(
                    id: step.id,
                    index: step.index,
                    title: step.title,
                    description: step.description,
                    date: step.date,
                    time: step.time,
                    isCompleted: !step.isCompleted,
                    scheduledDate: step.scheduledDate,
                    reminders: step.reminders
                )
            }
            return step
        }
        
        let updatedTaskSchedule = TaskSchedule(steps: updatedSteps)
        
        let updatedTask = UserTask(
            id: task.id,
            name: task.name,
            goal: task.goal,
            category: task.category,
            description: task.description,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            isCompleted: task.isCompleted,
            taskSchedule: updatedTaskSchedule,
            createdBy: task.createdBy,
            startDate: task.startDate,
            isActive: task.isActive
        )
        
        await updateTask(updatedTask)
    }
    
    // MARK: - Statistics
    
    func getStats(for task: UserTask) -> TaskStats {
        let totalSteps = task.steps.count
        let completedSteps = task.steps.filter { $0.isCompleted }.count
        let completionRate = totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : 1.0
        let isCompleted = task.isCompleted || (totalSteps > 0 && completedSteps == totalSteps)
        
        return TaskStats(
            taskId: task.id,
            totalSteps: totalSteps,
            completedSteps: completedSteps,
            completionRate: completionRate,
            isCompleted: isCompleted,
            completedAt: task.completedAt
        )
    }
    
    // MARK: - Cleanup
    
    deinit {
        tasksListener?.remove()
    }
}
