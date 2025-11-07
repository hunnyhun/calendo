import SwiftUI

struct CalendarView: View {
    @StateObject private var calendarManager = CalendarManager.shared
    @State private var selectedScale: Models.CalendarScale = .daily
    @State private var selectedDate: Date?
    @State private var selectedDailyDate: Date = Date()
    @State private var showDateDetail = false
    @State private var currentMonth = Date()
    @State private var currentNote = ""
    @State private var isEditingNote = false
    @AppStorage("calendarShowHabitsFirst") private var showHabitsFirst: Bool = true // Default: habits first, tasks second - persists user preference
    
    // Navigation binding for bottom bar
    @Binding var selectedFeature: Models.Feature
    
    private let daysOfWeek = ["M", "T", "W", "T", "F", "S", "S"]
    
    // Initializer with navigation binding
    init(selectedFeature: Binding<Models.Feature> = .constant(.calendar)) {
        self._selectedFeature = selectedFeature
    }
    
    // Legacy initializer for backward compatibility
    init(onNavigateBack: (() -> Void)? = nil) {
        self._selectedFeature = .constant(.calendar)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Fixed header at top
                headerView
                    .padding(.horizontal, 15)
                    .background(Color(.systemBackground))
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        calendarContentView
                            .padding(.horizontal, 15)
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                    }
                }
                
                // Fixed Bottom Navigation Bar at bottom
                BottomNavigationBar(selectedFeature: $selectedFeature)
            }
            
            // Toggle button to swap habits and tasks - top right corner of screen
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showHabitsFirst.toggle()
                }
            }) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title3)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .rotationEffect(.degrees(showHabitsFirst ? 0 : 180))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 8) // Top of screen with minimal padding
            .padding(.trailing, 15)
            .allowsHitTesting(true)
        }
        .background(Color(.systemBackground))
        .task {
            print("📅 [CalendarView] Loading calendar data for month: \(currentMonth)")
            await calendarManager.loadCalendarData(for: currentMonth)
            print("📅 [CalendarView] Calendar data loaded: \(calendarManager.calendarData.count) days")
            
            // For daily view, ensure selected date's data is loaded
            if selectedScale == .daily {
                await calendarManager.loadCalendarData(for: selectedDailyDate)
            }
        }
        .onChange(of: selectedDailyDate) { oldValue, newValue in
            Task {
                await calendarManager.loadCalendarData(for: newValue)
            }
        }
        .sheet(isPresented: $showDateDetail) {
            let date = selectedScale == .daily ? selectedDailyDate : (selectedDate ?? Date())
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
            // Title - fixed position
            HStack {
                Spacer()
                
                Text("Calendar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .frame(height: 44) // Fixed height to maintain position
            
            // Custom scale selector toggle
            CalendarScaleToggle(selectedScale: $selectedScale)
                .frame(height: 44) // Fixed height for toggle
                .padding(.bottom, 10)
            
            // Date/Month/Year navigation (always same height for consistency)
            HStack {
                if selectedScale == .daily {
                    // Daily date navigation
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            previousDay()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.brandPrimary)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text(isToday(selectedDailyDate) ? "Today" : selectedDailyDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.title2)
                            .fontWeight(.bold)
                            .id(selectedDailyDate)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        
                        Text(selectedDailyDate.formatted(.dateTime.weekday(.wide)))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .id(selectedDailyDate)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            nextDay()
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundColor(.brandPrimary)
                    }
                } else {
                    // Weekly/Monthly navigation
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
            .frame(height: 44) // Fixed height always
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 44 + 16 + 44 + 10 + 16 + 44 + 20 + 16) // Fixed total height: title + spacing + toggle + toggleBottomPadding + spacing + nav + topPadding + bottomPadding = 210
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
        .onChange(of: selectedScale) { oldValue, newValue in
            // Reset to today when switching to daily view
            if newValue == .daily && oldValue != .daily {
                selectedDailyDate = Date()
            }
        }
    }
    
    // MARK: - Daily View
    private var dailyView: some View {
        VStack(spacing: 20) {
            // Content with animation
            Group {
                if let dayData = calendarManager.getCalendarData(for: selectedDailyDate) {
                    DaySummaryView(dayData: dayData, showHabitsFirst: $showHabitsFirst)
                        .id(selectedDailyDate) // Force view refresh on date change
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                        .onAppear {
                            print("📅 [CalendarView] Found data for selected date: \(dayData.habitSteps.count) habit steps, \(dayData.taskItems.count) task items")
                        }
                        // Remove onTapGesture to prevent interference with card buttons
                } else if calendarManager.isLoading {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.vertical, 40)
                        
                        Text("Loading habits...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .transition(.opacity)
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
                            
                            Text("You have no habit steps for this day")
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
                            
                            Text("You have no task steps for this day")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.vertical, 8)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .id(selectedDailyDate)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                    .onTapGesture {
                        showDateDetail = true
                    }
                    .onAppear {
                        print("📅 [CalendarView] No data found for selected date")
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedDailyDate)
        }
    }
    
    // MARK: - Weekly View
    private var weeklyView: some View {
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
            
            // Calendar grid with equal spacing - single row with 7 day cells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 7), spacing: 16) {
                ForEach(weekDays.indices, id: \.self) { index in
                    let date = weekDays[index]
                    MonthDayView(
                        date: date,
                        calendarData: calendarManager.getCalendarData(for: date),
                        isSelected: selectedDate == date,
                        isCurrentMonth: true, // All days in week are part of current week
                        onTap: {
                            selectedDate = date
                            showDateDetail = true
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.brandBrightGreen)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .id(currentMonth) // Force view refresh on month change
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
            
            // Week summary with habit cards
            WeekSummaryCardsView(weekDays: weekDays, calendarManager: calendarManager, showHabitsFirst: $showHabitsFirst)
                .id(currentMonth) // Force view refresh on month change
                .transition(.opacity)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentMonth)
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
            
            // Calendar grid with equal spacing
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 7), spacing: 16) {
                ForEach(monthDays.indices, id: \.self) { index in
                    let date = monthDays[index]
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
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.brandBrightGreen)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .id(currentMonth) // Force view refresh on month change
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
            
            // Month summary with habit cards
            MonthSummaryCardsView(monthDays: monthDays, calendarManager: calendarManager, showHabitsFirst: $showHabitsFirst)
                .id(currentMonth) // Force view refresh on month change
                .transition(.opacity)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentMonth)
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
    private func previousDay() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: -1, to: selectedDailyDate) {
            selectedDailyDate = newDate
        }
    }
    
    private func nextDay() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: 1, to: selectedDailyDate) {
            selectedDailyDate = newDate
        }
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private func previousPeriod() {
        let calendar = Calendar.current
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
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
        }
        
        Task {
            await calendarManager.loadCalendarData(for: currentMonth)
        }
    }
    
    private func nextPeriod() {
        let calendar = Calendar.current
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
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
        }
        
        Task {
            await calendarManager.loadCalendarData(for: currentMonth)
        }
    }
}

