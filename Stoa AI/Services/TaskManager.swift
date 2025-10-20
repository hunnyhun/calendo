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
    
    init() {}
    
    // Clear error state
    func clearError() {
        error = nil
    }
    
    // MARK: - Data Loading
    
    func loadTasks() async {
        guard Auth.auth().currentUser?.uid != nil else {
            print("❌ [TaskManager] No authenticated user")
            return
        }
        
        isLoading = true
        
        // Use backend function instead of direct Firestore
        _Concurrency.Task {
            do {
                let tasksData = try await CloudFunctionService.shared.getTasks()
                
                await MainActor.run {
                    do {
                        // Convert backend data to UserTask objects
                        self.tasks = try tasksData.compactMap { data in
                            let jsonData = try JSONSerialization.data(withJSONObject: data)
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .iso8601
                            return try decoder.decode(UserTask.self, from: jsonData)
                        }
                        print("✅ [TaskManager] Loaded \(self.tasks.count) tasks from backend")
                        self.error = nil
                    } catch {
                        print("❌ [TaskManager] Error parsing tasks from backend: \(error.localizedDescription)")
                        self.error = error.localizedDescription
                        self.tasks = []
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    print("❌ [TaskManager] Error loading tasks from backend: \(error.localizedDescription)")
                    self.error = error.localizedDescription
                    self.isLoading = false
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
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let taskData = try encoder.encode(task)
            let taskDict = try JSONSerialization.jsonObject(with: taskData) as! [String: Any]
            
            // Debug: Print what we're saving
            print("💾 [TaskManager] Saving task data: \(taskDict)")
            
            let _ = try await db.collection("users").document(userId).collection("tasks").addDocument(data: taskDict)
            print("✅ [TaskManager] Created task: \(task.name)")
            
        } catch {
            print("❌ [TaskManager] Error creating task: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func updateTask(_ task: UserTask) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Please sign in to update tasks"
            return
        }
        
        let taskId = task.id
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let taskData = try encoder.encode(task)
            let taskDict = try JSONSerialization.jsonObject(with: taskData) as! [String: Any]
            
            try await db.collection("users").document(userId).collection("tasks").document(taskId).setData(taskDict)
            print("✅ [TaskManager] Updated task: \(task.name)")
        } catch {
            print("❌ [TaskManager] Error updating task: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func deleteTask(_ task: UserTask) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Please sign in to delete tasks"
            return
        }
        
        let taskId = task.id
        
        do {
            try await db.collection("users").document(userId).collection("tasks").document(taskId).delete()
            print("✅ [TaskManager] Deleted task: \(task.name)")
        } catch {
            print("❌ [TaskManager] Error deleting task: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Task Completion
    
    func toggleTaskCompletion(_ task: UserTask) async {
        let updatedTask = UserTask(
            id: task.id,
            name: task.name,
            description: task.description,
            createdAt: task.createdAt,
            completedAt: task.isCompleted ? nil : Date(),
            isCompleted: !task.isCompleted,
            steps: task.steps,
            createdBy: task.createdBy,
            deadline: task.deadline,
            startDate: task.startDate
        )
        
        await updateTask(updatedTask)
    }
    
    func toggleStepCompletion(_ task: UserTask, stepId: String) async {
        let updatedSteps = task.steps.map { step in
            if step.id == stepId {
                return TaskStep(
                    id: step.id,
                    description: step.description,
                    isCompleted: !step.isCompleted,
                    scheduledDate: step.scheduledDate
                )
            }
            return step
        }
        
        let updatedTask = UserTask(
            id: task.id,
            name: task.name,
            description: task.description,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            isCompleted: task.isCompleted,
            steps: updatedSteps,
            createdBy: task.createdBy,
            deadline: task.deadline,
            startDate: task.startDate
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
