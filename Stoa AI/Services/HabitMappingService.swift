import Foundation

/// Service for mapping new habit JSON structure to calendar dates
class HabitMappingService {
    static let shared = HabitMappingService()
    
    private init() {}
    
    // MARK: - Main Mapping Functions
    
    /// Maps daily habits from days_indexed to calendar dates
    /// - Parameters:
    ///   - habit: The habit JSON structure
    ///   - startDate: The date when the habit starts (from createdAt or startDate)
    /// - Returns: Dictionary mapping calendar dates to habit card data
    func dailyHabitMapping(habit: NewHabitJSON, startDate: Date) -> [Date: HabitCardData] {
        var result: [Date: HabitCardData] = [:]
        let calendar = Calendar.current
        
        guard let lowLevelSchedule = habit.lowLevelSchedule,
              let program = lowLevelSchedule.program.first else {
            return result
        }
        
        // Extract days_indexed items
        let daysIndexed = program.daysIndexed
        
        // Calculate habit duration constraints
        let habitSchedule = lowLevelSchedule.habitSchedule
        let spanValue = lowLevelSchedule.spanValue
        let habitRepeatCount = lowLevelSchedule.habitRepeatCount
        
        // Calculate maximum date based on constraints
        var maxDate: Date?
        if let habitRepeatCount = habitRepeatCount {
            // Calculate end date: startDate + (span * spanValue * habitRepeatCount)
            let totalDays = calculateTotalDays(
                span: lowLevelSchedule.span,
                spanValue: spanValue,
                habitRepeatCount: habitRepeatCount
            )
            maxDate = calendar.date(byAdding: .day, value: totalDays, to: startDate)
        } else if let habitSchedule = habitSchedule, habitSchedule > 0 {
            // Use habit_schedule as maximum duration
            maxDate = calendar.date(byAdding: .day, value: Int(habitSchedule), to: startDate)
        }
        
        // For index 1 (first day), check if any step time is earlier than creation time
        // If so, push it to the next day
        var shouldPushIndex1 = false
        if let firstDayItem = daysIndexed.first(where: { $0.index == 1 }) {
            let creationTime = calendar.component(.hour, from: startDate) * 60 + calendar.component(.minute, from: startDate)
            
            // Check if any step has a clock time earlier than creation time
            let hasEarlierStep = firstDayItem.content.contains { stepContent in
                guard let clockTime = stepContent.clock else {
                    return false // No time specified, can be done anytime
                }
                
                // Parse clock time (HH:MM format)
                let timeComponents = clockTime.split(separator: ":")
                guard timeComponents.count == 2,
                      let hour = Int(timeComponents[0]),
                      let minute = Int(timeComponents[1]),
                      hour >= 0, hour < 24,
                      minute >= 0, minute < 60 else {
                    return false
                }
                
                let stepTime = hour * 60 + minute
                return stepTime < creationTime
            }
            
            // If any step is earlier than creation time, push index 1 to next day
            shouldPushIndex1 = hasEarlierStep
        }
        
        // For infinite habits, generate dates for a reasonable range (1 year)
        // For finite habits, only generate dates within the defined cycle
        let isInfinite = (habitRepeatCount == nil && habitSchedule == nil)
        let cycleLength = Int(spanValue)
        
        // Determine how many cycles to generate
        var cyclesToGenerate: Int
        if isInfinite {
            // For infinite habits, generate enough cycles to cover 1 year
            // This ensures calendar views have enough data
            cyclesToGenerate = max(365 / cycleLength, 1)
        } else if let habitRepeatCount = habitRepeatCount {
            cyclesToGenerate = Int(habitRepeatCount)
        } else if let habitSchedule = habitSchedule {
            // Calculate cycles based on habit_schedule
            cyclesToGenerate = max(Int(habitSchedule) / cycleLength, 1)
        } else {
            cyclesToGenerate = 1
        }
        
        // Generate dates for each cycle
        for cycle in 0..<cyclesToGenerate {
            for dayItem in daysIndexed {
                let dayIndex = dayItem.index
                
                // Calculate the day offset: (cycle * cycleLength) + (dayIndex - 1)
                // Adjust if index 1 should be pushed
                let baseOffset = (cycle * cycleLength) + (dayIndex - 1)
                let adjustedDayIndex = baseOffset + (shouldPushIndex1 ? 1 : 0)
                
                guard let targetDate = calendar.date(byAdding: .day, value: adjustedDayIndex, to: startDate) else {
                    continue
                }
                
                // Check if date is within constraints
                if let maxDate = maxDate, targetDate > maxDate {
                    continue
                }
                
                // Normalize date to start of day
                let normalizedDate = calendar.startOfDay(for: targetDate)
                
                // Extract steps with clock times
                let steps = dayItem.content.map { stepContent in
                    HabitStepDisplay(
                        step: stepContent.step,
                        clock: stepContent.clock,
                        day: nil,
                        dayOfMonth: nil
                    )
                }
                
                // Extract reminders
                let reminders = dayItem.reminders.map { reminder in
                    HabitReminderDisplay(
                        time: reminder.time,
                        message: reminder.message
                    )
                }
                
                // Create habit card data
                let cardData = HabitCardData(
                    habitId: habit.id ?? UUID().uuidString,
                    name: habit.name,
                    goal: habit.goal,
                    category: habit.category,
                    description: habit.description,
                    difficulty: habit.difficulty,
                    title: dayItem.title,
                    steps: steps,
                    reminders: reminders
                )
                
                result[normalizedDate] = cardData
            }
        }
        
        // ALSO process weeks_indexed to include matching weekdays in daily view
        // This ensures habits like "every Monday for one month" show on all 4 Mondays
        let weeksIndexed = program.weeksIndexed
        if !weeksIndexed.isEmpty {
            // For each week item in weeks_indexed
            for weekItem in weeksIndexed {
                let weekIndex = weekItem.index
                
                // Group steps by day name to find all matching weekdays
                var stepsByDay: [String: [HabitStepDisplay]] = [:]
                for stepContent in weekItem.content {
                    let dayName = stepContent.day
                    if stepsByDay[dayName] == nil {
                        stepsByDay[dayName] = []
                    }
                    stepsByDay[dayName]?.append(HabitStepDisplay(
                        step: stepContent.step,
                        clock: nil,
                        day: dayName,
                        dayOfMonth: nil
                    ))
                }
                
                // For each day name in this week item, find all matching dates
                for (dayName, steps) in stepsByDay {
                    
                    // Calculate how many cycles to check based on habit constraints
                    let weekCyclesToCheck: Int
                    if isInfinite {
                        // For infinite habits, check up to 1 year
                        weekCyclesToCheck = max(52 / Int(spanValue), 1)
                    } else if let habitRepeatCount = habitRepeatCount {
                        weekCyclesToCheck = Int(habitRepeatCount)
                    } else if let habitSchedule = habitSchedule {
                        // Convert days to weeks (approximate)
                        weekCyclesToCheck = max(Int(habitSchedule) / (Int(spanValue) * 7), 1)
                    } else {
                        weekCyclesToCheck = 1
                    }
                    
                    // Generate dates for each cycle
                    for weekCycle in 0..<weekCyclesToCheck {
                        // Calculate the week offset: (weekCycle * cycleLength) + (weekIndex - 1)
                        let weekOffset = (weekCycle * Int(spanValue)) + (weekIndex - 1)
                        
                        // Calculate the start of the target week
                        guard let weekStartDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startDate) else {
                            continue
                        }
                        
                        // Get the start of the week (Monday) for the target week
                        let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekStartDate)?.start ?? weekStartDate
                        
                        // Find the specific day of week within this week
                        guard let targetDate = findDayOfWeek(dayName, in: weekStart, calendar: calendar) else {
                            continue
                        }
                        
                        // Check if date is within constraints
                        if let maxDate = maxDate, targetDate > maxDate {
                            continue
                        }
                        
                        // Normalize date to start of day
                        let normalizedDate = calendar.startOfDay(for: targetDate)
                        
                        // Extract reminders
                        let reminders = weekItem.reminders.map { reminder in
                            HabitReminderDisplay(
                                time: reminder.time,
                                message: reminder.message
                            )
                        }
                        
                        // Create or merge habit card data for this date
                        if let existingCard = result[normalizedDate] {
                            // Merge with existing data (from days_indexed)
                            let mergedSteps = existingCard.steps + steps
                            let mergedReminders = existingCard.reminders + reminders
                            
                            // Remove duplicate reminders
                            var uniqueReminders: [HabitReminderDisplay] = []
                            var seenReminders: Set<String> = []
                            for reminder in mergedReminders {
                                let key = "\(reminder.time ?? "")|\(reminder.message ?? "")"
                                if !seenReminders.contains(key) {
                                    seenReminders.insert(key)
                                    uniqueReminders.append(reminder)
                                }
                            }
                            
                            // Combine titles
                            let combinedTitle = existingCard.title.isEmpty ? weekItem.title : "\(existingCard.title) | \(weekItem.title)"
                            let combinedDescription = existingCard.description.isEmpty ? weekItem.description : "\(existingCard.description) | \(weekItem.description)"
                            
                            let mergedCard = HabitCardData(
                                habitId: existingCard.habitId,
                                name: existingCard.name,
                                goal: existingCard.goal,
                                category: existingCard.category,
                                description: combinedDescription,
                                difficulty: existingCard.difficulty,
                                title: combinedTitle,
                                steps: mergedSteps,
                                reminders: uniqueReminders
                            )
                            result[normalizedDate] = mergedCard
                        } else {
                            // Create new card data for this date
                            let cardData = HabitCardData(
                                habitId: habit.id ?? UUID().uuidString,
                                name: habit.name,
                                goal: habit.goal,
                                category: habit.category,
                                description: weekItem.description,
                                difficulty: habit.difficulty,
                                title: weekItem.title,
                                steps: steps,
                                reminders: reminders
                            )
                            result[normalizedDate] = cardData
                        }
                    }
                }
            }
        }
        
        // ALSO process months_indexed to include matching day-of-month dates in daily view
        // This ensures habits like "15th of every month" show on all matching dates
        let monthsIndexed = program.monthsIndexed
        if !monthsIndexed.isEmpty {
            // For each month item in months_indexed
            for monthItem in monthsIndexed {
                let monthIndex = monthItem.index
                
                // Group steps by day to avoid overwriting entries
                var stepsByDay: [Int: [HabitStepDisplay]] = [:]
                for stepContent in monthItem.content {
                    let daySpec = stepContent.day
                    
                    // Calculate the actual day of month
                    let dayOfMonth: Int
                    if daySpec == "end_of_month" {
                        // Will be calculated per month cycle
                        dayOfMonth = -1 // Special marker for end of month
                    } else if daySpec == "start_of_month" {
                        dayOfMonth = 1
                    } else {
                        // Parse day number (1-31)
                        guard let dayNum = Int(daySpec) else {
                            continue
                        }
                        dayOfMonth = dayNum
                    }
                    
                    if stepsByDay[dayOfMonth] == nil {
                        stepsByDay[dayOfMonth] = []
                    }
                    stepsByDay[dayOfMonth]?.append(HabitStepDisplay(
                        step: stepContent.step,
                        clock: nil,
                        day: nil,
                        dayOfMonth: dayOfMonth == -1 ? nil : dayOfMonth
                    ))
                }
                
                // Calculate how many cycles to check based on habit constraints
                let monthCyclesToCheck: Int
                if isInfinite {
                    // For infinite habits, check up to 2 years
                    monthCyclesToCheck = max(24 / Int(spanValue), 1)
                } else if let habitRepeatCount = habitRepeatCount {
                    monthCyclesToCheck = Int(habitRepeatCount)
                } else if let habitSchedule = habitSchedule {
                    // Convert days to months (approximate)
                    monthCyclesToCheck = max(Int(habitSchedule) / (Int(spanValue) * 30), 1)
                } else {
                    monthCyclesToCheck = 1
                }
                
                // Generate dates for each cycle
                for monthCycle in 0..<monthCyclesToCheck {
                    // Calculate the month offset: (monthCycle * cycleLength) + (monthIndex - 1)
                    let monthOffset = (monthCycle * Int(spanValue)) + (monthIndex - 1)
                    
                    // Calculate the target month (first day of the month)
                    guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: startDate) else {
                        continue
                    }
                    
                    // Get the first day of the target month
                    let targetMonthComponents = calendar.dateComponents([.year, .month], from: targetMonth)
                    guard let firstDayOfMonth = calendar.date(from: targetMonthComponents) else {
                        continue
                    }
                    
                    // Process each day with its steps
                    for (daySpecKey, steps) in stepsByDay {
                        let dayOfMonth: Int
                        if daySpecKey == -1 {
                            // End of month - get the last day of the target month
                            guard let monthRange = calendar.range(of: .day, in: .month, for: firstDayOfMonth),
                                  let lastDay = monthRange.last else {
                                continue
                            }
                            dayOfMonth = lastDay
                        } else {
                            dayOfMonth = daySpecKey
                        }
                        
                        // Validate day is within month range
                        guard let monthRange = calendar.range(of: .day, in: .month, for: firstDayOfMonth) else {
                            continue
                        }
                        let validDayOfMonth = min(dayOfMonth, monthRange.count)
                        
                        // Get the target date in the target month
                        guard let targetDate = calendar.date(bySettingDay: validDayOfMonth, of: firstDayOfMonth) else {
                            continue
                        }
                        
                        // Check if date is within constraints
                        if let maxDate = maxDate, targetDate > maxDate {
                            continue
                        }
                        
                        // Normalize date to start of day
                        let normalizedDate = calendar.startOfDay(for: targetDate)
                        
                        // Extract reminders
                        let reminders = monthItem.reminders.map { reminder in
                            HabitReminderDisplay(
                                time: reminder.time,
                                message: reminder.message
                            )
                        }
                        
                        // Create or merge habit card data for this date
                        if let existingCard = result[normalizedDate] {
                            // Merge with existing data (from days_indexed or weeks_indexed)
                            let mergedSteps = existingCard.steps + steps
                            let mergedReminders = existingCard.reminders + reminders
                            
                            // Remove duplicate reminders
                            var uniqueReminders: [HabitReminderDisplay] = []
                            var seenReminders: Set<String> = []
                            for reminder in mergedReminders {
                                let key = "\(reminder.time ?? "")|\(reminder.message ?? "")"
                                if !seenReminders.contains(key) {
                                    seenReminders.insert(key)
                                    uniqueReminders.append(reminder)
                                }
                            }
                            
                            // Combine titles
                            let combinedTitle = existingCard.title.isEmpty ? monthItem.title : "\(existingCard.title) | \(monthItem.title)"
                            let combinedDescription = existingCard.description.isEmpty ? monthItem.description : "\(existingCard.description) | \(monthItem.description)"
                            
                            let mergedCard = HabitCardData(
                                habitId: existingCard.habitId,
                                name: existingCard.name,
                                goal: existingCard.goal,
                                category: existingCard.category,
                                description: combinedDescription,
                                difficulty: existingCard.difficulty,
                                title: combinedTitle,
                                steps: mergedSteps,
                                reminders: uniqueReminders
                            )
                            result[normalizedDate] = mergedCard
                        } else {
                            // Create new card data for this date
                            let cardData = HabitCardData(
                                habitId: habit.id ?? UUID().uuidString,
                                name: habit.name,
                                goal: habit.goal,
                                category: habit.category,
                                description: monthItem.description,
                                difficulty: habit.difficulty,
                                title: monthItem.title,
                                steps: steps,
                                reminders: reminders
                            )
                            result[normalizedDate] = cardData
                        }
                    }
                }
            }
        }
        
        return result
    }
    
    /// Maps habits for weekly view - processes days_indexed, weeks_indexed, and months_indexed
    /// Shows basic/summarized information for weekly calendar display
    /// - Parameters:
    ///   - habit: The habit JSON structure
    ///   - startDate: The date when the habit starts
    /// - Returns: Dictionary mapping calendar dates to habit card data (with basic info)
    func weeklyHabitMapping(habit: NewHabitJSON, startDate: Date) -> [Date: HabitCardData] {
        var result: [Date: HabitCardData] = [:]
        let calendar = Calendar.current
        
        guard let lowLevelSchedule = habit.lowLevelSchedule,
              let program = lowLevelSchedule.program.first else {
            return result
        }
        
        // Extract all indexed items
        let daysIndexed = program.daysIndexed
        let weeksIndexed = program.weeksIndexed
        let monthsIndexed = program.monthsIndexed
        
        // Calculate habit duration constraints
        let habitSchedule = lowLevelSchedule.habitSchedule
        let spanValue = lowLevelSchedule.spanValue
        let habitRepeatCount = lowLevelSchedule.habitRepeatCount
        
        // Calculate maximum date based on constraints
        var maxDate: Date?
        if let habitRepeatCount = habitRepeatCount {
            let totalDays = calculateTotalDays(
                span: lowLevelSchedule.span,
                spanValue: spanValue,
                habitRepeatCount: habitRepeatCount
            )
            maxDate = calendar.date(byAdding: .day, value: totalDays, to: startDate)
        } else if let habitSchedule = habitSchedule, habitSchedule > 0 {
            maxDate = calendar.date(byAdding: .day, value: Int(habitSchedule), to: startDate)
        }
        
        let isInfinite = (habitRepeatCount == nil && habitSchedule == nil)
        let cycleLength = Int(spanValue)
        
        // MARK: Process days_indexed (with basic info)
        if !daysIndexed.isEmpty {
            var cyclesToGenerate: Int
            if isInfinite {
                cyclesToGenerate = max(365 / cycleLength, 1)
            } else if let habitRepeatCount = habitRepeatCount {
                cyclesToGenerate = Int(habitRepeatCount)
            } else if let habitSchedule = habitSchedule {
                cyclesToGenerate = max(Int(habitSchedule) / cycleLength, 1)
            } else {
                cyclesToGenerate = 1
            }
            
            for cycle in 0..<cyclesToGenerate {
                for dayItem in daysIndexed {
                    let dayIndex = dayItem.index
                    let dayOffset = (cycle * cycleLength) + (dayIndex - 1)
                    
                    guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                        continue
                    }
                    
                    if let maxDate = maxDate, targetDate > maxDate {
                        continue
                    }
                    
                    let normalizedDate = calendar.startOfDay(for: targetDate)
                    
                    // Create basic info: just count of steps, simplified title
                    let stepCount = dayItem.content.count
                    let basicSteps = [HabitStepDisplay(
                        step: "\(stepCount) step\(stepCount == 1 ? "" : "s") scheduled",
                        clock: nil,
                        day: nil,
                        dayOfMonth: nil
                    )]
                    
                    let cardData = HabitCardData(
                        habitId: habit.id ?? UUID().uuidString,
                        name: habit.name,
                        goal: habit.goal,
                        category: habit.category,
                        description: habit.description, // Basic description
                        difficulty: habit.difficulty,
                        title: dayItem.title.isEmpty ? habit.name : dayItem.title,
                        steps: basicSteps,
                        reminders: [] // No reminders for weekly view
                    )
                    
                    // Merge if date already exists
                    if let existing = result[normalizedDate] {
                        let mergedSteps = existing.steps + basicSteps
                        let mergedTitle = existing.title.isEmpty ? cardData.title : "\(existing.title) | \(cardData.title)"
                        result[normalizedDate] = HabitCardData(
                            habitId: existing.habitId,
                            name: existing.name,
                            goal: existing.goal,
                            category: existing.category,
                            description: existing.description,
                            difficulty: existing.difficulty,
                            title: mergedTitle,
                            steps: mergedSteps,
                            reminders: existing.reminders
                        )
                    } else {
                        result[normalizedDate] = cardData
                    }
                }
            }
        }
        
        // MARK: Process weeks_indexed (with basic info)
        if !weeksIndexed.isEmpty {
            var cyclesToGenerate: Int
            if isInfinite {
                cyclesToGenerate = max(52 / cycleLength, 1)
            } else if let habitRepeatCount = habitRepeatCount {
                cyclesToGenerate = Int(habitRepeatCount)
            } else if let habitSchedule = habitSchedule {
                cyclesToGenerate = max(Int(habitSchedule) / (cycleLength * 7), 1)
            } else {
                cyclesToGenerate = 1
            }
            
            for cycle in 0..<cyclesToGenerate {
                for weekItem in weeksIndexed {
                    let weekIndex = weekItem.index
                    let weekOffset = (cycle * cycleLength) + (weekIndex - 1)
                    
                    guard let weekStartDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startDate) else {
                        continue
                    }
                    
                    let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekStartDate)?.start ?? weekStartDate
                    
                    // Group steps by day
                    var stepsByDay: [String: [String]] = [:]
                    for stepContent in weekItem.content {
                        let dayName = stepContent.day
                        if stepsByDay[dayName] == nil {
                            stepsByDay[dayName] = []
                        }
                        stepsByDay[dayName]?.append(stepContent.step)
                    }
                    
                    // Process each day
                    for (dayName, stepTexts) in stepsByDay {
                        guard let targetDate = findDayOfWeek(dayName, in: weekStart, calendar: calendar) else {
                            continue
                        }
                        
                        if let maxDate = maxDate, targetDate > maxDate {
                            continue
                        }
                        
                        let normalizedDate = calendar.startOfDay(for: targetDate)
                        
                        // Create basic info: day name and step count
                        let stepCount = stepTexts.count
                        let basicSteps = [HabitStepDisplay(
                            step: "\(dayName): \(stepCount) step\(stepCount == 1 ? "" : "s")",
                            clock: nil,
                            day: dayName,
                            dayOfMonth: nil
                        )]
                        
                        let cardData = HabitCardData(
                            habitId: habit.id ?? UUID().uuidString,
                            name: habit.name,
                            goal: habit.goal,
                            category: habit.category,
                            description: weekItem.description.isEmpty ? habit.description : weekItem.description,
                            difficulty: habit.difficulty,
                            title: weekItem.title.isEmpty ? habit.name : weekItem.title,
                            steps: basicSteps,
                            reminders: [] // No reminders for weekly view
                        )
                        
                        // Merge if date already exists
                        if let existing = result[normalizedDate] {
                            let mergedSteps = existing.steps + basicSteps
                            let mergedTitle = existing.title.isEmpty ? cardData.title : "\(existing.title) | \(cardData.title)"
                            result[normalizedDate] = HabitCardData(
                                habitId: existing.habitId,
                                name: existing.name,
                                goal: existing.goal,
                                category: existing.category,
                                description: existing.description,
                                difficulty: existing.difficulty,
                                title: mergedTitle,
                                steps: mergedSteps,
                                reminders: existing.reminders
                            )
                        } else {
                            result[normalizedDate] = cardData
                        }
                    }
                }
            }
        }
        
        // MARK: Process months_indexed (with basic info)
        if !monthsIndexed.isEmpty {
            var cyclesToGenerate: Int
            if isInfinite {
                cyclesToGenerate = max(24 / cycleLength, 1)
            } else if let habitRepeatCount = habitRepeatCount {
                cyclesToGenerate = Int(habitRepeatCount)
            } else if let habitSchedule = habitSchedule {
                cyclesToGenerate = max(Int(habitSchedule) / (cycleLength * 30), 1)
            } else {
                cyclesToGenerate = 1
            }
            
            for cycle in 0..<cyclesToGenerate {
                for monthItem in monthsIndexed {
                    let monthIndex = monthItem.index
                    let monthOffset = (cycle * Int(spanValue)) + (monthIndex - 1)
                    
                    guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: startDate) else {
                        continue
                    }
                    
                    let targetMonthComponents = calendar.dateComponents([.year, .month], from: targetMonth)
                    guard let firstDayOfMonth = calendar.date(from: targetMonthComponents) else {
                        continue
                    }
                    
                    // Group steps by day
                    var stepsByDay: [Int: [String]] = [:]
                    for stepContent in monthItem.content {
                        let daySpec = stepContent.day
                        let dayOfMonth: Int
                        
                        if daySpec == "end_of_month" {
                            dayOfMonth = -1
                        } else if daySpec == "start_of_month" {
                            dayOfMonth = 1
                        } else {
                            guard let dayNum = Int(daySpec) else { continue }
                            dayOfMonth = dayNum
                        }
                        
                        if stepsByDay[dayOfMonth] == nil {
                            stepsByDay[dayOfMonth] = []
                        }
                        stepsByDay[dayOfMonth]?.append(stepContent.step)
                    }
                    
                    // Process each day
                    for (daySpecKey, stepTexts) in stepsByDay {
                        let dayOfMonth: Int
                        if daySpecKey == -1 {
                            guard let monthRange = calendar.range(of: .day, in: .month, for: firstDayOfMonth),
                                  let lastDay = monthRange.last else {
                                continue
                            }
                            dayOfMonth = lastDay
                        } else {
                            dayOfMonth = daySpecKey
                        }
                        
                        guard let monthRange = calendar.range(of: .day, in: .month, for: firstDayOfMonth) else {
                            continue
                        }
                        let validDayOfMonth = min(dayOfMonth, monthRange.count)
                        
                        guard let targetDate = calendar.date(bySettingDay: validDayOfMonth, of: firstDayOfMonth) else {
                            continue
                        }
                        
                        if let maxDate = maxDate, targetDate > maxDate {
                            continue
                        }
                        
                        let normalizedDate = calendar.startOfDay(for: targetDate)
                        
                        // Create basic info: day of month and step count
                        let stepCount = stepTexts.count
                        let dayLabel = daySpecKey == -1 ? "End of month" : "Day \(validDayOfMonth)"
                        let basicSteps = [HabitStepDisplay(
                            step: "\(dayLabel): \(stepCount) step\(stepCount == 1 ? "" : "s")",
                            clock: nil,
                            day: nil,
                            dayOfMonth: validDayOfMonth
                        )]
                        
                        let cardData = HabitCardData(
                            habitId: habit.id ?? UUID().uuidString,
                            name: habit.name,
                            goal: habit.goal,
                            category: habit.category,
                            description: monthItem.description.isEmpty ? habit.description : monthItem.description,
                            difficulty: habit.difficulty,
                            title: monthItem.title.isEmpty ? habit.name : monthItem.title,
                            steps: basicSteps,
                            reminders: [] // No reminders for weekly view
                        )
                        
                        // Merge if date already exists
                        if let existing = result[normalizedDate] {
                            let mergedSteps = existing.steps + basicSteps
                            let mergedTitle = existing.title.isEmpty ? cardData.title : "\(existing.title) | \(cardData.title)"
                            result[normalizedDate] = HabitCardData(
                                habitId: existing.habitId,
                                name: existing.name,
                                goal: existing.goal,
                                category: existing.category,
                                description: existing.description,
                                difficulty: existing.difficulty,
                                title: mergedTitle,
                                steps: mergedSteps,
                                reminders: existing.reminders
                            )
                        } else {
                            result[normalizedDate] = cardData
                        }
                    }
                }
            }
        }
        
        return result
    }
    
    /// Maps habits for monthly view - processes days_indexed, weeks_indexed, and months_indexed
    /// Shows minimal/general information for monthly calendar display
    /// - Parameters:
    ///   - habit: The habit JSON structure
    ///   - startDate: The date when the habit starts
    /// - Returns: Dictionary mapping calendar dates to habit card data (with minimal info)
    func monthlyHabitMapping(habit: NewHabitJSON, startDate: Date) -> [Date: HabitCardData] {
        var result: [Date: HabitCardData] = [:]
        let calendar = Calendar.current
        
        guard let lowLevelSchedule = habit.lowLevelSchedule,
              let program = lowLevelSchedule.program.first else {
            return result
        }
        
        // Extract all indexed items
        let daysIndexed = program.daysIndexed
        let weeksIndexed = program.weeksIndexed
        let monthsIndexed = program.monthsIndexed
        
        // Calculate habit duration constraints
        let habitSchedule = lowLevelSchedule.habitSchedule
        let spanValue = lowLevelSchedule.spanValue
        let habitRepeatCount = lowLevelSchedule.habitRepeatCount
        
        // Calculate maximum date based on constraints
        var maxDate: Date?
        if let habitRepeatCount = habitRepeatCount {
            let totalDays = calculateTotalDays(
                span: lowLevelSchedule.span,
                spanValue: spanValue,
                habitRepeatCount: habitRepeatCount
            )
            maxDate = calendar.date(byAdding: .day, value: totalDays, to: startDate)
        } else if let habitSchedule = habitSchedule, habitSchedule > 0 {
            maxDate = calendar.date(byAdding: .day, value: Int(habitSchedule), to: startDate)
        }
        
        let isInfinite = (habitRepeatCount == nil && habitSchedule == nil)
        let cycleLength = Int(spanValue)
        
        // MARK: Process days_indexed (with minimal info)
        if !daysIndexed.isEmpty {
            var cyclesToGenerate: Int
            if isInfinite {
                cyclesToGenerate = max(365 / cycleLength, 1)
            } else if let habitRepeatCount = habitRepeatCount {
                cyclesToGenerate = Int(habitRepeatCount)
            } else if let habitSchedule = habitSchedule {
                cyclesToGenerate = max(Int(habitSchedule) / cycleLength, 1)
            } else {
                cyclesToGenerate = 1
            }
            
            for cycle in 0..<cyclesToGenerate {
                for dayItem in daysIndexed {
                    let dayIndex = dayItem.index
                    let dayOffset = (cycle * cycleLength) + (dayIndex - 1)
                    
                    guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                        continue
                    }
                    
                    if let maxDate = maxDate, targetDate > maxDate {
                        continue
                    }
                    
                    let normalizedDate = calendar.startOfDay(for: targetDate)
                    
                    // Create minimal info: just habit indicator
                    let minimalSteps = [HabitStepDisplay(
                        step: "Habit activity",
                        clock: nil,
                        day: nil,
                        dayOfMonth: nil
                    )]
                    
                    let cardData = HabitCardData(
                        habitId: habit.id ?? UUID().uuidString,
                        name: habit.name,
                        goal: habit.goal,
                        category: habit.category,
                        description: habit.description,
                        difficulty: habit.difficulty,
                        title: habit.name, // Just habit name for monthly view
                        steps: minimalSteps,
                        reminders: [] // No reminders for monthly view
                    )
                    
                    // Merge if date already exists
                    if let existing = result[normalizedDate] {
                        // Just update title to show multiple habits
                        let mergedTitle = existing.title == habit.name ? existing.title : "\(existing.title) + \(habit.name)"
                        result[normalizedDate] = HabitCardData(
                            habitId: existing.habitId,
                            name: existing.name,
                            goal: existing.goal,
                            category: existing.category,
                            description: existing.description,
                            difficulty: existing.difficulty,
                            title: mergedTitle,
                            steps: existing.steps,
                            reminders: existing.reminders
                        )
                    } else {
                        result[normalizedDate] = cardData
                    }
                }
            }
        }
        
        // MARK: Process weeks_indexed (with minimal info)
        if !weeksIndexed.isEmpty {
            var cyclesToGenerate: Int
            if isInfinite {
                cyclesToGenerate = max(52 / cycleLength, 1)
            } else if let habitRepeatCount = habitRepeatCount {
                cyclesToGenerate = Int(habitRepeatCount)
            } else if let habitSchedule = habitSchedule {
                cyclesToGenerate = max(Int(habitSchedule) / (cycleLength * 7), 1)
            } else {
                cyclesToGenerate = 1
            }
            
            for cycle in 0..<cyclesToGenerate {
                for weekItem in weeksIndexed {
                    let weekIndex = weekItem.index
                    let weekOffset = (cycle * cycleLength) + (weekIndex - 1)
                    
                    guard let weekStartDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startDate) else {
                        continue
                    }
                    
                    let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekStartDate)?.start ?? weekStartDate
                    
                    // Collect all unique days for this week item
                    var uniqueDays = Set<String>()
                    for stepContent in weekItem.content {
                        uniqueDays.insert(stepContent.day)
                    }
                    
                    // Process each day
                    for dayName in uniqueDays {
                        guard let targetDate = findDayOfWeek(dayName, in: weekStart, calendar: calendar) else {
                            continue
                        }
                        
                        if let maxDate = maxDate, targetDate > maxDate {
                            continue
                        }
                        
                        let normalizedDate = calendar.startOfDay(for: targetDate)
                        
                        // Create minimal info: just habit indicator
                        let minimalSteps = [HabitStepDisplay(
                            step: "Habit activity",
                            clock: nil,
                            day: dayName,
                            dayOfMonth: nil
                        )]
                        
                        let cardData = HabitCardData(
                            habitId: habit.id ?? UUID().uuidString,
                            name: habit.name,
                            goal: habit.goal,
                            category: habit.category,
                            description: habit.description,
                            difficulty: habit.difficulty,
                            title: habit.name, // Just habit name for monthly view
                            steps: minimalSteps,
                            reminders: [] // No reminders for monthly view
                        )
                        
                        // Merge if date already exists
                        if let existing = result[normalizedDate] {
                            let mergedTitle = existing.title == habit.name ? existing.title : "\(existing.title) + \(habit.name)"
                            result[normalizedDate] = HabitCardData(
                                habitId: existing.habitId,
                                name: existing.name,
                                goal: existing.goal,
                                category: existing.category,
                                description: existing.description,
                                difficulty: existing.difficulty,
                                title: mergedTitle,
                                steps: existing.steps,
                                reminders: existing.reminders
                            )
                        } else {
                            result[normalizedDate] = cardData
                        }
                    }
                }
            }
        }
        
        // MARK: Process months_indexed (with minimal info)
        if !monthsIndexed.isEmpty {
            var cyclesToGenerate: Int
            if isInfinite {
                cyclesToGenerate = max(24 / cycleLength, 1)
            } else if let habitRepeatCount = habitRepeatCount {
                cyclesToGenerate = Int(habitRepeatCount)
            } else if let habitSchedule = habitSchedule {
                cyclesToGenerate = max(Int(habitSchedule) / (cycleLength * 30), 1)
            } else {
                cyclesToGenerate = 1
            }
            
            for cycle in 0..<cyclesToGenerate {
                for monthItem in monthsIndexed {
                    let monthIndex = monthItem.index
                    let monthOffset = (cycle * Int(spanValue)) + (monthIndex - 1)
                    
                    guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: startDate) else {
                        continue
                    }
                    
                    let targetMonthComponents = calendar.dateComponents([.year, .month], from: targetMonth)
                    guard let firstDayOfMonth = calendar.date(from: targetMonthComponents) else {
                        continue
                    }
                    
                    // Collect all unique days for this month item
                    var uniqueDays = Set<Int>()
                    for stepContent in monthItem.content {
                        let daySpec = stepContent.day
                        if daySpec == "end_of_month" {
                            uniqueDays.insert(-1) // Special marker
                        } else if daySpec == "start_of_month" {
                            uniqueDays.insert(1)
                        } else if let dayNum = Int(daySpec) {
                            uniqueDays.insert(dayNum)
                        }
                    }
                    
                    // Process each day
                    for daySpecKey in uniqueDays {
                        let dayOfMonth: Int
                        if daySpecKey == -1 {
                            guard let monthRange = calendar.range(of: .day, in: .month, for: firstDayOfMonth),
                                  let lastDay = monthRange.last else {
                                continue
                            }
                            dayOfMonth = lastDay
                        } else {
                            dayOfMonth = daySpecKey
                        }
                        
                        guard let monthRange = calendar.range(of: .day, in: .month, for: firstDayOfMonth) else {
                            continue
                        }
                        let validDayOfMonth = min(dayOfMonth, monthRange.count)
                        
                        guard let targetDate = calendar.date(bySettingDay: validDayOfMonth, of: firstDayOfMonth) else {
                            continue
                        }
                        
                        if let maxDate = maxDate, targetDate > maxDate {
                            continue
                        }
                        
                        let normalizedDate = calendar.startOfDay(for: targetDate)
                        
                        // Create minimal info: just habit indicator
                        let minimalSteps = [HabitStepDisplay(
                            step: "Habit activity",
                            clock: nil,
                            day: nil,
                            dayOfMonth: validDayOfMonth
                        )]
                        
                        let cardData = HabitCardData(
                            habitId: habit.id ?? UUID().uuidString,
                            name: habit.name,
                            goal: habit.goal,
                            category: habit.category,
                            description: habit.description,
                            difficulty: habit.difficulty,
                            title: habit.name, // Just habit name for monthly view
                            steps: minimalSteps,
                            reminders: [] // No reminders for monthly view
                        )
                        
                        // Merge if date already exists
                        if let existing = result[normalizedDate] {
                            let mergedTitle = existing.title == habit.name ? existing.title : "\(existing.title) + \(habit.name)"
                            result[normalizedDate] = HabitCardData(
                                habitId: existing.habitId,
                                name: existing.name,
                                goal: existing.goal,
                                category: existing.category,
                                description: existing.description,
                                difficulty: existing.difficulty,
                                title: mergedTitle,
                                steps: existing.steps,
                                reminders: existing.reminders
                            )
                        } else {
                            result[normalizedDate] = cardData
                        }
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - Combined Mapping Functions
    
    /// Calendar view type for determining which mappings to combine
    enum CalendarViewType {
        case daily    // Show all: daily + weekly + monthly
        case weekly   // Show weekly + monthly (exclude daily)
        case monthly  // Show only monthly (exclude daily and weekly)
    }
    
    /// Combines mapping functions based on calendar view type
    /// - Daily View: Shows all content from days_indexed, weeks_indexed, and months_indexed
    /// - Weekly View: Shows content from weeks_indexed and months_indexed (excludes daily)
    /// - Monthly View: Shows only content from months_indexed (excludes daily and weekly)
    /// - Parameters:
    ///   - habit: The habit JSON structure
    ///   - startDate: The date when the habit starts
    ///   - viewType: The calendar view type (daily, weekly, or monthly)
    /// - Returns: Dictionary mapping calendar dates to combined habit card data
    func combineMappingsForView(habit: NewHabitJSON, startDate: Date, viewType: CalendarViewType) -> [Date: HabitCardData] {
        var combinedResult: [Date: HabitCardData] = [:]
        
        // Get results from mapping functions based on view type
        let dailyResults = viewType == .daily ? dailyHabitMapping(habit: habit, startDate: startDate) : [:]
        let weeklyResults = (viewType == .daily || viewType == .weekly) ? weeklyHabitMapping(habit: habit, startDate: startDate) : [:]
        let monthlyResults = monthlyHabitMapping(habit: habit, startDate: startDate) // Always included
        
        // Collect all unique dates from enabled sources
        var allDates = Set(monthlyResults.keys)
        if viewType == .daily || viewType == .weekly {
            allDates = allDates.union(Set(weeklyResults.keys))
        }
        if viewType == .daily {
            allDates = allDates.union(Set(dailyResults.keys))
        }
        
        // For each date, combine content from enabled sources
        for date in allDates {
            var combinedSteps: [HabitStepDisplay] = []
            var combinedReminders: [HabitReminderDisplay] = []
            var titles: [String] = []
            var descriptions: [String] = []
            
            // Add daily content if enabled (daily view only)
            if viewType == .daily, let dailyCard = dailyResults[date] {
                combinedSteps.append(contentsOf: dailyCard.steps)
                combinedReminders.append(contentsOf: dailyCard.reminders)
                titles.append(dailyCard.title)
                descriptions.append(dailyCard.description)
            }
            
            // Add weekly content if enabled (daily or weekly view)
            if (viewType == .daily || viewType == .weekly), let weeklyCard = weeklyResults[date] {
                combinedSteps.append(contentsOf: weeklyCard.steps)
                combinedReminders.append(contentsOf: weeklyCard.reminders)
                titles.append(weeklyCard.title)
                descriptions.append(weeklyCard.description)
            }
            
            // Add monthly content (always included)
            if let monthlyCard = monthlyResults[date] {
                combinedSteps.append(contentsOf: monthlyCard.steps)
                combinedReminders.append(contentsOf: monthlyCard.reminders)
                titles.append(monthlyCard.title)
                descriptions.append(monthlyCard.description)
            }
            
            // Use the first available card's metadata as base
            let baseCard = dailyResults[date] ?? weeklyResults[date] ?? monthlyResults[date]
            
            // Combine titles and descriptions
            let combinedTitle = titles.joined(separator: " | ")
            let combinedDescription = descriptions.filter { !$0.isEmpty }.joined(separator: " | ")
            
            // Remove duplicate reminders (same time and message)
            var uniqueReminders: [HabitReminderDisplay] = []
            var seenReminders: Set<String> = []
            for reminder in combinedReminders {
                let key = "\(reminder.time ?? "")|\(reminder.message ?? "")"
                if !seenReminders.contains(key) {
                    seenReminders.insert(key)
                    uniqueReminders.append(reminder)
                }
            }
            
            // Create combined card data
            let combinedCard = HabitCardData(
                habitId: baseCard?.habitId ?? habit.id ?? UUID().uuidString,
                name: baseCard?.name ?? habit.name,
                goal: baseCard?.goal ?? habit.goal,
                category: baseCard?.category ?? habit.category,
                description: combinedDescription.isEmpty ? (baseCard?.description ?? habit.description) : combinedDescription,
                difficulty: baseCard?.difficulty ?? habit.difficulty,
                title: combinedTitle.isEmpty ? (baseCard?.title ?? "Habit Activity") : combinedTitle,
                steps: combinedSteps,
                reminders: uniqueReminders
            )
            
            combinedResult[date] = combinedCard
        }
        
        return combinedResult
    }
    
    /// Convenience function for daily view - combines all three sources
    func combineForDailyView(habit: NewHabitJSON, startDate: Date) -> [Date: HabitCardData] {
        return combineMappingsForView(habit: habit, startDate: startDate, viewType: .daily)
    }
    
    /// Convenience function for weekly view - combines weekly and monthly sources
    func combineForWeeklyView(habit: NewHabitJSON, startDate: Date) -> [Date: HabitCardData] {
        return combineMappingsForView(habit: habit, startDate: startDate, viewType: .weekly)
    }
    
    /// Convenience function for monthly view - shows only monthly source
    func combineForMonthlyView(habit: NewHabitJSON, startDate: Date) -> [Date: HabitCardData] {
        return combineMappingsForView(habit: habit, startDate: startDate, viewType: .monthly)
    }
    
    // MARK: - Helper Functions
    
    /// Calculate total days based on span, spanValue, and habitRepeatCount
    private func calculateTotalDays(span: String, spanValue: Double, habitRepeatCount: Double) -> Int {
        switch span {
        case "day":
            return Int(spanValue * habitRepeatCount)
        case "week":
            return Int(spanValue * habitRepeatCount * 7)
        case "month":
            return Int(spanValue * habitRepeatCount * 30) // Approximate
        case "year":
            return Int(spanValue * habitRepeatCount * 365) // Approximate
        default:
            return Int(spanValue * habitRepeatCount)
        }
    }
    
    /// Find a specific day of week within a given week
    /// Supports both full day names (e.g., "Monday") and abbreviations (e.g., "Mon")
    private func findDayOfWeek(_ dayName: String, in weekStart: Date, calendar: Calendar) -> Date? {
        // Map day names to Calendar weekday values
        // Calendar.weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        let weekdayMap: [String: Int] = [
            // Full day names
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7,
            "sunday": 1,
            // Abbreviations (in case JSON uses shortened forms)
            "mon": 2,
            "tue": 3,
            "wed": 4,
            "thu": 5,
            "fri": 6,
            "sat": 7,
            "sun": 1
        ]
        
        let lowercased = dayName.lowercased().trimmingCharacters(in: .whitespaces)
        guard let targetWeekday = weekdayMap[lowercased] else {
            return nil
        }
        
        // Get the weekday of the week start
        // Calendar.weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        let weekStartWeekday = calendar.component(.weekday, from: weekStart)
        
        // Calculate offset
        var offset = targetWeekday - weekStartWeekday
        if offset < 0 {
            offset += 7
        }
        
        return calendar.date(byAdding: .day, value: offset, to: weekStart)
    }
}

// MARK: - Supporting Models

/// Represents the new habit JSON structure
struct NewHabitJSON: Codable {
    let id: String?
    let name: String
    let goal: String
    let category: String?
    let description: String
    let difficulty: String?
    let highLevelSchedule: HighLevelScheduleNew?
    let lowLevelSchedule: LowLevelScheduleNew?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, goal, category, description, difficulty
        case highLevelSchedule = "high_level_schedule"
        case lowLevelSchedule = "low_level_schedule"
    }
}

