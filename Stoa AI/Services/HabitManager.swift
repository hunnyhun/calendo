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
    
    init() {}
    
    // Clear error state
    func clearError() {
        error = nil
    }
    
    // MARK: - Data Loading
    
    func loadHabits() async {
        guard Auth.auth().currentUser?.uid != nil else {
            print("❌ [HabitManager] No authenticated user")
            return
        }
        
        isLoading = true
        
        // Use backend function instead of direct Firestore
        Task {
            do {
                let habitsData = try await CloudFunctionService.shared.getHabits()
                
                await MainActor.run {
                    do {
                        // Convert backend data to ComprehensiveHabit objects
                        self.habits = try habitsData.compactMap { data in
                            let jsonData = try JSONSerialization.data(withJSONObject: data)
                            let decoder = JSONDecoder()
                            return try decoder.decode(ComprehensiveHabit.self, from: jsonData)
                        }
                        print("✅ [HabitManager] Loaded \(self.habits.count) habits from backend")
                        self.error = nil
                    } catch {
                        print("❌ [HabitManager] Error parsing habits from backend: \(error.localizedDescription)")
                        self.error = error.localizedDescription
                        self.habits = []
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    print("❌ [HabitManager] Error loading habits from backend: \(error.localizedDescription)")
                    self.error = error.localizedDescription
                    self.isLoading = false
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
        
        // Check if habit with same name already exists (case-insensitive)
        let existingHabit = habits.first { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == habit.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        
        if let existing = existingHabit {
            error = "DUPLICATE_HABIT:\(existing.name)"
            print("⚠️ [HabitManager] Duplicate habit prevented: '\(habit.name)' (existing: '\(existing.name)')")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let habitData = try encoder.encode(habit)
            let habitDict = try JSONSerialization.jsonObject(with: habitData) as! [String: Any]
            
            // Debug: Print what we're saving
            print("💾 [HabitManager] Saving habit data: \(habitDict)")
            
            _ = try await db.collection("users").document(userId).collection("habits").addDocument(data: habitDict)
            print("✅ [HabitManager] Created habit: \(habit.name)")
            
            // Reminder scheduling will be handled by the backend
        } catch {
            print("❌ [HabitManager] Error creating habit: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func updateHabit(_ habit: ComprehensiveHabit) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Please sign in to update habits"
            return
        }
        
        let habitId = habit.id
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let habitData = try encoder.encode(habit)
            let habitDict = try JSONSerialization.jsonObject(with: habitData) as! [String: Any]
            
            try await db.collection("users").document(userId).collection("habits").document(habitId).setData(habitDict)
            print("✅ [HabitManager] Updated habit: \(habit.name)")
        } catch {
            print("❌ [HabitManager] Error updating habit: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func deleteHabit(_ habit: ComprehensiveHabit) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "Please sign in to delete habits"
            return
        }
        
        let habitId = habit.id
        
        do {
            // Delete all entries for this habit first
            let entriesSnapshot = try await db.collection("users").document(userId).collection("habitEntries")
                .whereField("habitId", isEqualTo: habitId)
                .getDocuments()
            
            let batch = db.batch()
            
            for document in entriesSnapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            // Delete the habit
            batch.deleteDocument(db.collection("users").document(userId).collection("habits").document(habitId))
            
            try await batch.commit()
            print("✅ [HabitManager] Deleted habit and all entries: \(habit.name)")
        } catch {
            print("❌ [HabitManager] Error deleting habit: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
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
        let formatter = ISO8601DateFormatter()
        let createdAt = formatter.date(from: habit.createdAt) ?? Date()
        let daysSinceCreation = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 1
        let expectedCompletions: Int
        
        // Derive frequency from schedule
        let frequency: HabitFrequency
        if let lowLevelSchedule = habit.lowLevelSchedule {
            switch lowLevelSchedule.span {
            case "daily":
                frequency = .daily
            case "weekly":
                frequency = .weekly
            case "every-n-days":
                if let interval = lowLevelSchedule.spanInterval {
                    frequency = .custom(days: interval)
                } else {
                    frequency = .daily
                }
            default:
                frequency = .daily
            }
        } else {
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
