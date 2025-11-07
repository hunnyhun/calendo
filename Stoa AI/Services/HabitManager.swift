import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class HabitManager: ObservableObject {
    static let shared = HabitManager()
    
    @Published var habits: [ComprehensiveHabit] = []
    @Published var entries: [HabitEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private var habitsListener: ListenerRegistration?
    private var entriesListener: ListenerRegistration?
    private var isLoadingHabits = false // Prevent concurrent loads
    
    init() {}
    
    // Clear error state
    func clearError() {
        error = nil
    }
    
    // MARK: - Data Loading
    
    func loadHabits() async {
        guard Auth.auth().currentUser?.uid != nil else {
            print("❌ [HabitManager] loadHabits - No authenticated user")
            return
        }
        
        // Prevent concurrent loads
        if isLoadingHabits {
            print("⚠️ [HabitManager] loadHabits - Already loading, skipping duplicate call")
            return
        }
        
        isLoadingHabits = true
        isLoading = true
        
        print("🔄 [HabitManager] loadHabits - Starting habit load...")
        
        // Use backend function instead of direct Firestore
        Task {
            do {
                let habitsData = try await CloudFunctionService.shared.getHabits()
                
                await MainActor.run {
                    do {
                        // Convert backend data to ComprehensiveHabit objects
                        // Each document from Firestore needs the document ID added as the habit ID
                        let loadedHabits = try habitsData.compactMap { data -> ComprehensiveHabit? in
                            let habitData = data
                            // If the data includes a document ID, use it; otherwise generate one
                            // The backend should return data with document IDs
                            let jsonData = try JSONSerialization.data(withJSONObject: habitData)
                            let decoder = JSONDecoder()
                            var habit = try decoder.decode(ComprehensiveHabit.self, from: jsonData)
                            
                            // If we have a document ID from the data, use it
                            if let docId = habitData["id"] as? String {
                                habit = ComprehensiveHabit(
                                    id: docId,
                                    name: habit.name,
                                    goal: habit.goal,
                                    category: habit.category,
                                    description: habit.description,
                                    difficulty: habit.difficulty,
                                    lowLevelSchedule: habit.lowLevelSchedule,
                                    highLevelSchedule: habit.highLevelSchedule,
                                    createdAt: habit.createdAt,
                                    startDate: habit.startDate,
                                    isActive: habit.isActive
                                )
                            }
                            
                            return habit
                        }
                        
                        // Deduplicate by ID (keep first occurrence)
                        var seenIds = Set<String>()
                        let deduplicatedHabits = loadedHabits.filter { habit in
                            if seenIds.contains(habit.id) {
                                print("⚠️ [HabitManager] loadHabits - Found duplicate habit ID: \(habit.id) (\(habit.name)), removing duplicate")
                                return false
                            }
                            seenIds.insert(habit.id)
                            return true
                        }
                        
                        self.habits = deduplicatedHabits
                        print("✅ [HabitManager] loadHabits - Loaded \(deduplicatedHabits.count) habits from backend (removed \(loadedHabits.count - deduplicatedHabits.count) duplicates)")
                        print("✅ [HabitManager] loadHabits - All habits match habit.json structure")
                        print("📊 [HabitManager] loadHabits - Habit isActive states: \(deduplicatedHabits.map { "\($0.name): \($0.isActive)" })")
                        self.error = nil
                    } catch {
                        print("❌ [HabitManager] loadHabits - Error parsing habits: \(error.localizedDescription)")
                        print("❌ [HabitManager] loadHabits - Failed data: \(habitsData)")
                        self.error = error.localizedDescription
                        self.habits = []
                    }
                    self.isLoading = false
                    self.isLoadingHabits = false
                }
            } catch {
                await MainActor.run {
                    print("❌ [HabitManager] loadHabits - Error loading from backend: \(error.localizedDescription)")
                    self.error = error.localizedDescription
                    self.isLoading = false
                    self.isLoadingHabits = false
                }
            }
        }
        
        // Load entries for statistics
        loadEntries()
    }
    
    private func loadEntries() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        entriesListener = db.collection("users").document(userId).collection("habitEntries")
            .order(by: "completedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ [HabitManager] Error loading entries: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.entries = []
                    return
                }
                
                do {
                    self.entries = try documents.compactMap { doc -> HabitEntry? in
                        var data = doc.data()
                        data["id"] = doc.documentID // Add the document ID
                        let jsonData = try JSONSerialization.data(withJSONObject: data)
                        return try JSONDecoder().decode(HabitEntry.self, from: jsonData)
                    }
                    print("✅ [HabitManager] Loaded \(self.entries.count) habit entries")
                } catch {
                    print("❌ [HabitManager] Error decoding entries: \(error.localizedDescription)")
                }
            }
    }
    
    // MARK: - Habit Management
    
    func createHabit(_ habit: ComprehensiveHabit) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Please sign in to create habits"
            return
        }
        
        // Refresh habits list to ensure we have the latest data
        await loadHabits()
        
        // Wait for habits to fully load
        var loadAttempts = 0
        while isLoading && loadAttempts < 10 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            loadAttempts += 1
        }
        
        // Check if habit with same name already exists (case-insensitive) in local cache
        let normalizedNewName = habit.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let existingHabit = habits.first { existingHabit in
            let normalizedExistingName = existingHabit.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedExistingName == normalizedNewName
        }
        
        if let existing = existingHabit {
            error = "DUPLICATE_HABIT:\(existing.name)"
            print("⚠️ [HabitManager] Duplicate habit prevented (local check): '\(habit.name)' (existing: '\(existing.name)')")
            return
        }
        
        // Additional check: Query Firestore directly to ensure no duplicates (handles race conditions)
        // This is important because multiple users/devices might try to create the same habit simultaneously
        do {
            let allHabitsSnapshot = try await db.collection("users")
                .document(userId)
                .collection("habits")
                .getDocuments()
            
            // Check each document for case-insensitive name match
            for document in allHabitsSnapshot.documents {
                if let existingName = document.data()["name"] as? String {
                    let normalizedExistingName = existingName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if normalizedExistingName == normalizedNewName {
                        error = "DUPLICATE_HABIT:\(existingName)"
                        print("⚠️ [HabitManager] Duplicate habit prevented (Firestore check): '\(habit.name)' (existing: '\(existingName)' ID: \(document.documentID))")
                        return
                    }
                }
            }
            
            print("✅ [HabitManager] No duplicates found, proceeding with habit creation: '\(habit.name)'")
        } catch {
            print("⚠️ [HabitManager] Error checking for duplicates in Firestore: \(error.localizedDescription)")
            // Fail closed: if we can't check for duplicates, don't allow creation to prevent duplicates
            self.error = "Unable to verify habit doesn't already exist. Please try again."
            return
        }
        
        do {
            // Validate that habit has required schedules (both are required per habit.json)
            guard habit.lowLevelSchedule.program.count > 0 else {
                error = "Habit must have at least one program in low_level_schedule"
                print("❌ [HabitManager] Habit missing required program structure")
                return
            }
            
            // Ensure both schedules exist (required by habit.json)
            var habitToSave = habit
            
            // Set startDate when user pushes to calendar (now)
            // Preserve createdAt if it exists (from AI), otherwise set it to now
            let now = ISO8601DateFormatter().string(from: Date())
            let createdAtToUse = habit.createdAt ?? now
            let startDateToUse = now // Always set startDate to now when user pushes to calendar
            
            // Validate milestones exist in high_level_schedule
            if habitToSave.highLevelSchedule.milestones.isEmpty {
                print("⚠️ [HabitManager] Habit missing milestones, creating default milestones")
                let defaultMilestones = [
                    HabitMilestone(
                        index: 0,
                        description: "Foundation - Get started with the habit",
                        completionCriteria: "streak_of_days",
                        completionCriteriaPoint: 7,
                        rewardMessage: "Great job! You've completed your first week!"
                    ),
                    HabitMilestone(
                        index: 1,
                        description: "Building - Continue building consistency",
                        completionCriteria: "streak_of_days",
                        completionCriteriaPoint: 30,
                        rewardMessage: "Amazing! You've maintained consistency for a month!"
                    ),
                    HabitMilestone(
                        index: 2,
                        description: "Mastery - Achieve long-term success",
                        completionCriteria: "streak_of_days",
                        completionCriteriaPoint: 90,
                        rewardMessage: "Incredible! You've achieved mastery!"
                    )
                ]
                let defaultHighLevelSchedule = HabitHighLevelSchedule(milestones: defaultMilestones)
                habitToSave = ComprehensiveHabit(
                    id: habitToSave.id,
                    name: habitToSave.name,
                    goal: habitToSave.goal,
                    category: habitToSave.category,
                    description: habitToSave.description,
                    difficulty: habitToSave.difficulty,
                    lowLevelSchedule: habitToSave.lowLevelSchedule,
                    highLevelSchedule: defaultHighLevelSchedule,
                    createdAt: createdAtToUse,
                    startDate: startDateToUse,
                    isActive: true // Always active when first pushed to calendar
                )
            } else {
                // Update habit with dates
                // If startDate is being set for the first time (was nil, now has value), make it active
                let shouldBeActive = habitToSave.startDate == nil ? true : habitToSave.isActive
                habitToSave = ComprehensiveHabit(
                    id: habitToSave.id,
                    name: habitToSave.name,
                    goal: habitToSave.goal,
                    category: habitToSave.category,
                    description: habitToSave.description,
                    difficulty: habitToSave.difficulty,
                    lowLevelSchedule: habitToSave.lowLevelSchedule,
                    highLevelSchedule: habitToSave.highLevelSchedule,
                    createdAt: createdAtToUse,
                    startDate: startDateToUse,
                    isActive: shouldBeActive
                )
            }
            
            // Encode habit to JSON matching habit.json structure
            let encoder = JSONEncoder()
            let habitData = try encoder.encode(habitToSave)
            var habitDict = try JSONSerialization.jsonObject(with: habitData) as! [String: Any]
            
            // Remove the 'id' field from the dictionary since it's not in habit.json
            // The Firestore document ID will serve as the habit ID
            habitDict.removeValue(forKey: "id")
            
            // Debug: Print what we're saving
            print("💾 [HabitManager] Saving habit data matching habit.json structure")
            print("💾 [HabitManager] Habit name: \(habitToSave.name)")
            print("💾 [HabitManager] Has low_level_schedule: \(habitDict["low_level_schedule"] != nil)")
            print("💾 [HabitManager] Has high_level_schedule: \(habitDict["high_level_schedule"] != nil)")
            
            _ = try await db.collection("users").document(userId).collection("habits").addDocument(data: habitDict)
            print("✅ [HabitManager] Created habit: \(habitToSave.name)")
            
            // Reload habits to reflect the new addition
            await loadHabits()
            
        } catch {
            print("❌ [HabitManager] Error creating habit: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func updateHabit(_ habit: ComprehensiveHabit) async {
        print("💾 [HabitManager] updateHabit called for: \(habit.name) (ID: \(habit.id))")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ [HabitManager] updateHabit failed: No authenticated user")
            error = "Please sign in to update habits"
            return
        }
        
        let habitId = habit.id
        print("🔍 [HabitManager] updateHabit - User ID: \(userId), Habit ID: \(habitId), isActive: \(habit.isActive)")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let habitData = try encoder.encode(habit)
            let habitDict = try JSONSerialization.jsonObject(with: habitData) as! [String: Any]
            
            print("💾 [HabitManager] updateHabit - Saving to Firestore...")
            try await db.collection("users").document(userId).collection("habits").document(habitId).setData(habitDict)
            print("✅ [HabitManager] updateHabit - Successfully updated habit: \(habit.name)")
            
            // Reload habits to reflect the update
            print("🔄 [HabitManager] updateHabit - Reloading habits...")
            await loadHabits()
            print("✅ [HabitManager] updateHabit - Habits reloaded, update complete")
        } catch {
            print("❌ [HabitManager] updateHabit - Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func deleteHabit(_ habit: ComprehensiveHabit) async {
        print("🗑️ [HabitManager] deleteHabit called for: \(habit.name) (ID: \(habit.id))")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ [HabitManager] deleteHabit failed: No authenticated user")
            error = "Please sign in to delete habits"
            return
        }
        
        let habitId = habit.id
        print("🔍 [HabitManager] deleteHabit - User ID: \(userId), Habit ID: \(habitId)")
        
        do {
            // Delete all entries for this habit first
            print("🔍 [HabitManager] deleteHabit - Fetching habit entries...")
            let entriesSnapshot = try await db.collection("users").document(userId).collection("habitEntries")
                .whereField("habitId", isEqualTo: habitId)
                .getDocuments()
            
            print("📊 [HabitManager] deleteHabit - Found \(entriesSnapshot.documents.count) entries to delete")
            
            let batch = db.batch()
            
            for document in entriesSnapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            // Delete the habit
            batch.deleteDocument(db.collection("users").document(userId).collection("habits").document(habitId))
            
            print("💾 [HabitManager] deleteHabit - Committing batch delete...")
            try await batch.commit()
            print("✅ [HabitManager] deleteHabit - Successfully deleted habit and \(entriesSnapshot.documents.count) entries: \(habit.name)")
            
            // Reload habits to reflect the deletion
            print("🔄 [HabitManager] deleteHabit - Reloading habits...")
            await loadHabits()
            print("✅ [HabitManager] deleteHabit - Habits reloaded, deletion complete")
        } catch {
            print("❌ [HabitManager] deleteHabit - Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func toggleHabitActive(_ habit: ComprehensiveHabit) async {
        let newActiveState = !habit.isActive
        print("🔄 [HabitManager] toggleHabitActive called for: \(habit.name) (ID: \(habit.id))")
        print("📊 [HabitManager] toggleHabitActive - Current state: \(habit.isActive ? "ACTIVE" : "INACTIVE") → New state: \(newActiveState ? "ACTIVE" : "INACTIVE")")
        
        let updatedHabit = ComprehensiveHabit(
            id: habit.id,
            name: habit.name,
            goal: habit.goal,
            category: habit.category,
            description: habit.description,
            difficulty: habit.difficulty,
            lowLevelSchedule: habit.lowLevelSchedule,
            highLevelSchedule: habit.highLevelSchedule,
            createdAt: habit.createdAt,
            startDate: habit.startDate,
            isActive: newActiveState
        )
        
        await updateHabit(updatedHabit)
        print("✅ [HabitManager] toggleHabitActive - Toggle complete for: \(habit.name)")
    }
    
    func shareHabit(_ habit: ComprehensiveHabit) async -> (text: String, link: URL?) {
        // Create human-readable text
        var shareText = "📋 \(habit.name)\n\n"
        shareText += "🎯 Goal: \(habit.goal)\n"
        shareText += "📂 Category: \(habit.category)\n"
        shareText += "📝 Description: \(habit.description)\n"
        shareText += "💪 Difficulty: \(habit.difficulty.capitalized)\n\n"
        
        if !habit.milestones.isEmpty {
            shareText += "🎯 Milestones:\n"
            for (index, milestone) in habit.milestones.enumerated() {
                shareText += "\(index + 1). \(milestone.description)\n"
            }
        }
        
        // Generate shareable link via backend
        var shareLink: URL?
        do {
            let response = try await CloudFunctionService.shared.createShareLink(type: "habit", itemId: habit.id)
            if let shareUrlString = response["shareUrl"] as? String,
               let url = URL(string: shareUrlString) {
                shareLink = url
                shareText += "\n\n🔗 Import Link:\n\(shareUrlString)"
            }
        } catch {
            print("❌ [HabitManager] Error creating share link: \(error.localizedDescription)")
            // Fallback to client-side link if backend fails
            shareLink = ShareLinkService.shared.generateHabitLink(habit)
            if let link = shareLink {
                shareText += "\n\n🔗 Import Link:\n\(link.absoluteString)"
            }
        }
        
        return (text: shareText, link: shareLink)
    }
    
    // MARK: - Habit Tracking
    
    func recordHabitCompletion(_ habit: ComprehensiveHabit, notes: String?, rating: Int?, reflection: String?, mood: HabitMood?) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Invalid habit or user"
            return
        }
        
        let entry = HabitEntry(
            habitId: habit.id,
            completedAt: Date(),
            notes: notes,
            rating: rating,
            reflection: reflection,
            mood: mood,
            createdBy: userId
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let entryData = try encoder.encode(entry)
            let entryDict = try JSONSerialization.jsonObject(with: entryData) as! [String: Any]
            
            _ = try await db.collection("users").document(userId).collection("habitEntries").addDocument(data: entryDict)
            print("✅ [HabitManager] Recorded completion for: \(habit.name)")
        } catch {
            print("❌ [HabitManager] Error recording completion: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func isHabitCompletedToday(_ habit: ComprehensiveHabit) -> Bool {
        let habitId = habit.id
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        return entries.contains { entry in
            entry.habitId == habitId &&
            entry.completedAt >= today &&
            entry.completedAt < tomorrow
        }
    }
    
    func getLastCompletion(for habit: ComprehensiveHabit) -> HabitEntry? {
        let habitId = habit.id
        
        return entries
            .filter { $0.habitId == habitId }
            .max(by: { $0.completedAt < $1.completedAt })
    }
    
    
    // MARK: - Statistics
    
    func getStats(for habit: ComprehensiveHabit) -> HabitStats? {
        let habitId = habit.id
        
        let habitEntries = entries.filter { $0.habitId == habitId }
        
        guard !habitEntries.isEmpty else {
            return HabitStats(
                habitId: habitId,
                totalCompletions: 0,
                currentStreak: 0,
                longestStreak: 0,
                completionRate: 0,
                lastCompletedAt: nil,
                averageRating: nil
            )
        }
        
        let totalCompletions = habitEntries.count
        let lastCompleted = habitEntries.max(by: { $0.completedAt < $1.completedAt })?.completedAt
        
        // Calculate completion rate
        // Since we don't have createdAt in the new structure, use the first entry date or current date
        let firstEntryDate = habitEntries.min(by: { $0.completedAt < $1.completedAt })?.completedAt ?? Date()
        let daysSinceCreation = Calendar.current.dateComponents([.day], from: firstEntryDate, to: Date()).day ?? 1
        let expectedCompletions: Int
        
        // Derive frequency from schedule
        let frequency: HabitFrequency
        switch habit.lowLevelSchedule.span {
        case "day":
            if habit.lowLevelSchedule.spanValue == 1.0 {
                frequency = .daily
            } else {
                // For every-n-days, use spanValue as the interval (convert Double to Int)
                frequency = .custom(days: Int(habit.lowLevelSchedule.spanValue))
            }
        case "week":
            frequency = .weekly
        default:
            frequency = .daily
        }
        
        switch frequency {
        case .daily:
            expectedCompletions = max(1, daysSinceCreation)
        case .weekly:
            expectedCompletions = max(1, daysSinceCreation / 7)
        case .custom(let days):
            expectedCompletions = max(1, daysSinceCreation / days)
        }
        
        let completionRate = min(1.0, Double(totalCompletions) / Double(expectedCompletions))
        
        // Calculate streaks
        let (currentStreak, longestStreak) = calculateStreaks(for: habit, entries: habitEntries)
        
        // Calculate average rating
        let ratingsSum = habitEntries.compactMap { $0.rating }.reduce(0, +)
        let ratingsCount = habitEntries.compactMap { $0.rating }.count
        let averageRating = ratingsCount > 0 ? Double(ratingsSum) / Double(ratingsCount) : nil
        
        return HabitStats(
            habitId: habitId,
            totalCompletions: totalCompletions,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            completionRate: completionRate,
            lastCompletedAt: lastCompleted,
            averageRating: averageRating
        )
    }
    
    private func calculateStreaks(for habit: ComprehensiveHabit, entries: [HabitEntry]) -> (current: Int, longest: Int) {
        let sortedEntries = entries.sorted { $0.completedAt > $1.completedAt }
        
        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 0
        
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: Date())
        
        // Check for current streak
        for entry in sortedEntries {
            let entryDate = calendar.startOfDay(for: entry.completedAt)
            
            if entryDate == currentDate {
                tempStreak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else {
                break
            }
        }
        
        currentStreak = tempStreak
        
        // Calculate longest streak
        tempStreak = 0
        var previousDate: Date?
        
        for entry in sortedEntries.reversed() {
            let entryDate = calendar.startOfDay(for: entry.completedAt)
            
            if let prevDate = previousDate {
                let daysDiff = calendar.dateComponents([.day], from: prevDate, to: entryDate).day ?? 0
                
                if daysDiff == 1 {
                    tempStreak += 1
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    tempStreak = 1
                }
            } else {
                tempStreak = 1
            }
            
            previousDate = entryDate
        }
        
        longestStreak = max(longestStreak, tempStreak)
        
        return (currentStreak, longestStreak)
    }
    
    // MARK: - Cleanup
    
    deinit {
        habitsListener?.remove()
        entriesListener?.remove()
    }
}