// MARK: - Supporting Views

struct DaySummaryView: View {
    let dayData: Models.CalendarDayData
    @Binding var showHabitsFirst: Bool
    @State private var expandedHabits: Set<String> = []
    
    // Habit colors array - bright, high-contrast colors for visibility
    private let habitColors: [Color] = [
        Color(red: 0.2, green: 0.8, blue: 0.4),      // Bright Green
        Color(red: 0.4, green: 0.3, blue: 0.9),      // Bright Purple
        Color(red: 0.0, green: 0.7, blue: 1.0),      // Bright Blue
        Color(red: 1.0, green: 0.3, blue: 0.5),     // Bright Pink
        Color(red: 1.0, green: 0.4, blue: 0.2),     // Bright Orange
        Color(red: 0.6, green: 0.2, blue: 0.8),     // Bright Violet
        Color(red: 0.2, green: 0.6, blue: 0.9),     // Bright Cyan
        Color(red: 0.9, green: 0.2, blue: 0.3)      // Bright Red
    ]
    
    // Helper function to get consistent color for a habit
    // Uses a stable hash based on habitId to ensure same habit always gets same color
    private func getColorForHabit(habitId: String) -> Color {
        // Create a stable hash from the habitId string
        var hash: Int = 0
        for char in habitId.utf8 {
            hash = ((hash << 5) &- hash) &+ Int(char)
            hash = hash & hash // Convert to 32bit
        }
        let positiveHash = abs(hash)
        let colorIndex = positiveHash % habitColors.count
        return habitColors[colorIndex]
    }
    
