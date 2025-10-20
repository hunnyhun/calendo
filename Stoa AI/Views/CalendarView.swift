import SwiftUI

struct CalendarView: View {
    @StateObject private var calendarManager = CalendarManager.shared
    @State private var selectedScale: Models.CalendarScale = .daily
    @State private var selectedDate: Date?
    @State private var showDateDetail = false
    @State private var currentMonth = Date()
    @State private var currentNote = ""
    @State private var isEditingNote = false
    
    // Navigation callback to go back to chat
    let onNavigateBack: (() -> Void)?
    
    private let daysOfWeek = ["M", "T", "W", "T", "F", "S", "S"]
    
    // Initializer with optional navigation callback
    init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with scale selector
            headerView
            
            // Calendar content based on selected scale
            calendarContentView
            
            Spacer()
        }
        .padding(.horizontal, 15)
        .background(Color(.systemBackground))
        .task {
            print("📅 [CalendarView] Loading calendar data for month: \(currentMonth)")
            await calendarManager.loadCalendarData(for: currentMonth)
            print("📅 [CalendarView] Calendar data loaded: \(calendarManager.calendarData.count) days")
            
            // For daily view, ensure today's data is loaded
            if selectedScale == .daily {
                await calendarManager.loadCalendarData(for: Date())
            }
        }
        .sheet(isPresented: $showDateDetail) {
            let date = selectedScale == .daily ? Date() : (selectedDate ?? Date())
            DateDetailView(
                date: date,
                calendarData: calendarManager.getCalendarData(for: date),
                onSaveNote: { note in
                    Task {
                        await calendarManager.saveCalendarNote(note)
                    }
                },
                onDeleteNote: {
                    Task {
                        await calendarManager.deleteCalendarNote(for: date)
                    }
                }
            )
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 16) {
            // Title and Back button
            HStack {
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
                
                Text("Calendar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Empty space to balance the back button
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .opacity(0)
                    Text("Back")
                        .font(.headline)
                        .opacity(0)
                }
            }
            
            // Scale selector
            Picker("Calendar Scale", selection: $selectedScale) {
                ForEach(Models.CalendarScale.allCases.filter { $0 != .yearly }, id: \.self) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Month/Year navigation (hidden for daily view)
            if selectedScale != .daily {
                HStack {
                    Button(action: previousPeriod) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.brandPrimary)
                    }
                    
                    Spacer()
                    
                    Text(monthYearText)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: nextPeriod) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundColor(.brandPrimary)
                    }
                }
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Calendar Content View
    private var calendarContentView: some View {
        Group {
            switch selectedScale {
            case .daily:
                dailyView
            case .weekly:
                weeklyView
            case .monthly:
                monthlyView
            case .yearly:
                // This case should never be reached since yearly is filtered out
                dailyView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedScale)
    }
    
    // MARK: - Daily View
    private var dailyView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Today")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let dayData = calendarManager.getCalendarData(for: Date()) {
                DaySummaryView(dayData: dayData)
                    .onTapGesture {
                        showDateDetail = true
                    }
            } else {
                // Show empty state with section titles
                VStack(spacing: 20) {
                    // Habits Section (Empty)
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "target")
                                    .foregroundColor(.brandPrimary)
                                Text("Habits")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("0/0")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("You have no habit steps for today")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.vertical, 8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Tasks Section (Empty)
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checklist")
                                    .foregroundColor(.blue)
                                Text("Tasks")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("0/0")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("You have no task steps for today")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.vertical, 8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .onTapGesture {
                    showDateDetail = true
                }
            }
        }
        .padding()
    }
    
    // MARK: - Weekly View
    private var weeklyView: some View {
        VStack(spacing: 20) {
            // Week header
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // Week grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekDays, id: \.self) { date in
                    WeekDayView(
                        date: date,
                        calendarData: calendarManager.getCalendarData(for: date),
                        isSelected: selectedDate == date,
                        onTap: {
                            selectedDate = date
                            showDateDetail = true
                        }
                    )
                }
            }
            .padding(.horizontal)
            
            // Week summary
            WeekSummaryView(weekDays: weekDays, calendarManager: calendarManager)
                .onTapGesture {
                    showDateDetail = true
                }
        }
    }
    
    // MARK: - Monthly View
    private var monthlyView: some View {
        VStack(spacing: 20) {
            // Day names header
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(hex: 0xDCEAF7))
                        )
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            VStack(spacing: 6) {
                ForEach(0..<((monthDays.count + 6) / 7), id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { day in
                            let dateIndex = week * 7 + day
                            if dateIndex < monthDays.count {
                                let date = monthDays[dateIndex]
                                MonthDayView(
                                    date: date,
                                    calendarData: calendarManager.getCalendarData(for: date),
                                    isSelected: selectedDate == date,
                                    isCurrentMonth: Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month),
                                    onTap: {
                                        selectedDate = date
                                        showDateDetail = true
                                    }
                                )
                            } else {
                                // Empty space for incomplete last row
                                Spacer()
                                    .frame(width: 32, height: 32)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.brandBrightGreen)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            // Month summary
            MonthSummaryView(monthDays: monthDays, calendarManager: calendarManager)
                .onTapGesture {
                    showDateDetail = true
                }
        }
    }
    
    
    // MARK: - Computed Properties
    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
    
    private var monthDays: [Date] {
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: currentMonth)?.start ?? currentMonth
        let endOfMonth = calendar.dateInterval(of: .month, for: currentMonth)?.end ?? currentMonth
        
        var days: [Date] = []
        var currentDate = startOfMonth
        
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
        while currentDate < endOfMonth {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        // Add days from next month to complete the last week
        // Calculate how many days we need to reach the next Sunday
        let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: endOfMonth) ?? endOfMonth
        let lastWeekday = calendar.component(.weekday, from: lastDayOfMonth)
        // Sunday is weekday 1, so we need to add (8 - lastWeekday) % 7 days to reach Sunday
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
    
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: currentMonth)?.start ?? currentMonth
        
        var days: [Date] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                days.append(date)
            }
        }
        return days
    }
    
    // MARK: - Actions
    private func previousPeriod() {
        let calendar = Calendar.current
        switch selectedScale {
        case .daily, .weekly:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentMonth) {
                currentMonth = newDate
            }
        case .monthly:
            if let newDate = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
                currentMonth = newDate
            }
        case .yearly:
            // This case should never be reached since yearly is filtered out
            break
        }
        
        Task {
            await calendarManager.loadCalendarData(for: currentMonth)
        }
    }
    
    private func nextPeriod() {
        let calendar = Calendar.current
        switch selectedScale {
        case .daily, .weekly:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentMonth) {
                currentMonth = newDate
            }
        case .monthly:
            if let newDate = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
                currentMonth = newDate
            }
        case .yearly:
            // This case should never be reached since yearly is filtered out
            break
        }
        
        Task {
            await calendarManager.loadCalendarData(for: currentMonth)
        }
    }
}

