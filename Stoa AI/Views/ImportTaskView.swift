import SwiftUI

struct ImportTaskView: View {
    let task: UserTask
    @ObservedObject var taskManager: TaskManager
    let onDismiss: () -> Void
    
    @State private var isImporting = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Import Task")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    // Task preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.name)
                            .font(.headline)
                        
                        if let goal = task.goal {
                            Text("Goal: \(goal)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let category = task.category {
                            Text("Category: \(category)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(task.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        if let taskSchedule = task.taskSchedule, !taskSchedule.steps.isEmpty {
                            Text("\(taskSchedule.steps.count) steps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    Text("This task will be added to your calendar. You can activate it after importing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Import Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        importTask()
                    }
                    .disabled(isImporting)
                }
            }
        }
    }
    
    private func importTask() {
        isImporting = true
        Task {
            await taskManager.createTask(task)
            // Record the import for analytics
            await ImportService.shared.recordImport()
            await MainActor.run {
                isImporting = false
                onDismiss()
            }
        }
    }
}

