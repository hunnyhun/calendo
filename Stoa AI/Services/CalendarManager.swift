import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    @Published var calendarData: [Date: Models.CalendarDayData] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let habitManager = HabitManager.shared
    private let taskManager = TaskManager.shared
    private let mappingService = HabitMappingService.shared
    
    // Cache for habit mappings to avoid recalculating multiple times
    // Key: habitId, Value: [Date: HabitCardData] - mappings for all dates
    private var habitMappingsCache: [String: [Date: HabitCardData]] = [:]
    
    // Cache for task mappings to avoid recalculating multiple times
    // Key: taskId, Value: [Date: [Models.CalendarTaskItem]] - mappings for all dates
    private var taskMappingsCache: [String: [Date: [Models.CalendarTaskItem]]] = [:]
    
    private var cacheDateRange: (start: Date, end: Date)?
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownHabitCount = 0
    private var lastKnownHabitIds: Set<String> = []
    
    private init() {
        // Observe changes to habits to invalidate cache when habits are added/updated/deleted
        // Since both CalendarManager and HabitManager are @MainActor, the publisher will emit on main thread
        habitManager.$habits
            .dropFirst() // Skip the initial value to avoid invalidating on initialization
            .sink { [weak self] habits in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    await self?.handleHabitsChanged(newHabits: habits)
                }
            }
            .store(in: &cancellables)
        
        // Initialize last known state
        lastKnownHabitCount = habitManager.habits.count
        lastKnownHabitIds = Set(habitManager.habits.map { $0.id })
    }
    
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
        
        // Get all days that will be displayed in the calendar (includes adjacent month days)
        let displayedDays = getDisplayedDaysForMonth(month, calendar: calendar)
        
        // Calculate date range for caching
        let minDate = displayedDays.min() ?? startOfMonth
        let maxDate = displayedDays.max() ?? endOfMonth
        
        // Pre-calculate all habit mappings once for the date range
        // This avoids recalculating mappings for each date
        precalculateHabitMappings(habits: habits, dateRange: (minDate, maxDate))
        
        // Pre-calculate all task mappings once for the date range
        // This avoids recalculating mappings for each date
        precalculateTaskMappings(tasks: tasks, dateRange: (minDate, maxDate))
        
        // Aggregate data for each day
        var aggregatedData: [Date: Models.CalendarDayData] = [:]
        
        for date in displayedDays {
            // Normalize date to start of day for consistent dictionary keys
            let normalizedDate = calendar.startOfDay(for: date)
            
            let dayHabits = habitData[normalizedDate] ?? []
            let completedHabits = dayHabits.filter { $0.isCompleted }.count
            let totalHabits = dayHabits.count
            let note = notes[normalizedDate]
            
            // Parse habit steps for this date
            let habitSteps = parseHabitStepsForDate(habits: habits, date: normalizedDate)
            
            // Parse task items for this date
            let taskItems = parseTaskItemsForDate(tasks: tasks, date: normalizedDate)
            
            // Debug logging for today's date
            if calendar.isDateInToday(normalizedDate) {
                print("📅 [CalendarManager] Today's data - Habits: \(habitSteps.count), Tasks: \(taskItems.count)")
                print("📅 [CalendarManager] Storing today's data with normalized date: \(normalizedDate)")
            }
            
            aggregatedData[normalizedDate] = Models.CalendarDayData(
                date: normalizedDate,
                habitsCompleted: completedHabits,
                totalHabits: totalHabits,
                hasQuote: false, // TODO: Integrate with quote system
                note: note,
                habitSteps: habitSteps,
                taskItems: taskItems
            )
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
        // Normalize date to start of day for consistent lookup
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        
        // Try exact match first
        if let data = calendarData[normalizedDate] {
            return data
        }
        
        // If not found, search for any matching date (in case of timezone issues)
        for (key, value) in calendarData {
            if calendar.isDate(key, inSameDayAs: normalizedDate) {
                return value
            }
        }
        
        print("📅 [CalendarManager] No calendar data found for date: \(normalizedDate)")
        return nil
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
                   let id = data["id"] as? String {
                    
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
    
    /// Pre-calculate all habit mappings for a date range to avoid recalculating for each date
    private func precalculateHabitMappings(habits: [ComprehensiveHabit], dateRange: (start: Date, end: Date)) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: dateRange.start)
        let normalizedEnd = calendar.startOfDay(for: dateRange.end)
        
        // Check if cache is still valid for this date range
        if let cachedRange = cacheDateRange,
           cachedRange.start <= normalizedStart && cachedRange.end >= normalizedEnd {
            // Cache is still valid, no need to recalculate
            print("📅 [CalendarManager] Using cached habit mappings")
            return
        }
        
        print("📅 [CalendarManager] Pre-calculating habit mappings for \(habits.count) habits")
        let startTime = Date()
        
        // Clear old cache
        habitMappingsCache.removeAll()
        
        // Calculate mappings for each habit
        for habit in habits {
            // Use startDate from habit (when user pushed to calendar)
            // Fallback to createdAt (when AI created it) if startDate is not set
            // Final fallback to current date
            let startDate: Date
            if let startDateString = habit.startDate {
                startDate = parseCreatedAtDate(startDateString)
            } else if let createdAtString = habit.createdAt {
                startDate = parseCreatedAtDate(createdAtString)
            } else {
                // Fallback: use first entry date or current date
                startDate = habitManager.entries
                    .filter { $0.habitId == habit.id }
                    .min(by: { $0.completedAt < $1.completedAt })?.completedAt ?? Date()
            }
            
            // Convert habit to NewHabitJSON format for mapping service
            let newHabitJson = convertToNewHabitJSON(habit)
            
            // Get combined mappings for daily view (shows all content)
            // This calculates mappings for all dates at once
            let combinedMappings = mappingService.combineForDailyView(habit: newHabitJson, startDate: startDate)
            
            // Store in cache
            habitMappingsCache[habit.id] = combinedMappings
        }
        
        // Update cache date range
        cacheDateRange = (normalizedStart, normalizedEnd)
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("📅 [CalendarManager] Pre-calculated mappings in \(String(format: "%.2f", elapsed))s")
    }
    
    /// Parse habit steps for a specific date using cached mappings
    private func parseHabitStepsForDate(habits: [ComprehensiveHabit], date: Date) -> [Models.CalendarHabitStep] {
        var steps: [Models.CalendarHabitStep] = []
        
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        
        // Use cached mappings instead of recalculating
        for habit in habits {
            // Get cached mappings for this habit
            guard let cachedMappings = habitMappingsCache[habit.id] else {
                continue
            }
            
            // Check if this date has content in cached mappings
            if let cardData = cachedMappings[normalizedDate] {
                // Convert HabitCardData to CalendarHabitStep
                for step in cardData.steps {
                    let isCompleted = checkStepCompletion(habitId: habit.id, stepId: step.step, date: normalizedDate)
                    
                    let stepItem = Models.CalendarHabitStep(
                        habitId: habit.id,
                        habitName: habit.name,
                        stepDescription: step.step,
                        time: step.clock,
                        isCompleted: isCompleted,
                        stepId: step.step, // Use step text as ID
                        difficulty: nil,
                        durationMinutes: nil,
                        feedback: nil,
                        title: cardData.title
                    )
                    steps.append(stepItem)
                }
            }
        }
        
        return steps
    }
    
    /// Convert ComprehensiveHabit to NewHabitJSON format for mapping service
    private func convertToNewHabitJSON(_ habit: ComprehensiveHabit) -> NewHabitJSON {
        // Convert low-level schedule
        let lowLevelSchedule = LowLevelScheduleNew(
            span: habit.lowLevelSchedule.span,
            spanValue: habit.lowLevelSchedule.spanValue,
            habitSchedule: habit.lowLevelSchedule.habitSchedule,
            habitRepeatCount: habit.lowLevelSchedule.habitRepeatCount,
            program: habit.lowLevelSchedule.program.map { program in
                ProgramNew(
                    daysIndexed: program.daysIndexed,
                    weeksIndexed: program.weeksIndexed,
                    monthsIndexed: program.monthsIndexed
                )
            }
        )
        
        // Convert high-level schedule
        let highLevelSchedule: HighLevelScheduleNew? = nil // HighLevelScheduleNew is empty in new structure
        
        return NewHabitJSON(
            id: habit.id,
            name: habit.name,
            goal: habit.goal,
            category: habit.category,
            description: habit.description,
            difficulty: habit.difficulty,
            highLevelSchedule: highLevelSchedule,
            lowLevelSchedule: lowLevelSchedule
        )
    }
    
    // MARK: - Old parsing methods (removed - now using HabitMappingService)
    // The following methods are kept for reference but are no longer used
    
    /// Parse low-level habit schedule for a specific date (DEPRECATED - use HabitMappingService)
    private func parseLowLevelScheduleForDate_DEPRECATED(habit: ComprehensiveHabit, schedule: HabitSchedule, date: Date) -> [Models.CalendarHabitStep] {
        var steps: [Models.CalendarHabitStep] = []
        let calendar = Calendar.current
        
        // Use first entry date as start date (or current date if no entries)
        let habitStartDate = habitManager.entries
            .filter { $0.habitId == habit.id }
            .min(by: { $0.completedAt < $1.completedAt })?.completedAt ?? Date()
        
        // Normalize dates to start of day for comparison
        let startOfHabitDate = calendar.startOfDay(for: habitStartDate)
        let startOfTargetDate = calendar.startOfDay(for: date)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        print("📅 [CalendarManager] Comparing dates - Start: \(dateFormatter.string(from: startOfHabitDate)), Target: \(dateFormatter.string(from: startOfTargetDate))")
        
        // Check if date is after habit start date
        guard startOfTargetDate >= startOfHabitDate else {
            print("📅 [CalendarManager] Date \(dateFormatter.string(from: startOfTargetDate)) is before habit start date \(dateFormatter.string(from: startOfHabitDate)) for habit '\(habit.name)'")
            return steps
        }
        
        // Check habitRepeatCount if specified (null = infinite, number = limited repetitions)
        if let habitRepeatCount = schedule.habitRepeatCount {
            let repetitions = calculateRepetitions(schedule: schedule, from: startOfHabitDate, to: startOfTargetDate)
            if Double(repetitions) > habitRepeatCount {
                return steps // Exceeded repetition limit
            }
        }
        
        // Check if this date matches the schedule
        let matchesSchedule = checkDateMatchesSchedule(schedule: schedule, date: startOfTargetDate, startDate: startOfHabitDate, calendar: calendar)
        guard matchesSchedule else {
            print("📅 [CalendarManager] Date \(startOfTargetDate) does not match schedule '\(schedule.span)' for habit '\(habit.name)'")
            return steps
        }
        
        print("📅 [CalendarManager] Date \(startOfTargetDate) matches schedule '\(schedule.span)' for habit '\(habit.name)'")
        
        // This method is deprecated - use HabitMappingService instead
        // The new structure uses daysIndexed, weeksIndexed, monthsIndexed instead of steps
        return steps
    }
    
    /// Check if a date matches the schedule span criteria (DEPRECATED - use HabitMappingService)
    private func checkDateMatchesSchedule(schedule: HabitSchedule, date: Date, startDate: Date, calendar: Calendar) -> Bool {
        // Date must be on or after the start date
        guard date >= startDate else { return false }
        
        switch schedule.span {
        case "day":
            // For day span, check spanValue
            if schedule.spanValue == 1.0 {
                return true // Daily
            } else {
                // Every N days
                let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
                let intervalDays = Int(schedule.spanValue)
                return daysSinceStart >= 0 && daysSinceStart % intervalDays == 0
            }
            
        case "week":
            // Weekly habits - check if same weekday as start date
            let weekday = calendar.component(.weekday, from: date)
            let startWeekday = calendar.component(.weekday, from: startDate)
            if schedule.spanValue == 1.0 {
                return weekday == startWeekday
            } else {
                // Every N weeks - check week interval
                guard let startOfStartWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start,
                      let startOfDateWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
                    return false
                }
                let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: startOfStartWeek, to: startOfDateWeek).weekOfYear ?? 0
                let intervalWeeks = Int(schedule.spanValue)
                return weeksSinceStart >= 0 && weeksSinceStart % intervalWeeks == 0 && weekday == startWeekday
            }
            
        case "every-n-weeks":
            // Get interval and calculate weeks properly using week boundaries
            guard let intervalDays = getIntervalDays(from: schedule), intervalDays > 0 else {
                return false
            }
            let intervalWeeks = max(1, intervalDays / 7)
            
            // Check if date falls on the same weekday as start date
            let startWeekday = calendar.component(.weekday, from: startDate)
            let dateWeekday = calendar.component(.weekday, from: date)
            guard startWeekday == dateWeekday else { return false }
            
            // Calculate which week of the interval we're in
            guard let startOfStartWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start,
                  let startOfDateWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
                return false
            }
            
            let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: startOfStartWeek, to: startOfDateWeek).weekOfYear ?? 0
            return weeksSinceStart >= 0 && weeksSinceStart % intervalWeeks == 0
            
        case "month":
            // Monthly habits - check if same day of month as start date
            let dayOfMonth = calendar.component(.day, from: date)
            let startDayOfMonth = calendar.component(.day, from: startDate)
            if schedule.spanValue == 1.0 {
                return dayOfMonth == startDayOfMonth
            } else {
                // Every N months - check month interval
                let monthsSinceStart = calendar.dateComponents([.month], from: startDate, to: date).month ?? 0
                let intervalMonths = Int(schedule.spanValue)
                return monthsSinceStart >= 0 && monthsSinceStart % intervalMonths == 0 && dayOfMonth == startDayOfMonth
            }
            
        case "every-n-months":
            // Calculate months difference properly
            guard let intervalDays = getIntervalDays(from: schedule), intervalDays > 0 else {
                return false
            }
            
            // Check if date is on the same day of month as start date
            let startDayOfMonth = calendar.component(.day, from: startDate)
            let dateDayOfMonth = calendar.component(.day, from: date)
            guard startDayOfMonth == dateDayOfMonth else { return false }
            
            // Calculate months since start
            let monthsSinceStart = calendar.dateComponents([.month], from: startDate, to: date).month ?? 0
            guard monthsSinceStart >= 0 else { return false }
            
            // Calculate interval in months (more accurate than dividing days)
            let intervalMonths = max(1, Int(round(Double(intervalDays) / 30.0)))
            return monthsSinceStart % intervalMonths == 0
            
        case "year":
            // Yearly habits - check if same day of year as start date
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
            let startDayOfYear = calendar.ordinality(of: .day, in: .year, for: startDate) ?? 0
            return dayOfYear == startDayOfYear
            
        default:
            return false
        }
    }
    
    /// Extract interval days from schedule (helper method - DEPRECATED)
    private func getIntervalDays(from schedule: HabitSchedule) -> Int? {
        // Use spanValue instead
        if schedule.span == "day" && schedule.spanValue > 1.0 {
            return Int(schedule.spanValue)
        }
        return nil
    }
    
    /// Calculate number of repetitions since start date
    /// Used to check if spanInterval limit has been exceeded
    private func calculateRepetitions(schedule: HabitSchedule, from startDate: Date, to endDate: Date) -> Int {
        let calendar = Calendar.current
        
        switch schedule.span {
        case "daily":
            let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            return max(0, daysSinceStart + 1) // +1 because start date is day 0
            
        case "every-n-days":
            guard let intervalDays = getIntervalDays(from: schedule), intervalDays > 0 else {
                return 0
            }
            let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            guard daysSinceStart >= 0 else { return 0 }
            return (daysSinceStart / intervalDays) + 1 // +1 because start date counts as repetition 0
            
        case "weekly":
            // Count actual weeks between dates
            guard let startOfStartWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start,
                  let startOfEndWeek = calendar.dateInterval(of: .weekOfYear, for: endDate)?.start else {
                return 0
            }
            let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: startOfStartWeek, to: startOfEndWeek).weekOfYear ?? 0
            return max(0, weeksSinceStart + 1)
            
        case "every-n-weeks":
            guard let intervalDays = getIntervalDays(from: schedule), intervalDays > 0 else {
                return 0
            }
            let intervalWeeks = max(1, intervalDays / 7)
            guard let startOfStartWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start,
                  let startOfEndWeek = calendar.dateInterval(of: .weekOfYear, for: endDate)?.start else {
                return 0
            }
            let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: startOfStartWeek, to: startOfEndWeek).weekOfYear ?? 0
            guard weeksSinceStart >= 0 else { return 0 }
            return (weeksSinceStart / intervalWeeks) + 1
            
        case "monthly":
            let monthsSinceStart = calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 0
            return max(0, monthsSinceStart + 1)
            
        case "every-n-months":
            guard let intervalDays = getIntervalDays(from: schedule), intervalDays > 0 else {
                return 0
            }
            let intervalMonths = max(1, Int(round(Double(intervalDays) / 30.0)))
            let monthsSinceStart = calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 0
            guard monthsSinceStart >= 0 else { return 0 }
            return (monthsSinceStart / intervalMonths) + 1
            
        case "yearly":
            let yearsSinceStart = calendar.dateComponents([.year], from: startDate, to: endDate).year ?? 0
            return max(0, yearsSinceStart + 1)
            
        default:
            return 0
        }
    }
    
    /// Check if a step is completed for a specific date
    private func checkStepCompletion(habitId: String, stepId: String, date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        // Check if there's a completion entry for this habit on this date
        return habitManager.entries.contains { entry in
            entry.habitId == habitId &&
            entry.completedAt >= startOfDay &&
            entry.completedAt < endOfDay
        }
    }
    
    /// Parse high-level habit schedule for a specific date (DEPRECATED - use HabitMappingService)
    /// High-level schedule now only contains milestones, not program steps
    private func parseHighLevelScheduleForDate(habit: ComprehensiveHabit, schedule: HabitHighLevelSchedule, date: Date) -> [Models.CalendarHabitStep] {
        // High-level schedule in new structure only has milestones, not program steps
        // Use low-level schedule for actual step content
        return []
    }
    
    // MARK: - Task Schedule Parsing
    
    /// Pre-calculate all task mappings for a date range to avoid recalculating for each date
    private func precalculateTaskMappings(tasks: [UserTask], dateRange: (start: Date, end: Date)) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: dateRange.start)
        let normalizedEnd = calendar.startOfDay(for: dateRange.end)
        
        print("📅 [CalendarManager] Pre-calculating task mappings for \(tasks.count) tasks")
        let startTime = Date()
        
        // Clear old cache
        taskMappingsCache.removeAll()
        
        // Calculate mappings for each task
        for task in tasks {
            // Skip completed tasks
            guard !task.isCompleted else { continue }
            
            // Get combined mappings for daily view (shows all content)
            let combinedMappings = combineTaskMappingsForDailyView(task: task, dateRange: (normalizedStart, normalizedEnd))
            
            // Store in cache
            taskMappingsCache[task.id] = combinedMappings
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("📅 [CalendarManager] Pre-calculated task mappings in \(String(format: "%.2f", elapsed))s")
    }
    
    /// Daily task mapping - maps steps with exact dates to their specific days
    private func dailyTaskMapping(task: UserTask, dateRange: (start: Date, end: Date)) -> [Date: [Models.CalendarTaskItem]] {
        var result: [Date: [Models.CalendarTaskItem]] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for step in task.steps {
            guard !step.isCompleted else { continue }
            
            // Parse step date if available
            var stepDateValue: Date?
            if let dateString = step.date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                stepDateValue = formatter.date(from: dateString)
                
                // Add time if available
                if let timeString = step.time, let baseDate = stepDateValue {
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "HH:mm"
                    if let timeValue = timeFormatter.date(from: timeString) {
                        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeValue)
                        stepDateValue = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: baseDate)
                    }
                }
            } else {
                stepDateValue = step.scheduledDate
            }
            
            if let scheduledDate = stepDateValue {
                let stepDate = calendar.startOfDay(for: scheduledDate)
                
                // Only include if within date range
                if stepDate >= dateRange.start && stepDate <= dateRange.end {
                    let stepItem = Models.CalendarTaskItem(
                        taskId: task.id,
                        taskName: task.name,
                        itemType: .scheduledStep,
                        description: step.displayTitle,
                        daysRemaining: nil,
                        scheduledDate: scheduledDate,
                        isCompleted: step.isCompleted
                    )
                    
                    if result[stepDate] == nil {
                        result[stepDate] = []
                    }
                    result[stepDate]?.append(stepItem)
                }
            }
        }
        
        // For today, include current incomplete step (only for steps without dates)
        if today >= dateRange.start && today <= dateRange.end {
            let incompleteSteps = task.steps.filter { !$0.isCompleted && $0.date == nil }
            if let currentStep = incompleteSteps.first {
                let currentStepItem = Models.CalendarTaskItem(
                    taskId: task.id,
                    taskName: task.name,
                    itemType: .currentStep,
                    description: currentStep.displayTitle,
                    daysRemaining: nil,
                    scheduledDate: nil,
                        isCompleted: false
                    )
                
                if result[today] == nil {
                    result[today] = []
                }
                result[today]?.append(currentStepItem)
                }
            }
            
        return result
    }
    
    /// Weekly task mapping - maps steps to their week (shows steps that fall within each week)
    private func weeklyTaskMapping(task: UserTask, dateRange: (start: Date, end: Date)) -> [Date: [Models.CalendarTaskItem]] {
        var result: [Date: [Models.CalendarTaskItem]] = [:]
        let calendar = Calendar.current
        
            for step in task.steps {
            guard !step.isCompleted else { continue }
            
            // Parse step date if available
            var stepDateValue: Date?
            if let dateString = step.date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                stepDateValue = formatter.date(from: dateString)
                
                if let timeString = step.time, let baseDate = stepDateValue {
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "HH:mm"
                    if let timeValue = timeFormatter.date(from: timeString) {
                        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeValue)
                        stepDateValue = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: baseDate)
                    }
                }
            } else {
                stepDateValue = step.scheduledDate
            }
            
            if let scheduledDate = stepDateValue {
                // Get the start of the week for this step
                guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: scheduledDate)?.start else { continue }
                let weekStartNormalized = calendar.startOfDay(for: weekStart)
                
                // Only include if week start is within date range
                if weekStartNormalized >= dateRange.start && weekStartNormalized <= dateRange.end {
                    let stepItem = Models.CalendarTaskItem(
                        taskId: task.id,
                        taskName: task.name,
                        itemType: .scheduledStep,
                        description: step.displayTitle,
                        daysRemaining: nil,
                        scheduledDate: scheduledDate,
                        isCompleted: step.isCompleted
                    )
                    
                    if result[weekStartNormalized] == nil {
                        result[weekStartNormalized] = []
                    }
                    result[weekStartNormalized]?.append(stepItem)
                }
            }
        }
        
        return result
    }
    
    /// Monthly task mapping - maps steps to their month (shows steps that fall within each month)
    private func monthlyTaskMapping(task: UserTask, dateRange: (start: Date, end: Date)) -> [Date: [Models.CalendarTaskItem]] {
        var result: [Date: [Models.CalendarTaskItem]] = [:]
        let calendar = Calendar.current
        
        for step in task.steps {
            guard !step.isCompleted else { continue }
            
            // Parse step date if available
            var stepDateValue: Date?
            if let dateString = step.date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                stepDateValue = formatter.date(from: dateString)
                
                if let timeString = step.time, let baseDate = stepDateValue {
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "HH:mm"
                    if let timeValue = timeFormatter.date(from: timeString) {
                        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeValue)
                        stepDateValue = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: baseDate)
                    }
                }
            } else {
                stepDateValue = step.scheduledDate
            }
            
            if let scheduledDate = stepDateValue {
                // Get the start of the month for this step
                guard let monthStart = calendar.dateInterval(of: .month, for: scheduledDate)?.start else { continue }
                let monthStartNormalized = calendar.startOfDay(for: monthStart)
                
                // Only include if month start is within date range
                if monthStartNormalized >= dateRange.start && monthStartNormalized <= dateRange.end {
                    let stepItem = Models.CalendarTaskItem(
                        taskId: task.id,
                        taskName: task.name,
                        itemType: .scheduledStep,
                        description: step.displayTitle,
                        daysRemaining: nil,
                        scheduledDate: scheduledDate,
                        isCompleted: step.isCompleted
                    )
                    
                    if result[monthStartNormalized] == nil {
                        result[monthStartNormalized] = []
                    }
                    result[monthStartNormalized]?.append(stepItem)
                }
            }
        }
        
        return result
    }
    
    /// Combine task mappings for daily view - combines daily, weekly, and monthly mappings
    private func combineTaskMappingsForDailyView(task: UserTask, dateRange: (start: Date, end: Date)) -> [Date: [Models.CalendarTaskItem]] {
        var combinedResult: [Date: [Models.CalendarTaskItem]] = [:]
        
        // Get results from all mapping functions
        let dailyResults = dailyTaskMapping(task: task, dateRange: dateRange)
        let weeklyResults = weeklyTaskMapping(task: task, dateRange: dateRange)
        let monthlyResults = monthlyTaskMapping(task: task, dateRange: dateRange)
        
        // Collect all unique dates from all sources
        var allDates = Set(dailyResults.keys)
        allDates = allDates.union(Set(weeklyResults.keys))
        allDates = allDates.union(Set(monthlyResults.keys))
        
        // For each date, combine items from all sources
        for date in allDates {
            var combinedItems: [Models.CalendarTaskItem] = []
            
            // Add daily items
            if let dailyItems = dailyResults[date] {
                combinedItems.append(contentsOf: dailyItems)
            }
            
            // Add weekly items
            if let weeklyItems = weeklyResults[date] {
                combinedItems.append(contentsOf: weeklyItems)
            }
            
            // Add monthly items
            if let monthlyItems = monthlyResults[date] {
                combinedItems.append(contentsOf: monthlyItems)
            }
            
            // Remove duplicates (same taskId, itemType, and description)
            var uniqueItems: [Models.CalendarTaskItem] = []
            var seenItems: Set<String> = []
            for item in combinedItems {
                let key = "\(item.taskId)|\(item.itemType.rawValue)|\(item.description)"
                if !seenItems.contains(key) {
                    seenItems.insert(key)
                    uniqueItems.append(item)
                }
            }
            
            combinedResult[date] = uniqueItems
        }
        
        return combinedResult
    }
    
    /// Parse task items for a specific date using cached mappings
    private func parseTaskItemsForDate(tasks: [UserTask], date: Date) -> [Models.CalendarTaskItem] {
        var items: [Models.CalendarTaskItem] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        
        for task in tasks {
            // Skip completed tasks
            guard !task.isCompleted else { continue }
            
            // Use cached mappings if available
            if let cachedItems = taskMappingsCache[task.id]?[targetDate] {
                items.append(contentsOf: cachedItems)
            } else {
                // Fallback to direct parsing if cache miss
                // Check for scheduled steps (new structure with date field)
                for step in task.steps {
                    // Use date from new structure, fallback to scheduledDate for backward compatibility
                    var stepDateValue: Date?
                    if let dateString = step.date {
                        // Parse YYYY-MM-DD format
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.timeZone = TimeZone.current
                        stepDateValue = formatter.date(from: dateString)
                        
                        // Add time if available
                        if let timeString = step.time, let baseDate = stepDateValue {
                            let timeFormatter = DateFormatter()
                            timeFormatter.dateFormat = "HH:mm"
                            if let timeValue = timeFormatter.date(from: timeString) {
                                let timeComponents = calendar.dateComponents([.hour, .minute], from: timeValue)
                                stepDateValue = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: baseDate)
                            }
                        }
                    } else {
                        // Fallback to scheduledDate for legacy tasks
                        stepDateValue = step.scheduledDate
                    }
                    
                    if let scheduledDate = stepDateValue {
                    let stepDate = calendar.startOfDay(for: scheduledDate)
                    if stepDate == targetDate {
                            let stepDescription = step.displayTitle
                        let stepItem = Models.CalendarTaskItem(
                            taskId: task.id,
                            taskName: task.name,
                            itemType: .scheduledStep,
                                description: stepDescription,
                            daysRemaining: nil,
                            scheduledDate: scheduledDate,
                            isCompleted: step.isCompleted
                        )
                        items.append(stepItem)
                    }
                }
            }
            
                // If today, include current incomplete step (only for steps without dates)
            if targetDate == today {
                    let incompleteSteps = task.steps.filter { !$0.isCompleted && $0.date == nil }
                if let currentStep = incompleteSteps.first {
                    let currentStepItem = Models.CalendarTaskItem(
                        taskId: task.id,
                        taskName: task.name,
                        itemType: .currentStep,
                            description: currentStep.displayTitle,
                        daysRemaining: nil,
                        scheduledDate: nil,
                        isCompleted: false
                    )
                    items.append(currentStepItem)
                    }
                }
            }
        }
        
        return items
    }
    
    // MARK: - Helper Methods
    
    /// Get all days that should be displayed for a month (includes adjacent month days for calendar grid)
    private func getDisplayedDaysForMonth(_ month: Date, calendar: Calendar) -> [Date] {
        let startOfMonth = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let endOfMonth = calendar.dateInterval(of: .month, for: month)?.end ?? month
        var days: [Date] = []
        
        // Add days from previous month to fill the first week
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let daysToAdd = (firstWeekday + 5) % 7 // Convert to Monday = 0 format
        
        if daysToAdd > 0 {
            for i in (1...daysToAdd).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: startOfMonth) {
                    days.append(date)
                }
            }
        }
        
        // Add days of current month
        var currentDate = startOfMonth
        while currentDate < endOfMonth {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        // Add days from next month to complete the last week
        let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: endOfMonth) ?? endOfMonth
        let lastWeekday = calendar.component(.weekday, from: lastDayOfMonth)
        let daysToCompleteLastWeek = (8 - lastWeekday) % 7
        
        if daysToCompleteLastWeek > 0 {
            for i in 1...daysToCompleteLastWeek {
                if let date = calendar.date(byAdding: .day, value: i, to: lastDayOfMonth) {
                    days.append(date)
                }
            }
        }
        
        return days
    }
    
    /// Parse createdAt date string (ISO 8601 format) to Date
    private func parseCreatedAtDate(_ dateString: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Final fallback: return today if parsing fails
        return Date()
    }
    
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
        // Find the habit
        guard let habit = habitManager.habits.first(where: { $0.id == habitId }) else {
            errorMessage = "Habit not found"
            return
        }
        
        // Check if already completed today
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        let alreadyCompleted = habitManager.entries.contains { entry in
            entry.habitId == habitId &&
            entry.completedAt >= startOfDay &&
            entry.completedAt < endOfDay
        }
        
        if alreadyCompleted {
            // Step already completed, refresh to update UI
            await loadCalendarData(for: date)
            return
        }
        
        // Create habit entry via HabitManager
        await habitManager.recordHabitCompletion(habit, notes: nil, rating: nil, reflection: nil, mood: nil)
        
        // Invalidate cache to ensure fresh data
        invalidateCache()
        
        // Refresh calendar data
        await loadCalendarData(for: date)
    }
    
    /// Complete a task step
    func completeTaskStep(taskId: String, stepId: String) async {
        // Find the task and toggle step completion
        if let task = taskManager.tasks.first(where: { $0.id == taskId }) {
            await taskManager.toggleStepCompletion(task, stepId: stepId)
            
            // Invalidate cache to ensure fresh data
            invalidateCache()
            
            // Refresh calendar data
            let today = Date()
            await loadCalendarData(for: today)
        }
    }
    
    // MARK: - Cache Management
    
    /// Handle changes to habits list - invalidate cache when habits are added/updated/deleted
    private func handleHabitsChanged(newHabits: [ComprehensiveHabit]) async {
        let newHabitCount = newHabits.count
        let newHabitIds = Set(newHabits.map { $0.id })
        
        // Check if habits changed (count or IDs)
        let habitsChanged = newHabitCount != lastKnownHabitCount || newHabitIds != lastKnownHabitIds
        
        if habitsChanged {
            print("📅 [CalendarManager] Habits changed - Count: \(lastKnownHabitCount) -> \(newHabitCount), Invalidating cache")
            invalidateCache()
            
            // Update last known state
            lastKnownHabitCount = newHabitCount
            lastKnownHabitIds = newHabitIds
            
            // If we have calendar data loaded, reload it to include new habits
            if !calendarData.isEmpty {
                // Reload for the current month (or most recent month in cache)
                if let mostRecentDate = calendarData.keys.max() {
                    let calendar = Calendar.current
                    let month = calendar.dateInterval(of: .month, for: mostRecentDate)?.start ?? mostRecentDate
                    print("📅 [CalendarManager] Auto-reloading calendar data for month: \(month)")
                    await loadCalendarData(for: month)
                }
            }
        }
    }
    
    /// Invalidate the habit mappings cache
    private func invalidateCache() {
        habitMappingsCache.removeAll()
        cacheDateRange = nil
        print("📅 [CalendarManager] Cache invalidated")
    }
}

// MARK: - Helper Models

struct HabitCompletion {
    let habitId: String
    let date: Date
    let isCompleted: Bool
}
