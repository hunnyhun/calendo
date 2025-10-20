import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    @Published var calendarData: [Date: Models.CalendarDayData] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let habitManager = HabitManager.shared
    private let taskManager = TaskManager.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Load calendar data for a specific month
    func loadCalendarData(for month: Date) async {
        isLoading = true
        errorMessage = nil
        
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            isLoading = false
            return
        }
        
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let endOfMonth = calendar.dateInterval(of: .month, for: month)?.end ?? month
        
        // Load habit data for the month
        let habitData = await loadHabitData(from: startOfMonth, to: endOfMonth)
        
        // Load calendar notes for the month
        let notes = await loadCalendarNotes(from: startOfMonth, to: endOfMonth)
        
        // Ensure habits and tasks are loaded
        if habitManager.habits.isEmpty {
            await habitManager.loadHabits()
        }
        
        if taskManager.tasks.isEmpty {
            await taskManager.loadTasks()
        }
        
        // Load habits and tasks for schedule parsing
        let habits = habitManager.habits
        let tasks = taskManager.tasks
        
        print("📅 [CalendarManager] Loaded \(habits.count) habits and \(tasks.count) tasks")
        
        // Aggregate data for each day
        var aggregatedData: [Date: Models.CalendarDayData] = [:]
        
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                let dayHabits = habitData[date] ?? []
                let completedHabits = dayHabits.filter { $0.isCompleted }.count
                let totalHabits = dayHabits.count
                let note = notes[date]
                
                // Parse habit steps for this date
                let habitSteps = parseHabitStepsForDate(habits: habits, date: date)
                
                // Parse task items for this date
                let taskItems = parseTaskItemsForDate(tasks: tasks, date: date)
                
                // Debug logging for today's date
                if calendar.isDateInToday(date) {
                    print("📅 [CalendarManager] Today's data - Habits: \(habitSteps.count), Tasks: \(taskItems.count)")
                }
                
                aggregatedData[date] = Models.CalendarDayData(
                    date: date,
                    habitsCompleted: completedHabits,
                    totalHabits: totalHabits,
                    hasQuote: false, // TODO: Integrate with quote system
                    note: note,
                    habitSteps: habitSteps,
                    taskItems: taskItems
                )
            }
        }
        
        calendarData = aggregatedData
        isLoading = false
    }
    
    /// Save a calendar note for a specific date
    func saveCalendarNote(_ note: Models.CalendarNote) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateId = dateFormatter.string(from: note.date)
            
            try await db.collection("users")
                .document(userId)
                .collection("calendarNotes")
                .document(dateId)
                .setData([
                    "id": note.id,
                    "date": Timestamp(date: note.date),
                    "note": note.note,
                    "createdAt": Timestamp(date: note.createdAt),
                    "updatedAt": Timestamp(date: note.updatedAt)
                ])
            
            // Update local data
            if var dayData = calendarData[note.date] {
                dayData = Models.CalendarDayData(
                    date: dayData.date,
                    habitsCompleted: dayData.habitsCompleted,
                    totalHabits: dayData.totalHabits,
                    hasQuote: dayData.hasQuote,
                    note: note
                )
                calendarData[note.date] = dayData
            }
            
        } catch {
            errorMessage = "Failed to save note: \(error.localizedDescription)"
        }
    }
    
    /// Delete a calendar note for a specific date
    func deleteCalendarNote(for date: Date) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateId = dateFormatter.string(from: date)
            
            try await db.collection("users")
                .document(userId)
                .collection("calendarNotes")
                .document(dateId)
                .delete()
            
            // Update local data
            if var dayData = calendarData[date] {
                dayData = Models.CalendarDayData(
                    date: dayData.date,
                    habitsCompleted: dayData.habitsCompleted,
                    totalHabits: dayData.totalHabits,
                    hasQuote: dayData.hasQuote,
                    note: nil
                )
                calendarData[date] = dayData
            }
            
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
        }
    }
    
    /// Get calendar data for a specific date
    func getCalendarData(for date: Date) -> Models.CalendarDayData? {
        return calendarData[date]
    }
    
    // MARK: - Private Methods
    
    private func loadHabitData(from startDate: Date, to endDate: Date) async -> [Date: [HabitCompletion]] {
        // This would integrate with HabitManager to get habit completion data
        // For now, return empty data - this needs to be implemented based on HabitManager's structure
        return [:]
    }
    
    private func loadCalendarNotes(from startDate: Date, to endDate: Date) async -> [Date: Models.CalendarNote] {
        guard let userId = Auth.auth().currentUser?.uid else { return [:] }
        
        do {
            let startTimestamp = Timestamp(date: startDate)
            let endTimestamp = Timestamp(date: endDate)
            
            let querySnapshot = try await db.collection("users")
                .document(userId)
                .collection("calendarNotes")
                .whereField("date", isGreaterThanOrEqualTo: startTimestamp)
                .whereField("date", isLessThan: endTimestamp)
                .getDocuments()
            
            var notes: [Date: Models.CalendarNote] = [:]
            
            for document in querySnapshot.documents {
                let data = document.data()
                
                if let timestamp = data["date"] as? Timestamp,
                   let noteText = data["note"] as? String,
                   let id = data["id"] as? String,
                   let createdAt = data["createdAt"] as? Timestamp,
                   let updatedAt = data["updatedAt"] as? Timestamp {
                    
                    let date = timestamp.dateValue()
                    let note = Models.CalendarNote(
                        id: id,
                        date: date,
                        note: noteText
                    )
                    notes[date] = note
                }
            }
            
            return notes
            
        } catch {
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
            return [:]
        }
    }
    
    // MARK: - Habit Schedule Parsing
    
    /// Parse habit steps for a specific date
    private func parseHabitStepsForDate(habits: [ComprehensiveHabit], date: Date) -> [Models.CalendarHabitStep] {
        var steps: [Models.CalendarHabitStep] = []
        
        for habit in habits {
            // Parse low-level schedule (repetitive)
            if let lowLevelSchedule = habit.lowLevelSchedule {
                let scheduleSteps = parseLowLevelScheduleForDate(habit: habit, schedule: lowLevelSchedule, date: date)
                steps.append(contentsOf: scheduleSteps)
            }
            
            // Parse high-level schedule (progressive)
            if let highLevelSchedule = habit.highLevelSchedule {
                let scheduleSteps = parseHighLevelScheduleForDate(habit: habit, schedule: highLevelSchedule, date: date)
                steps.append(contentsOf: scheduleSteps)
            }
        }
        
        return steps
    }
    
    /// Parse low-level habit schedule for a specific date
    private func parseLowLevelScheduleForDate(habit: ComprehensiveHabit, schedule: HabitSchedule, date: Date) -> [Models.CalendarHabitStep] {
        var steps: [Models.CalendarHabitStep] = []
        let calendar = Calendar.current
        
        // Parse habit start date
        let habitStartDate: Date
        if let startDateString = habit.startDate {
            let formatter = ISO8601DateFormatter()
            habitStartDate = formatter.date(from: startDateString) ?? Date()
        } else {
            habitStartDate = Date()
        }
        
        // Check if date is after habit start date
        guard date >= habitStartDate else { return steps }
        
        switch schedule.span {
        case "daily":
            // Daily habits - check if any steps are scheduled for this day
            for program in schedule.program {
                for step in program.steps {
                    if let time = step.time {
                        // Create step for this time
                        let stepItem = Models.CalendarHabitStep(
                            habitId: habit.id,
                            habitName: habit.name,
                            stepDescription: step.instructions,
                            time: time,
                            isCompleted: false // TODO: Check completion status
                        )
                        steps.append(stepItem)
                    }
                }
            }
            
        case "weekly":
            // Weekly habits - check if this day matches the scheduled day
            let weekday = calendar.component(.weekday, from: date)
            for program in schedule.program {
                for step in program.steps {
                    if let day = step.day {
                        let stepWeekday = dayToWeekday(day)
                        if weekday == stepWeekday {
                            let stepItem = Models.CalendarHabitStep(
                                habitId: habit.id,
                                habitName: habit.name,
                                stepDescription: step.instructions,
                                time: step.time,
                                isCompleted: false
                            )
                            steps.append(stepItem)
                        }
                    }
                }
            }
            
        case "monthly":
            // Monthly habits - check if this day matches the scheduled day of month
            let dayOfMonth = calendar.component(.day, from: date)
            for program in schedule.program {
                for step in program.steps {
                    if let scheduledDay = step.dayOfMonth, dayOfMonth == scheduledDay {
                        let stepItem = Models.CalendarHabitStep(
                            habitId: habit.id,
                            habitName: habit.name,
                            stepDescription: step.instructions,
                            time: step.time,
                            isCompleted: false
                        )
                        steps.append(stepItem)
                    }
                }
            }
            
        default:
            break
        }
        
        return steps
    }
    
    /// Parse high-level habit schedule for a specific date
    private func parseHighLevelScheduleForDate(habit: ComprehensiveHabit, schedule: HabitHighLevelSchedule, date: Date) -> [Models.CalendarHabitStep] {
        var steps: [Models.CalendarHabitStep] = []
        let calendar = Calendar.current
        
        // Parse habit start date
        let habitStartDate: Date
        if let startDateString = habit.startDate {
            let formatter = ISO8601DateFormatter()
            habitStartDate = formatter.date(from: startDateString) ?? Date()
        } else {
            habitStartDate = Date()
        }
        
        // Check if date is after habit start date
        guard date >= habitStartDate else { return steps }
        
        // Calculate which week we're in since habit start
        let daysSinceStart = calendar.dateComponents([.day], from: habitStartDate, to: date).day ?? 0
        let currentWeek = (daysSinceStart / 7) + 1
        
        // Find the current phase based on duration
        var weekCounter = 1
        for phase in schedule.program {
            let phaseEndWeek = weekCounter + phase.durationWeeks - 1
            
            if currentWeek >= weekCounter && currentWeek <= phaseEndWeek {
                // This phase is active, add its steps
                for step in phase.steps {
                    let stepItem = Models.CalendarHabitStep(
                        habitId: habit.id,
                        habitName: habit.name,
                        stepDescription: step.instructions,
                        time: nil, // High-level schedule doesn't specify times
                        isCompleted: false
                    )
                    steps.append(stepItem)
                }
                break
            }
            
            weekCounter += phase.durationWeeks
        }
        
        return steps
    }
    
    // MARK: - Task Schedule Parsing
    
    /// Parse task items for a specific date
    private func parseTaskItemsForDate(tasks: [UserTask], date: Date) -> [Models.CalendarTaskItem] {
        var items: [Models.CalendarTaskItem] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        
        for task in tasks {
            // Skip completed tasks
            guard !task.isCompleted else { continue }
            
            // Check for deadline
            if let deadline = task.deadline {
                let deadlineDate = calendar.startOfDay(for: deadline)
                if deadlineDate == targetDate {
                    let daysRemaining = calendar.dateComponents([.day], from: today, to: deadline).day ?? 0
                    let deadlineItem = Models.CalendarTaskItem(
                        taskId: task.id,
                        taskName: task.name,
                        itemType: .deadline,
                        description: "Deadline: \(task.name)",
                        daysRemaining: max(0, daysRemaining),
                        scheduledDate: deadline,
                        isCompleted: false
                    )
                    items.append(deadlineItem)
                }
            }
            
            // Check for scheduled steps
            for step in task.steps {
                if let scheduledDate = step.scheduledDate {
                    let stepDate = calendar.startOfDay(for: scheduledDate)
                    if stepDate == targetDate {
                        let stepItem = Models.CalendarTaskItem(
                            taskId: task.id,
                            taskName: task.name,
                            itemType: .scheduledStep,
                            description: step.description,
                            daysRemaining: nil,
                            scheduledDate: scheduledDate,
                            isCompleted: step.isCompleted
                        )
                        items.append(stepItem)
                    }
                }
            }
            
            // If today, include current incomplete step
            if targetDate == today {
                let incompleteSteps = task.steps.filter { !$0.isCompleted }
                if let currentStep = incompleteSteps.first {
                    let currentStepItem = Models.CalendarTaskItem(
                        taskId: task.id,
                        taskName: task.name,
                        itemType: .currentStep,
                        description: currentStep.description,
                        daysRemaining: nil,
                        scheduledDate: nil,
                        isCompleted: false
                    )
                    items.append(currentStepItem)
                }
            }
        }
        
        return items
    }
    
    // MARK: - Helper Methods
    
    /// Convert day string to weekday number (1 = Sunday, 2 = Monday, etc.)
    private func dayToWeekday(_ day: String) -> Int {
        switch day.lowercased() {
        case "sunday", "sun": return 1
        case "monday", "mon": return 2
        case "tuesday", "tue": return 3
        case "wednesday", "wed": return 4
        case "thursday", "thu": return 5
        case "friday", "fri": return 6
        case "saturday", "sat": return 7
        default: return 1
        }
    }
    
    // MARK: - Completion Handlers
    
    /// Complete a habit step for a specific date
    func completeHabitStep(habitId: String, date: Date) async {
        // Create habit entry via HabitManager
        let entry = HabitEntry(
            habitId: habitId,
            completedAt: date,
            createdBy: Auth.auth().currentUser?.uid ?? ""
        )
        
        // TODO: Implement habit entry creation in HabitManager
        // await habitManager.createHabitEntry(entry)
        
        // Refresh calendar data
        await loadCalendarData(for: date)
    }
    
    /// Complete a task step
    func completeTaskStep(taskId: String, stepId: String) async {
        // Find the task and toggle step completion
        if let task = taskManager.tasks.first(where: { $0.id == taskId }) {
            await taskManager.toggleStepCompletion(task, stepId: stepId)
            
            // Refresh calendar data
            let today = Date()
            await loadCalendarData(for: today)
        }
    }
}

// MARK: - Helper Models

struct HabitCompletion {
    let habitId: String
    let date: Date
    let isCompleted: Bool
}