// MARK: - Supporting Views

struct DaySummaryView: View {
    let dayData: Models.CalendarDayData
    
    var body: some View {
        VStack(spacing: 20) {
            // Habits Section
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.brandPrimary)
                        Text("Habits")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Text("\(dayData.habitsCompleted)/\(dayData.totalHabits)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(dayData.habitSteps.isEmpty ? "You have no steps" : "Scheduled Habits")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if !dayData.habitSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(dayData.habitSteps.prefix(3)) { step in
                            HStack {
                                Circle()
                                    .fill(step.isCompleted ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.habitName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(step.stepDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let time = step.time {
                                    Text(time)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        if dayData.habitSteps.count > 3 {
                            Text("+ \(dayData.habitSteps.count - 3) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("You have no habit steps for today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Tasks Section
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(.blue)
                        Text("Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    
                    Text(dayData.taskItems.isEmpty ? "You have no steps" : "Scheduled Tasks")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if !dayData.taskItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(dayData.taskItems.prefix(3)) { item in
                            HStack {
                                Circle()
                                    .fill(item.isCompleted ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.taskName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let daysRemaining = item.daysRemaining {
                                    Text("\(daysRemaining)d")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        if dayData.taskItems.count > 3 {
                            Text("+ \(dayData.taskItems.count - 3) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("You have no task steps for today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Quote indicator
            if dayData.hasQuote {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "quote.bubble")
                            .foregroundColor(.brandPrimary)
                        Text("Daily Quote")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    
                    Text("Daily Quote Viewed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Note preview
            if let note = dayData.note {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(.brandPrimary)
                        Text("Note")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    
                    Text(note.note)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct WeekDayView: View {
    let date: Date
    let calendarData: Models.CalendarDayData?
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                if let data = calendarData {
                    HStack(spacing: 2) {
                        if data.habitsCompleted > 0 {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                        if data.hasQuote {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                        }
                        if data.note != nil {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .frame(width: 40, height: 40)
            .background(
                Circle()
                    .fill(isSelected ? Color.brandPrimary : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MonthDayView: View {
    let date: Date
    let calendarData: Models.CalendarDayData?
    let isSelected: Bool
    let isCurrentMonth: Bool
    let onTap: () -> Void
    
    private var isCurrentDay: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                // Visual indicators for habits and tasks
                if let data = calendarData {
                    HStack(spacing: 2) {
                        // Habit indicator (green)
                        if !data.habitSteps.isEmpty {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4, height: 4)
                        }
                        
                        // Task indicator (blue)
                        if !data.taskItems.isEmpty {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                        }
                        
                        // Deadline indicator (orange)
                        if data.taskItems.contains(where: { $0.itemType == .deadline }) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(isCurrentDay ? Color.brandCurrentDay : Color(hex: 0x12D70C))
            )
            .frame(maxWidth: .infinity)
            .opacity(isCurrentMonth ? 1.0 : 0.5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


struct DateDetailView: View {
    let date: Date
    let calendarData: Models.CalendarDayData?
    let onSaveNote: (Models.CalendarNote) -> Void
    let onDeleteNote: () -> Void
    
    @State private var noteText = ""
    @State private var isEditing = false
    @Environment(\.dismiss) private var dismiss
    
    // Add references to managers
    private let calendarManager = CalendarManager.shared
    private let taskManager = TaskManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Date header
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()
                
                // Habits summary
                if let data = calendarData {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(.brandPrimary)
                            Text("Habits Completed: \(data.habitsCompleted)/\(data.totalHabits)")
                                .font(.headline)
                        }
                        
                        if data.hasQuote {
                            HStack {
                                Image(systemName: "quote.bubble")
                                    .foregroundColor(.brandPrimary)
                                Text("Daily Quote Viewed")
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Habit Steps Section
                if let data = calendarData, !data.habitSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.green)
                            Text("Scheduled Habits")
                                .font(.headline)
                            Spacer()
                        }
                        
                        ForEach(data.habitSteps) { step in
                            HabitStepRow(
                                step: step,
                                onComplete: {
                                    Task {
                                        await calendarManager.completeHabitStep(habitId: step.habitId, date: date)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Task Items Section
                if let data = calendarData, !data.taskItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundColor(.blue)
                            Text("Tasks")
                                .font(.headline)
                            Spacer()
                        }
                        
                        ForEach(data.taskItems) { item in
                            TaskItemRow(
                                item: item,
                                onComplete: {
                                    Task {
                                        // Find the step ID for the current step
                                        if let task = taskManager.tasks.first(where: { $0.id == item.taskId }),
                                           let step = task.steps.first(where: { $0.description == item.description }) {
                                            await calendarManager.completeTaskStep(taskId: item.taskId, stepId: step.id)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Note section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(.brandPrimary)
                        Text("Notes")
                            .font(.headline)
                        Spacer()
                        
                        if calendarData?.note != nil {
                            Button(isEditing ? "Save" : "Edit") {
                                if isEditing {
                                    saveNote()
                                } else {
                                    isEditing = true
                                    noteText = calendarData?.note?.note ?? ""
                                }
                            }
                            .foregroundColor(.brandPrimary)
                        }
                    }
                    
                    if isEditing {
                        TextEditor(text: $noteText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
                        HStack {
                            Button("Cancel") {
                                isEditing = false
                                noteText = ""
                            }
                            .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if calendarData?.note != nil {
                                Button("Delete") {
                                    onDeleteNote()
                                    dismiss()
                                }
                                .foregroundColor(.red)
                            }
                        }
                    } else if let note = calendarData?.note {
                        Text(note.note)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                    } else {
                        Text("No notes for this day")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Day Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                if isEditing {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveNote()
                        }
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .onAppear {
            if let note = calendarData?.note {
                noteText = note.note
            }
        }
    }
    
    private func saveNote() {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            let note = Models.CalendarNote(date: date, note: trimmedNote)
            onSaveNote(note)
        }
        isEditing = false
    }
}

// MARK: - Interactive Components

struct HabitStepRow: View {
    let step: Models.CalendarHabitStep
    let onComplete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(step.isCompleted ? .green : .gray)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(step.habitName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(step.stepDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let time = step.time {
                Text(time)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TaskItemRow: View {
    let item: Models.CalendarTaskItem
    let onComplete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isCompleted ? .green : .gray)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.taskName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(item.itemType.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            }
            
            Spacer()
            
            if let daysRemaining = item.daysRemaining {
                Text("\(daysRemaining)d")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Week Summary View
struct WeekSummaryView: View {
    let weekDays: [Date]
    let calendarManager: CalendarManager
    
    private var weekData: (habitsCompleted: Int, totalHabits: Int, hasData: Bool, hasProgress: Bool) {
        var totalCompleted = 0
        var totalHabits = 0
        var hasAnyData = false
        var hasProgress = false
        
        for date in weekDays {
            if let dayData = calendarManager.getCalendarData(for: date) {
                totalCompleted += dayData.habitsCompleted
                totalHabits += dayData.totalHabits
                if !dayData.habitSteps.isEmpty || !dayData.taskItems.isEmpty {
                    hasAnyData = true
                }
                if dayData.habitsCompleted > 0 || !dayData.habitSteps.isEmpty || !dayData.taskItems.isEmpty {
                    hasProgress = true
                }
            }
        }
        
        return (totalCompleted, totalHabits, hasAnyData, hasProgress)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Habits Section
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.brandPrimary)
                        Text("Habits")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Text("\(weekData.habitsCompleted)/\(weekData.totalHabits)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if weekData.totalHabits > 0 {
                    Text("Weekly habit completion")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("You have no habit steps this week")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Tasks Section
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(.blue)
                        Text("Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Text("0/0")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if weekData.hasData {
                    Text("Weekly task completion")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("You have no task steps this week")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
    }
}

// MARK: - Month Summary View
struct MonthSummaryView: View {
    let monthDays: [Date]
    let calendarManager: CalendarManager
    
    private var monthData: (habitsCompleted: Int, totalHabits: Int, hasData: Bool) {
        var totalCompleted = 0
        var totalHabits = 0
        var hasAnyData = false
        
        for date in monthDays {
            if let dayData = calendarManager.getCalendarData(for: date) {
                totalCompleted += dayData.habitsCompleted
                totalHabits += dayData.totalHabits
                if !dayData.habitSteps.isEmpty || !dayData.taskItems.isEmpty {
                    hasAnyData = true
                }
            }
        }
        
        return (totalCompleted, totalHabits, hasAnyData)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Habits Section
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.brandPrimary)
                        Text("Habits")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Text("\(monthData.habitsCompleted)/\(monthData.totalHabits)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if monthData.hasData {
                    Text("Monthly Progress")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("You have no habit steps this month")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Tasks Section
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(.blue)
                        Text("Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Text("0/0")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if monthData.hasData {
                    Text("Monthly Tasks")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("You have no task steps this month")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
    }
}

#Preview {
    CalendarView(onNavigateBack: {
        print("Navigate back to chat")
    })
}