/// High-level schedule structure
struct HighLevelScheduleNew: Codable {
    let milestones: [MilestoneNew]
}

/// Milestone structure matching habit.json
struct MilestoneNew: Codable {
    let index: Int
    let description: String
    let completionCriteria: String
    let completionCriteriaPoint: Double // number type in JSON
    let rewardMessage: String
    
    private enum CodingKeys: String, CodingKey {
        case index, description, rewardMessage = "reward_message"
        case completionCriteria = "completion_criteria"
        case completionCriteriaPoint = "completion_criteria_point"
    }
}

/// Low-level schedule structure matching habit.json
struct LowLevelScheduleNew: Codable {
    let span: String
    let spanValue: Double // number type in JSON
    let habitSchedule: Double? // number | null in JSON
    let habitRepeatCount: Double? // number | null in JSON
    let program: [ProgramNew]
    
    private enum CodingKeys: String, CodingKey {
        case span, program
        case spanValue = "span_value"
        case habitSchedule = "habit_schedule"
        case habitRepeatCount = "habit_repeat_count"
    }
}

/// Program structure containing indexed arrays
/// Uses types from HabitModels.swift: DaysIndexedItem, WeeksIndexedItem, MonthsIndexedItem
struct ProgramNew: Codable {
    let daysIndexed: [DaysIndexedItem]
    let weeksIndexed: [WeeksIndexedItem]
    let monthsIndexed: [MonthsIndexedItem]
    