    // Computed property for sorted habits
    private var sortedHabits: [(String, [Models.CalendarHabitStep])] {
        let groupedHabits = Dictionary(grouping: dayData.habitSteps) { $0.habitId }
        return groupedHabits.sorted { habit1, habit2 in
            let name1 = habit1.value.first?.habitName ?? ""
            let name2 = habit2.value.first?.habitName ?? ""
            return name1 < name2
        }
    }
    
    // Computed property for displayed habit cards count
    private var displayedHabitCardsCount: Int {
        sortedHabits.count
    }
    
    // Habits Section View
    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.brandPrimary)
                    Text("Habits")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    // Show count of displayed habit cards
                    Text("\(displayedHabitCardsCount)/\(displayedHabitCardsCount)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                if !dayData.habitSteps.isEmpty {
                    ForEach(Array(sortedHabits.enumerated()), id: \.element.0) { index, habitTuple in
                        let (habitId, steps) = habitTuple
                        if let firstStep = steps.first {
                            let cardColor = getColorForHabit(habitId: habitId)
                            let completedCount = steps.filter { $0.isCompleted }.count
                            let isExpanded = expandedHabits.contains(habitId)
                            
                            // Determine indexed day title - show if available (for daily view)
                            let allTitles = steps.compactMap { $0.title }.filter { !$0.isEmpty }
                            let uniqueTitles = Set(allTitles)
                            // Show title if all steps share the same indexed day title
                            let indexedDayTitle = uniqueTitles.count == 1 ? uniqueTitles.first : nil
                            
                            // Make entire card clickable
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    if isExpanded {
                                        expandedHabits.remove(habitId)
                                    } else {
                                        expandedHabits.insert(habitId)
                                    }
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Habit header
                                    HStack {
                                        Text(firstStep.habitName)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Text("\(completedCount)/\(steps.count)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(cardColor)
                                        
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(cardColor)
                                            .padding(.leading, 8)
                                    }
                                    
                                    // Display indexed day title if available (for daily view)
                                    if let indexedTitle = indexedDayTitle {
                                        Text(indexedTitle)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(cardColor)
                                            .padding(.top, 2)
                                    }
                                    
                                    // Habit steps - expandable
                                    if isExpanded {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(steps) { step in
                                                HStack(spacing: 12) {
                                                    Circle()
                                                        .fill(step.isCompleted ? cardColor : Color.gray.opacity(0.3))
                                                        .frame(width: 10, height: 10)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(step.stepDescription)
                                                            .font(.subheadline)
                                                            .foregroundColor(.primary)
                                                            .strikethrough(step.isCompleted)
                                                        
                                                        if let difficulty = step.difficulty {
                                                            Text(difficulty.capitalized)
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    if let time = step.time {
                                                        Text(time)
                                                            .font(.caption)
                                                            .fontWeight(.medium)
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                            .background(cardColor)
                                                            .cornerRadius(6)
                                                    }
                                                }
                                            }
                                        }
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .move(edge: .top)),
                                            removal: .opacity.combined(with: .move(edge: .top))
                                        ))
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(cardColor.opacity(0.15))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(cardColor.opacity(0.3), lineWidth: 1.5)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle()) // Make entire card area tappable
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                .delay(Double(index) * 0.1),
                                value: dayData.date
                            )
                        }
                    }
                } else {
                    Text("You have no habit steps for today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
    }
    
    // Computed property for displayed task items count
    private var displayedTaskItemsCount: Int {
        min(dayData.taskItems.count, 3) // Daily view shows up to 3 items
    }
    
    // Tasks Section View
    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundColor(.blue)
                    Text("Tasks")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    // Show count of displayed task items
                    Text("\(displayedTaskItemsCount)/\(displayedTaskItemsCount)")
                        .font(.headline)
                        .foregroundColor(.secondary)
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
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Reorder sections based on toggle
            if showHabitsFirst {
                habitsSection
                tasksSection
            } else {
                tasksSection
                habitsSection
            }
            
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
        .onChange(of: dayData.date) { _, _ in
            // Reset expanded habits when date changes
            expandedHabits.removeAll()
        }
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
                    .font(.system(size: 14, weight: .medium))
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
                        
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Circle()
                    .fill(isCurrentDay ? Color.brandCurrentDay : Color(hex: 0x12D70C))
            )
            .clipShape(Circle())
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
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onComplete) {
                    Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(step.isCompleted ? .green : .gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(step.habitName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let phase = step.phase {
                            Text(phase.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(step.stepDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                    
                    if !isExpanded && (step.difficulty != nil || step.durationMinutes != nil) {
                        HStack(spacing: 8) {
                            if let difficulty = step.difficulty {
                                DifficultyBadge(difficulty: difficulty)
                            }
                            
                            if let duration = step.durationMinutes {
                                Label("\(duration)m", systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let time = step.time {
                        Text(time)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    
                    if step.feedback != nil || step.durationMinutes != nil {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let difficulty = step.difficulty {
                        HStack(spacing: 8) {
                            Text("Difficulty:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DifficultyBadge(difficulty: difficulty)
                        }
                    }
                    
                    if let duration = step.durationMinutes {
                        HStack(spacing: 8) {
                            Text("Duration:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Label("\(duration) minutes", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let feedback = step.feedback {
                        Text(feedback)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                    }
                }
                .padding(.leading, 40)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(step.isCompleted ? Color.green.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }
}

struct DifficultyBadge: View {
    let difficulty: String
    
    var body: some View {
        let (color, text) = difficultyInfo
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
    
    private var difficultyInfo: (Color, String) {
        switch difficulty.lowercased() {
        case "easy":
            return (.green, "Easy")
        case "medium":
            return (.orange, "Medium")
        case "hard":
            return (.red, "Hard")
        case "expert":
            return (.purple, "Expert")
        default:
            return (.gray, difficulty.capitalized)
        }
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
        }
        .padding()
    }
}

// MARK: - Week Summary Cards View
struct WeekSummaryCardsView: View {
    let weekDays: [Date]
    let calendarManager: CalendarManager
    @Binding var showHabitsFirst: Bool
    @State private var expandedHabits: Set<String> = []
    
    // Habit colors array - bright, high-contrast colors for visibility
    private let habitColors: [Color] = [
        Color(red: 0.2, green: 0.8, blue: 0.4),      // Bright Green
        Color(red: 0.4, green: 0.3, blue: 0.9),      // Bright Purple
        Color(red: 0.0, green: 0.7, blue: 1.0),      // Bright Blue
        Color(red: 1.0, green: 0.3, blue: 0.5),     // Bright Pink
        Color(red: 1.0, green: 0.4, blue: 0.2),     // Bright Orange
        Color(red: 0.6, green: 0.2, blue: 0.8),     // Bright Violet
        Color(red: 0.2, green: 0.6, blue: 0.9),     // Bright Cyan
        Color(red: 0.9, green: 0.2, blue: 0.3)      // Bright Red
    ]
    
    private func getColorForHabit(habitId: String) -> Color {
        var hash: Int = 0
        for char in habitId.utf8 {
            hash = ((hash << 5) &- hash) &+ Int(char)
            hash = hash & hash
        }
        let positiveHash = abs(hash)
        let colorIndex = positiveHash % habitColors.count
        return habitColors[colorIndex]
    }
    
    // Collect all unique habits from the week
    private var weekHabits: [(String, String, [Date], Int, String?)] { // (habitId, habitName, dates, totalSteps, indexedWeekTitle)
        var habitMap: [String: (String, [Date], Int, Set<String>)] = [:]
        
        for date in weekDays {
            if let dayData = calendarManager.getCalendarData(for: date) {
                for step in dayData.habitSteps {
                    if habitMap[step.habitId] == nil {
                        habitMap[step.habitId] = (step.habitName, [], 0, [])
                    }
                    habitMap[step.habitId]?.1.append(date)
                    habitMap[step.habitId]?.2 += 1
                    if let title = step.title, !title.isEmpty {
                        habitMap[step.habitId]?.3.insert(title)
                    }
                }
            }
        }
        
        return habitMap.map { (id, data) in
            // If all steps share the same indexed week title, use it; otherwise nil
            let uniqueTitles = data.3
            let indexedWeekTitle = uniqueTitles.count == 1 ? uniqueTitles.first : nil
            return (id, data.0, data.1, data.2, indexedWeekTitle)
        }.sorted { $0.1 < $1.1 }
    }
    
    // Habits Section View
    private var habitsSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.brandPrimary)
                Text("Habits")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                // Show count of displayed habit cards
                Text("\(weekHabits.count)/\(weekHabits.count)")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if weekHabits.isEmpty {
                Text("No habits scheduled this week")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                // Habit cards
                ForEach(Array(weekHabits.enumerated()), id: \.element.0) { index, habitTuple in
                    let (habitId, habitName, dates, totalSteps, indexedWeekTitle) = habitTuple
                    let cardColor = getColorForHabit(habitId: habitId)
                    let isExpanded = expandedHabits.contains(habitId)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if isExpanded {
                                expandedHabits.remove(habitId)
                            } else {
                                expandedHabits.insert(habitId)
                            }
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Habit header
                            HStack {
                                Text(habitName)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text("\(totalSteps) step\(totalSteps == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(cardColor)
                                
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(cardColor)
                            }
                            
                            // Display indexed week title if available (for weekly view)
                            if let weekTitle = indexedWeekTitle {
                                Text(weekTitle)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(cardColor)
                                    .padding(.top, 2)
                            }
                            
                            // Days with activity
                            if isExpanded {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(dates, id: \.self) { date in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(cardColor.opacity(0.3))
                                                .frame(width: 6, height: 6)
                                            
                                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            if let dayData = calendarManager.getCalendarData(for: date) {
                                                let daySteps = dayData.habitSteps.filter { $0.habitId == habitId }
                                                if !daySteps.isEmpty {
                                                    Text("• \(daySteps.count) step\(daySteps.count == 1 ? "" : "s")")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            } else {
                                // Show day count summary
                                Text("\(dates.count) day\(dates.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(cardColor.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(cardColor.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
            }
        }
    }
    
    // Tasks Section View
    private var tasksSection: some View {
        VStack(spacing: 16) {
            // Collect all unique tasks from the week
            let weekTasks = collectWeekTasks()
            
            // Header
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                Text("Tasks")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                // Show count of displayed task cards
                Text("\(weekTasks.count)/\(weekTasks.count)")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if weekTasks.isEmpty {
                Text("No tasks scheduled this week")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                // Task cards
                ForEach(weekTasks, id: \.taskId) { task in
                    TaskCardView(task: task, calendarManager: calendarManager)
                }
                .padding(.horizontal)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Reorder sections based on toggle
            if showHabitsFirst {
                habitsSection
                tasksSection
            } else {
                tasksSection
                habitsSection
            }
        }
    }
    
    // Collect all unique tasks from the week
    private func collectWeekTasks() -> [(taskId: String, taskName: String, dates: [Date], totalItems: Int)] {
        var taskMap: [String: (String, [Date], Int)] = [:]
        
        for date in weekDays {
            if let dayData = calendarManager.getCalendarData(for: date) {
                for item in dayData.taskItems {
                    if taskMap[item.taskId] == nil {
                        taskMap[item.taskId] = (item.taskName, [], 0)
                    }
                    if !taskMap[item.taskId]!.1.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
                        taskMap[item.taskId]?.1.append(date)
                    }
                    taskMap[item.taskId]?.2 += 1
                }
            }
        }
        
        return taskMap.map { (id, data) in
            (taskId: id, taskName: data.0, dates: data.1, totalItems: data.2)
        }.sorted { $0.taskName < $1.taskName }
    }
}

// MARK: - Month Summary Cards View
struct MonthSummaryCardsView: View {
    let monthDays: [Date]
    let calendarManager: CalendarManager
    @Binding var showHabitsFirst: Bool
    @State private var expandedHabits: Set<String> = []
    
    // Habit colors array - bright, high-contrast colors for visibility
    private let habitColors: [Color] = [
        Color(red: 0.2, green: 0.8, blue: 0.4),      // Bright Green
        Color(red: 0.4, green: 0.3, blue: 0.9),      // Bright Purple
        Color(red: 0.0, green: 0.7, blue: 1.0),      // Bright Blue
        Color(red: 1.0, green: 0.3, blue: 0.5),     // Bright Pink
        Color(red: 1.0, green: 0.4, blue: 0.2),     // Bright Orange
        Color(red: 0.6, green: 0.2, blue: 0.8),     // Bright Violet
        Color(red: 0.2, green: 0.6, blue: 0.9),     // Bright Cyan
        Color(red: 0.9, green: 0.2, blue: 0.3)      // Bright Red
    ]
    
    private func getColorForHabit(habitId: String) -> Color {
        var hash: Int = 0
        for char in habitId.utf8 {
            hash = ((hash << 5) &- hash) &+ Int(char)
            hash = hash & hash
        }
        let positiveHash = abs(hash)
        let colorIndex = positiveHash % habitColors.count
        return habitColors[colorIndex]
    }
    
    // Collect all unique habits from the month
    private var monthHabits: [(String, String, [Date], Int, String?)] { // (habitId, habitName, dates, totalSteps, indexedMonthTitle)
        var habitMap: [String: (String, [Date], Int, Set<String>)] = [:]
        
        for date in monthDays {
            if let dayData = calendarManager.getCalendarData(for: date) {
                for step in dayData.habitSteps {
                    if habitMap[step.habitId] == nil {
                        habitMap[step.habitId] = (step.habitName, [], 0, [])
                    }
                    if !habitMap[step.habitId]!.1.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
                        habitMap[step.habitId]?.1.append(date)
                    }
                    habitMap[step.habitId]?.2 += 1
                    if let title = step.title, !title.isEmpty {
                        habitMap[step.habitId]?.3.insert(title)
                    }
                }
            }
        }
        
        return habitMap.map { (id, data) in
            // If all steps share the same indexed month title, use it; otherwise nil
            let uniqueTitles = data.3
            let indexedMonthTitle = uniqueTitles.count == 1 ? uniqueTitles.first : nil
            return (id, data.0, data.1, data.2, indexedMonthTitle)
        }.sorted { $0.1 < $1.1 }
    }
    
    // Habits Section View
    private var habitsSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.brandPrimary)
                Text("Habits")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                // Show count of displayed habit cards
                Text("\(monthHabits.count)/\(monthHabits.count)")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if monthHabits.isEmpty {
                Text("No habits scheduled this month")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                // Habit cards (minimal info)
                ForEach(Array(monthHabits.enumerated()), id: \.element.0) { index, habitTuple in
                    let (habitId, habitName, dates, totalSteps, indexedMonthTitle) = habitTuple
                    let cardColor = getColorForHabit(habitId: habitId)
                    let isExpanded = expandedHabits.contains(habitId)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if isExpanded {
                                expandedHabits.remove(habitId)
                            } else {
                                expandedHabits.insert(habitId)
                            }
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // Habit name
                                Text(habitName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                // Minimal info
                                if isExpanded {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(dates.count) day\(dates.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(totalSteps) total")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("\(dates.count) day\(dates.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(cardColor)
                                }
                                
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(cardColor)
                            }
                            
                            // Display indexed month title if available (for monthly view)
                            if let monthTitle = indexedMonthTitle {
                                Text(monthTitle)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(cardColor)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(cardColor.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(cardColor.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
            }
        }
    }
    
    // Tasks Section View
    private var tasksSection: some View {
        VStack(spacing: 16) {
            // Collect all unique tasks from the month
            let monthTasks = collectMonthTasks()
            
            // Header
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                Text("Tasks")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                // Show count of displayed task cards
                Text("\(monthTasks.count)/\(monthTasks.count)")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if monthTasks.isEmpty {
                Text("No tasks scheduled this month")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                // Task cards
                ForEach(monthTasks, id: \.taskId) { task in
                    TaskCardView(task: task, calendarManager: calendarManager)
                }
                .padding(.horizontal)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Reorder sections based on toggle
            if showHabitsFirst {
                habitsSection
                tasksSection
            } else {
                tasksSection
                habitsSection
            }
        }
    }
    
    // Collect all unique tasks from the month
    private func collectMonthTasks() -> [(taskId: String, taskName: String, dates: [Date], totalItems: Int)] {
        var taskMap: [String: (String, [Date], Int)] = [:]
        
        for date in monthDays {
            if let dayData = calendarManager.getCalendarData(for: date) {
                for item in dayData.taskItems {
                    if taskMap[item.taskId] == nil {
                        taskMap[item.taskId] = (item.taskName, [], 0)
                    }
                    if !taskMap[item.taskId]!.1.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
                        taskMap[item.taskId]?.1.append(date)
                    }
                    taskMap[item.taskId]?.2 += 1
                }
            }
        }
        
        return taskMap.map { (id, data) in
            (taskId: id, taskName: data.0, dates: data.1, totalItems: data.2)
        }.sorted { $0.taskName < $1.taskName }
    }
}

// MARK: - Task Card View
struct TaskCardView: View {
    let task: (taskId: String, taskName: String, dates: [Date], totalItems: Int)
    let calendarManager: CalendarManager
    @State private var isExpanded = false
    
    private let taskColor = Color.blue
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Task header
                HStack {
                    Text(task.taskName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(task.totalItems) item\(task.totalItems == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(taskColor)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(taskColor)
                }
                
                // Days with activity
                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(task.dates, id: \.self) { date in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(taskColor.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                
                                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if let dayData = calendarManager.getCalendarData(for: date) {
                                    let dayItems = dayData.taskItems.filter { $0.taskId == task.taskId }
                                    if !dayItems.isEmpty {
                                        Text("• \(dayItems.count) item\(dayItems.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    // Show day count summary
                    Text("\(task.dates.count) day\(task.dates.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(taskColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(taskColor.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Calendar Scale Toggle (Custom Three-Option Toggle)
struct CalendarScaleToggle: View {
    @Binding var selectedScale: Models.CalendarScale
    @Environment(\.colorScheme) private var colorScheme
    
    private let scales: [Models.CalendarScale] = [.daily, .weekly, .monthly]
    
    // Helper computed properties
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }
    
    // Calculate the selected index for animation
    private var selectedIndex: Int {
        scales.firstIndex(of: selectedScale) ?? 0
    }
    
    private func textColor(for scale: Models.CalendarScale) -> Color {
        if selectedScale == scale {
            return .white
        } else {
            return colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let buttonWidth = geometry.size.width / CGFloat(scales.count)
            
            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: 18)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(strokeColor, lineWidth: 1)
                    )
                
                // Sliding background indicator
        HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.brandPrimary)
                        .frame(width: buttonWidth)
                        .offset(x: CGFloat(selectedIndex) * buttonWidth)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
                    
                    Spacer()
                }
                
                // Buttons overlay
                HStack(spacing: 0) {
                    ForEach(Array(scales.enumerated()), id: \.element) { index, scale in
                        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedScale = scale
            }
        }) {
            Text(scale.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(textColor(for: scale))
                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
                }
            }
        }
        .frame(height: 44)
    }
}

#Preview {
    CalendarView(selectedFeature: .constant(.calendar))
}
