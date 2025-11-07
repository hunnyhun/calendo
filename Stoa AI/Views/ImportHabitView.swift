import SwiftUI

struct ImportHabitView: View {
    let habit: ComprehensiveHabit
    @ObservedObject var habitManager: HabitManager
    let onDismiss: () -> Void
    
    @State private var isImporting = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Import Habit")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    // Habit preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text(habit.name)
                            .font(.headline)
                        
                        Text("Goal: \(habit.goal)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Category: \(habit.category)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(habit.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    Text("This habit will be added to your calendar. You can activate it after importing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Import Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        importHabit()
                    }
                    .disabled(isImporting)
                }
            }
        }
    }
    
    private func importHabit() {
        isImporting = true
        Task {
            await habitManager.createHabit(habit)
            // Record the import for analytics
            await ImportService.shared.recordImport()
            await MainActor.run {
                isImporting = false
                onDismiss()
            }
        }
    }
}