    private enum CodingKeys: String, CodingKey {
        case daysIndexed = "days_indexed"
        case weeksIndexed = "weeks_indexed"
        case monthsIndexed = "months_indexed"
    }
}

/// Habit card data for display
struct HabitCardData {
    let habitId: String
    let name: String
    let goal: String
    let category: String?
    let description: String
    let difficulty: String?
    let title: String
    let steps: [HabitStepDisplay]
    let reminders: [HabitReminderDisplay]
}

/// Habit step display data
struct HabitStepDisplay {
    let step: String
    let clock: String?
    let day: String?
    let dayOfMonth: Int?
}

/// Habit reminder display data
struct HabitReminderDisplay {
    let time: String?
    let message: String?
}

// MARK: - Calendar Extensions

extension Calendar {
    /// Helper to set a specific day of month for a date
    func date(bySettingDay day: Int, of date: Date) -> Date? {
        var components = self.dateComponents([.year, .month, .hour, .minute, .second], from: date)
        
        // Check if the day is valid for the month
        guard let monthRange = self.range(of: .day, in: .month, for: date) else {
            return nil
        }
        
        // Clamp day to valid range (1 to max day of month)
        let clampedDay = max(1, min(day, monthRange.count))
        
        components.day = clampedDay
        return self.date(from: components)
    }
}

