import SwiftUI

/// Card component that displays an AI-suggested task with a "Push it" button
struct TaskSuggestionCard: View {
    let task: UserTask
    let onPushToSchedule: () -> Void
    @State private var isExpanded = false
    @State private var isProcessing = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Break down complex expressions into computed properties
    private var headerSection: some View {
        HStack {
            taskTitleInfo
            Spacer()
            expandButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var taskTitleInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                Text(task.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            if !task.steps.isEmpty {
                Text("\(task.steps.count) steps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var expandButton: some View {
        Button(action: { 
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var expandableContent: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .padding(.horizontal, 16)
                
                detailsSection
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            descriptionSection
            stepsSection
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(task.description)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var stepsSection: some View {
        if !task.steps.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text("Steps (\(task.steps.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                stepsList
            }
        }
    }
    
    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(task.steps.prefix(3).enumerated()), id: \.offset) { _, step in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.caption)
                    
                    Text(step.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            if task.steps.count > 3 {
                Text("+ \(task.steps.count - 3) more steps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var pushButton: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)
            
            Button(action: {
                guard !isProcessing else { return }
                isProcessing = true
                onPushToSchedule()
                
                // Reset after a delay to prevent rapid tapping
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isProcessing = false
                }
            }) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                    
                    Text(isProcessing ? "Creating..." : "Push it")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isProcessing ? AnyView(Color.gray) : AnyView(buttonGradient))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private var buttonGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.blue,
                Color.blue.opacity(0.8)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 8,
                x: 0,
                y: 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color.blue.opacity(0.3),
                        lineWidth: 1
                    )
            )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            expandableContent
            pushButton
        }
        .background(cardBackground)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        TaskSuggestionCard(
            task: UserTask(
                name: "Plan Vacation",
                description: "Organize and plan a complete vacation trip",
                steps: [
                    TaskStep(description: "Research destinations and choose location"),
                    TaskStep(description: "Book flights and accommodation"),
                    TaskStep(description: "Create itinerary and activity list"),
                    TaskStep(description: "Pack bags and prepare for departure")
                ],
                createdBy: "preview"
            ),
            onPushToSchedule: {
                print("Push to schedule tapped")
            }
        )
        .padding()
        
        Spacer()
    }
    .background(Color(.systemBackground))
}
