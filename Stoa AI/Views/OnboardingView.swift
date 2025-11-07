import SwiftUI
import UserNotifications
import AppTrackingTransparency
#if canImport(UIKit)
import UIKit
#endif


// MARK: - String Extension for Width Calculation
extension String {
    func widthOfString(usingFont font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }
}

// MARK: - Onboarding Habit Card Data Model
struct OnboardingHabitCard {
    let emoji: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Study Plan Demo Data Model
struct StudyPlanDemo {
    let title: String
    let subtitle: String
    let sections: [(title: String, content: String)]
}

// MARK: - Scheduled Habit Demo Data Model
struct ScheduledHabitDemo {
    let emoji: String
    let title: String
    let subtitle: String?
    let time: String?
    let isCompleted: Bool
    let backgroundColor: Color
    let detailedProgram: [String: [String: String]]?
}

// MARK: - Keyword Option Data Model
struct KeywordOption: Identifiable {
    let id = UUID()
    let title: String
}

// MARK: - Habit Card Deck View
struct HabitCardDeckView: View {
    @State private var currentCardIndex = 0
    @State private var isAnimating = false
    @State private var animationTimer: Timer?
    
    private let habitCards: [OnboardingHabitCard] = [
        OnboardingHabitCard(
            emoji: "",
            title: "Deep Work Session",
            description: "Create \nHabit Cards\nin Any Subject",
            color: .brandBrightGreen
        ),
        OnboardingHabitCard(
            emoji: "",
            title: "Evening Journal",
            description: "",
            color: .brandBrightCyan
        ),
        OnboardingHabitCard(
            emoji: "",
            title: "Gym Strength Training",
            description: "",
            color: .brandBrightMagenta
        ),
        OnboardingHabitCard(
            emoji: "",
            title: "Language Learning Sprint",
            description: "",
            color: .brandBrightRed
        ),
        OnboardingHabitCard(
            emoji: "",
            title: "Morning Walk & Sunlight",
            description: "",
            color: .brandBrightPurple
        )
    ]
    
    var body: some View {
        ZStack {
            // Stack of cards with same X coordinate, different Y coordinates
            // Front card (index 0) at bottom, back cards higher
            ForEach(0..<habitCards.count, id: \.self) { index in
                HabitCardView(card: habitCards[index])
                    .offset(
                        x: 0, // Same X coordinate for all cards
                        y: CGFloat(index) * -20 + (isAnimating && currentCardIndex == index && index > 0 ? -50 : 0)
                    )
                    .zIndex(Double(habitCards.count - index))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isAnimating)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAnimating = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isAnimating = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    currentCardIndex = (currentCardIndex + 1) % habitCards.count
                }
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Individual Habit Card View
struct HabitCardView: View {
    let card: OnboardingHabitCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title - Left aligned
            Text(card.title)
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Description - Left aligned
            if !card.description.isEmpty {
                Text(card.description)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.black.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(width: 300, height: 330, alignment: .topLeading)
        .background(
            ZStack {
                // Outer colored border
                RoundedRectangle(cornerRadius: 30)
                    .fill(card.color)
                
                // Inner white content (inset by border width)
                // Corner radius = outer radius - border width (since border extends inward)
                RoundedRectangle(cornerRadius: max(20, 30 - 10))
                    .fill(Color.white)
                    .padding(20)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - New Onboarding Chat Demo View
struct NewOnboardingChatDemoView: View {
    @State private var showUserMessage = false
    @State private var showAIMessage = false
    @State private var showStudyPlan = false
    @State private var showPushButton = false
    @State private var userMessageOffset: CGFloat = 300
    @State private var aiMessageOffset: CGFloat = -300
    @State private var studyPlanOffset: CGFloat = 200
    
    private let studyPlan = StudyPlanDemo(
        title: "Study Plan for History Exam",
        subtitle: "DAY 1: Foundations of the USA",
        sections: [
            (
                title: "Colonial America (1600s - 1770s)",
                content: "• British, French, Spanish, and Dutch established colonies in North America.\n• Thirteen British colonies developed along the Atlantic coast.\n• Colonists valued self-rule but were still under British control."
            ),
            (
                title: "Road to Independence",
                content: "• Britain imposed taxes (like the Stamp Act) without giving colonies representation.\n• Slogan: \"No taxation without representation.\"\n• Tensions grew — Boston Tea Party (1773) became a turning point."
            ),
            (
                title: "American Revolution (1775 - 1783)",
                content: "• Colonies declared independence on July 4, 1776 (Declaration of Independence by Thomas Jefferson).\n• War fought between American colonies and Britain.\n• Americans won with help from France."
            ),
            (
                title: "Building a Nation",
                content: "• 1787: U.S. Constitution written — created the system of government with 3 branches.\n• George Washington became the 1st President in 1789."
            )
        ]
    )
    
    var body: some View {
        VStack(spacing: 20) {
            // Chat Messages
            VStack(spacing: 16) {
                // User Message
                if showUserMessage {
                    HStack {
                        Spacer()
                        Text("I have an History of U.S.A. exam in two days!!!!")
                            .padding(12)
                            .background(Color.brandBrightGreen)
                            .foregroundColor(.black)
                            .cornerRadius(20)
                            .frame(maxWidth: 280, alignment: .trailing)
                    }
                    .offset(x: userMessageOffset)
                    .opacity(showUserMessage ? 1 : 0)
                }
                
                // AI Response
                if showAIMessage {
                    HStack {
                        Text("Don't worry. We'll keep it clear and simple. I have prepared a two-day study program. We'll start from the early colonies, the independence movement, and end with the Civil War.")
                            .padding(12)
                            .background(Color.brandLightPurple)
                            .foregroundColor(.black)
                            .cornerRadius(20)
                            .frame(maxWidth: 280, alignment: .leading)
                        
                        Spacer()
                    }
                    .offset(x: aiMessageOffset)
                    .opacity(showAIMessage ? 1 : 0)
                }
            }
            .padding(.horizontal, 16)
            
            // Study Plan Card
            if showStudyPlan {
                StudyPlanCardView(studyPlan: studyPlan, showPushButton: showPushButton)
                    .offset(y: studyPlanOffset)
                    .opacity(showStudyPlan ? 1 : 0)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Reset all states
        showUserMessage = false
        showAIMessage = false
        showStudyPlan = false
        userMessageOffset = 300
        aiMessageOffset = -300
        studyPlanOffset = 200
        
        // Start animation sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.64)) { // 0.8 / 1.25
                showUserMessage = true
                userMessageOffset = 0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { // 2.0 / 1.25
            withAnimation(.easeOut(duration: 0.64)) { // 0.8 / 1.25
                showAIMessage = true
                aiMessageOffset = 0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { // 3.5 / 1.25
            withAnimation(.easeOut(duration: 0.64)) { // 0.8 / 1.25
                showStudyPlan = true
                studyPlanOffset = 0
            }
        }
        
        // Show push button after all 3 messages have appeared
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                showPushButton = true
            }
        }
    }
}

// MARK: - Study Plan Card View
struct StudyPlanCardView: View {
    let studyPlan: StudyPlanDemo
    var showPushButton: Bool = false
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.7
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(studyPlan.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text(studyPlan.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.7))
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(studyPlan.sections.enumerated()), id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(index + 1). \(section.title)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Text(section.content)
                                .font(.caption)
                                .foregroundColor(.black.opacity(0.8))
                                .lineSpacing(2)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
            .cornerRadius(16)
            .padding(.horizontal, 16)
            
            // Push to Calendar Button - Top Right Corner
            if showPushButton {
                Button(action: {}) {
                    VStack(spacing: 2) {
                        Text("Push to")
                            .font(.system(size: 14, weight: .medium))
                        Text("Calendar +")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.brandBrightGreen)
                    .cornerRadius(20)
                    .shadow(color: Color.brandBrightGreen.opacity(pulseOpacity * 0.6), radius: 8)
                    .scaleEffect(pulseScale)
                }
                .padding(.top, 8)
                .padding(.trailing, 32)
                .onAppear {
                    startPulseAnimation()
                }
            }
        }
    }
    
    private func startPulseAnimation() {
        // Continuous pulsing animation
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
        
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.6)) {
            pulseOpacity = 1.0
        }
    }
}

// MARK: - Calendar Widget View
struct CalendarWidgetView: View {
    private let daysOfWeek = ["M", "T", "W", "T", "F", "S", "S"]
    private let calendarDays = [
        ["29", "30", "1", "2", "3", "4", "5"],
        ["6", "7", "8", "9", "10", "11", "12"],
        ["13", "14", "15", "16", "17", "18", "19"],
        ["20", "21", "22", "23", "24", "25", "26"],
        ["27", "28", "29", "30", "31", "1", "2"]
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            // Day names at the top
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
            .padding(.horizontal, 16)
            
            // Calendar grid with day numbers
            VStack(spacing: 6) {
                ForEach(0..<calendarDays.count, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<calendarDays[row].count, id: \.self) { col in
                            let day = calendarDays[row][col]
                            let isCurrentDay = day == "7"
                            let isOtherMonth = (row == 0 && (day == "29" || day == "30")) ||
                                             (row == calendarDays.count - 1 && (day == "1" || day == "2"))
                            
                            Text(day)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(isCurrentDay ? Color.brandCurrentDay : Color(hex: 0x12D70C))
                                )
                                .frame(maxWidth: .infinity)
                                .opacity(isOtherMonth ? 0.5 : 1.0)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.brandBrightGreen)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Underlined Title View
struct UnderlinedTitleView: View {
    let text: String
    let underlinedPhrases: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let parts = splitTextWithUnderlines()
            
            HStack {
                ForEach(0..<parts.count, id: \.self) { index in
                    let part = parts[index]
                    
                    if part.isUnderlined {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.text)
                                .font(.system(.largeTitle, design: .default))
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Rectangle()
                                .fill(Color.black)
                                .frame(height: 2)
                                .frame(width: part.text.widthOfString(usingFont: .systemFont(ofSize: 28, weight: .bold)))
                        }
                    } else {
                        Text(part.text)
                            .font(.system(.largeTitle, design: .default))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
    }
    
    private func splitTextWithUnderlines() -> [(text: String, isUnderlined: Bool)] {
        var result: [(text: String, isUnderlined: Bool)] = []
        var remainingText = text
        
        for phrase in underlinedPhrases {
            if let range = remainingText.range(of: phrase) {
                // Add text before the phrase
                let beforeText = String(remainingText[..<range.lowerBound])
                if !beforeText.isEmpty {
                    result.append((text: beforeText, isUnderlined: false))
                }
                
                // Add the underlined phrase
                result.append((text: phrase, isUnderlined: true))
                
                // Update remaining text
                remainingText = String(remainingText[range.upperBound...])
            }
        }
        
        // Add any remaining text
        if !remainingText.isEmpty {
            result.append((text: remainingText, isUnderlined: false))
        }
        
        return result
    }
}

// MARK: - Habit Schedule List View
struct HabitScheduleListView: View {
    private let habits: [ScheduledHabitDemo] = [
        ScheduledHabitDemo(
            emoji: "🌅",
            title: "Morning Routine",
            subtitle: nil,
            time: "06.30",
            isCompleted: false,
            backgroundColor: Color.cyan.opacity(0.15),
            detailedProgram: nil
        ),
        ScheduledHabitDemo(
            emoji: "🏋️",
            title: "Gym Exercise",
            subtitle: nil,
            time: "08.30",
            isCompleted: false,
            backgroundColor: Color.brandLightPurple,
            detailedProgram: [
                "Warm-Up & Stretching": [
                    "Arm Circles": "3 Min",
                    "Cat-Cow Stretch": "3 Min",
                    "Lat Stretch": "4 Min"
                ],
                "Back Workout": [
                    "Lat Pulldown": "3x10",
                    "Seated Cable Row": "4x8",
                    "Reverse Fly": "3x12"
                ]
            ]
        )
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(habits.enumerated()), id: \.offset) { index, habit in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(habit.emoji)
                                .font(.system(size: 24))
                            Text(habit.title)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            Spacer()
                            if let time = habit.time {
                                Text(time)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                        }
                        
                        if let subtitle = habit.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.black.opacity(0.7))
                        }
                        
                        if let program = habit.detailedProgram {
                            VStack(alignment: .leading, spacing: 8) {
                                // Ensure Warm-Up comes first
                                let sortedSections = program.keys.sorted { section1, section2 in
                                    if section1.contains("Warm-Up") { return true }
                                    if section2.contains("Warm-Up") { return false }
                                    return section1 < section2
                                }
                                ForEach(sortedSections, id: \.self) { section in
                                    if let exercises = program[section] {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(section)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.black.opacity(0.8))
                                            
                                            ForEach(Array(exercises.keys.sorted()), id: \.self) { exercise in
                                                if let duration = exercises[exercise] {
                                                    HStack {
                                                        Text(exercise)
                                                            .font(.caption)
                                                            .foregroundColor(.black.opacity(0.7))
                                                        Spacer()
                                                        Text(duration)
                                                            .font(.caption)
                                                            .foregroundColor(.black.opacity(0.7))
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    Spacer()
                    
                    if habit.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(habit.backgroundColor)
                .cornerRadius(16)
            }
        }
    }
}

// MARK: - Keyword Selection View
struct KeywordSelectionView: View {
    @Binding var selectedKeywords: Set<UUID>
    @State private var keywords: [KeywordOption] = []
    
    init(selectedKeywords: Binding<Set<UUID>>) {
        self._selectedKeywords = selectedKeywords
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(keywords) { keyword in
                    KeywordPillView(
                        keyword: keyword,
                        isSelected: selectedKeywords.contains(keyword.id)
                    ) {
                        toggleSelection(keyword.id)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            loadKeywords()
        }
    }
    
    private func loadKeywords() {
        keywords = [
            KeywordOption(title: "Skin Care"),
            KeywordOption(title: "Discipline"),
            KeywordOption(title: "Productivity"),
            KeywordOption(title: "Creativity"),
            KeywordOption(title: "Sleep"),
            KeywordOption(title: "Fitness"),
            KeywordOption(title: "Energy"),
            KeywordOption(title: "Learning"),
            KeywordOption(title: "Morning"),
            KeywordOption(title: "Financial"),
            KeywordOption(title: "Mental Health"),
            KeywordOption(title: "Language"),
            KeywordOption(title: "Stress"),
            KeywordOption(title: "Weight Loss"),
            KeywordOption(title: "Communication"),
            KeywordOption(title: "Meditation")
        ]
    }
    
    private func toggleSelection(_ keywordId: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedKeywords.contains(keywordId) {
                selectedKeywords.remove(keywordId)
            } else {
                selectedKeywords.insert(keywordId)
            }
        }
    }
}

// MARK: - Keyword Pill View
struct KeywordPillView: View {
    let keyword: KeywordOption
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(isSelected ? "✓" : "+")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black)
                
                Text(keyword.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(isSelected ? Color.brandBrightGreen : Color.green.opacity(0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: .unspecified)
        }
    }
}

struct FlowResult {
    var size: CGSize
    var positions: [CGPoint]
    
    init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []
        var currentLineItems: [(size: CGSize, index: Int)] = []
        
        for (index, subview) in subviews.enumerated() {
            let subviewSize = subview.sizeThatFits(.unspecified)
            
            // Check if this item fits on the current line
            let currentLineWidth = currentLineItems.reduce(0) { $0 + $1.size.width } + CGFloat(max(0, currentLineItems.count - 1)) * spacing
            if currentLineWidth + subviewSize.width > maxWidth && !currentLineItems.isEmpty {
                // Place current line items centered
                let totalLineWidth = currentLineWidth
                let startX = (maxWidth - totalLineWidth) / 2
                var currentX = startX
                
                for (size, _) in currentLineItems {
                    positions.append(CGPoint(x: currentX, y: currentY))
                    currentX += size.width + spacing
                }
                
                // Move to next line
                currentY += lineHeight + spacing
                lineHeight = 0
                currentLineItems.removeAll()
            }
            
            currentLineItems.append((size: subviewSize, index: index))
            lineHeight = max(lineHeight, subviewSize.height)
        }
        
        // Place remaining items in the last line
        if !currentLineItems.isEmpty {
            let totalLineWidth = currentLineItems.reduce(0) { $0 + $1.size.width } + CGFloat(max(0, currentLineItems.count - 1)) * spacing
            let startX = (maxWidth - totalLineWidth) / 2
            var currentX = startX
            
            for (size, _) in currentLineItems {
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
            }
        }
        
        self.positions = positions
        self.size = CGSize(
            width: maxWidth,
            height: currentY + lineHeight
        )
    }
}

// MARK: - Gender Selection View
struct GenderSelectionView: View {
    @Binding var selectedGender: Models.Gender?
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Personalize\nYour Experience")
                .font(.system(size: 40, weight: .bold, design: .default))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                .padding(.top, 60)
            
            Text("This helps us provide more relevant content and recommendations")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            VStack(spacing: 16) {
                ForEach(Models.Gender.allCases, id: \.self) { gender in
                    GenderOptionView(
                        gender: gender,
                        isSelected: selectedGender == gender
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedGender = gender
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
}

// MARK: - Gender Option View
struct GenderOptionView: View {
    let gender: Models.Gender
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(gender.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.green : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Age Selection View
struct AgeSelectionView: View {
    @Binding var selectedAge: Int?
    @State private var currentAge: Int = 25
    
    private let ages = Array(13...100)
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Better Content for\nYour Life Stage")
                .font(.system(size: 40, weight: .bold, design: .default))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                .padding(.top, 60)
            
            Text("This helps us provide age-appropriate content and recommendations")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Age Picker
            VStack(spacing: 20) {
                Text("\(currentAge)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.vertical, 20)
                
                Picker("Age", selection: $currentAge) {
                    ForEach(ages, id: \.self) { age in
                        Text("\(age)")
                            .tag(age)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 200)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .onChange(of: currentAge) { oldValue, newValue in
            selectedAge = newValue
        }
        .onAppear {
            if selectedAge == nil {
                selectedAge = currentAge
            } else {
                currentAge = selectedAge ?? 25
            }
        }
    }
}

// MARK: - Social Proof View
struct SocialProofView: View {
    @State private var visibleReviews: Set<Int> = []
    
    private let reviews = [
        AppReview(
            rating: 5,
            text: "This app has completely transformed my daily routine. The AI suggestions are spot-on and the habit tracking keeps me motivated.",
            author: "Sarah M.",
            date: "2 days ago"
        ),
        AppReview(
            rating: 5,
            text: "Finally, an app that understands personal growth. The quotes and insights are exactly what I needed during tough times.",
            author: "Michael R.",
            date: "1 week ago"
        ),
        AppReview(
            rating: 5,
            text: "The calendar integration is brilliant. I can see my progress at a glance and stay on track with my goals.",
            author: "Emma L.",
            date: "3 days ago"
        ),
        AppReview(
            rating: 5,
            text: "Love how personalized everything feels. The AI really gets me and provides relevant advice for my situation.",
            author: "David K.",
            date: "5 days ago"
        )
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text("Join Thousands of\nSatisfied Users")
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                    .padding(.top, 60)
                
                // Show reviews with staggered animation
                VStack(spacing: 16) {
                    ForEach(0..<reviews.count, id: \.self) { index in
                        ReviewCardView(review: reviews[index], reviewerIndex: index + 1)
                            .opacity(visibleReviews.contains(index) ? 1.0 : 0.0)
                            .scaleEffect(visibleReviews.contains(index) ? 1.0 : 0.95)
                            .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.15), value: visibleReviews.contains(index))
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 20)
            }
        }
        .onAppear {
            startReviewAnimation()
        }
    }
    
    private func startReviewAnimation() {
        // Animate each review card in sequence
        for index in 0..<reviews.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.15) {
                withAnimation(.easeOut(duration: 0.5)) {
                    let _ = visibleReviews.insert(index)
                }
            }
        }
        
        // Show native App Store review popup after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            AppReviewManager.shared.requestReview()
        }
    }
}

// MARK: - App Review Model
struct AppReview {
    let rating: Int
    let text: String
    let author: String
    let date: String
}

// MARK: - Review Card View
struct ReviewCardView: View {
    let review: AppReview
    let reviewerIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Profile photo and rating stars
            HStack(alignment: .center, spacing: 12) {
                // Circular profile photo
                Image("reviewer-\(reviewerIndex)")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                // Rating stars
                HStack(spacing: 4) {
                    ForEach(0..<review.rating, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.yellow)
                    }
                }
                
                Spacer()
            }
            
            // Review text
            Text(review.text)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.black)
                .lineSpacing(4)
            
            // Author and date
            HStack {
                Text(review.author)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black.opacity(0.8))
                
                Spacer()
                
                Text(review.date)
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.6))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Widget Logo
struct WidgetStoicColumn: View {
    let width: CGFloat
    let color: Color
    let shadowColor: Color
    
    var body: some View {
        Image("logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width * 1.5, height: width * 1.5)
            .shadow(color: shadowColor, radius: 2, x: 1, y: 1)
    }
}



// MARK: - Main Onboarding View
struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var showCalendar = false
    @State private var selectedKeywords: Set<UUID> = []
    @State private var selectedGender: Models.Gender? = nil
    @State private var selectedAge: Int? = nil
    @Binding var isPresented: Bool
    var onCompletion: (() -> Void)? = nil
    
    // Function to request notification permission
    private func requestNotificationPermission() {
        Task {
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                print("📱 [OnboardingView] Notification permission granted: \(granted)")
                
                if granted {
                    await MainActor.run {
                        #if canImport(UIKit)
                        UIApplication.shared.registerForRemoteNotifications()
                        #endif
                    }
                }
            } catch {
                print("📱 [OnboardingView] Error requesting notification permission: \(error.localizedDescription)")
            }
        }
    }
    
    // Function to request App Tracking Transparency permission
    private func requestTrackingPermission() {
        Task {
            let granted = await AppTrackingTransparencyManager.shared.requestTrackingPermission()
            print("📱 [OnboardingView] Tracking permission granted: \(granted)")
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // White background for all pages
                Color.white
                    .ignoresSafeArea(.all)
                
                ZStack {
                    // TabView pages - Full screen content
                    TabView(selection: $currentPage) {
                        // Page 1: Welcome with Habit Cards
                        VStack(spacing: 0) {
                            Text("Welcome to Calendo")
                                .font(.system(size: 40, weight: .bold, design: .default))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                                .padding(.top, 20)
                                .padding(.bottom, 10)
                            Spacer()
                                .frame(height: 60) // Space between text and cards
                            
                            HabitCardDeckView()
                                .frame(maxHeight: geometry.size.height * 0.55)
                        }
                        .tag(0)
                        
                        // Page 2: Chat Demo
                        VStack(spacing: 20) {
                            Text("Plan Everything\nEasy and Fast")
                                .font(.system(size: 40, weight: .bold, design: .default))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                                .padding(.top, 60)
                            
                            NewOnboardingChatDemoView()
                                .frame(maxHeight: geometry.size.height * 0.7)
                        }
                        .tag(1)
                        .onAppear {
                            // Restart animation when returning to this page
                            if currentPage == 1 {
                                // Animation will restart automatically in NewOnboardingChatDemoView
                            }
                        }
                        
                        // Page 3: Calendar & Habits
                        VStack(spacing: 20) {
                            // Title section
                            Text("Plan Your Day\nWeek and Month")
                                .font(.system(size: 40, weight: .bold, design: .default))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                                .padding(.top, 40)
                            
                            // Calendar and Date section
                            VStack(spacing: 8) {
                                CalendarWidgetView()
                                    .scaleEffect(showCalendar ? 1.0 : 0.8)
                                    .opacity(showCalendar ? 1.0 : 0.0)
                                    .animation(.spring(response: 0.7, dampingFraction: 0.7), value: showCalendar)
                                
                                HStack {
                                    Text("7th July")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                        .padding(.leading, 20)
                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Habits section
                            HabitScheduleListView()
                                .padding(.horizontal, 20)
                            
                            Spacer()
                        }
                        .tag(2)
                        .onAppear { showCalendar = true }
                        
                        // Page 4: Keyword Selection
                        VStack(spacing: 0) {
                            Text("Select Topics\nThat Fit You Best")
                                .font(.system(size: 40, weight: .bold, design: .default))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40)
                                .padding(.bottom, 20)
                            
                            KeywordSelectionView(selectedKeywords: $selectedKeywords)
                                .frame(maxWidth: .infinity)
                            
                            Spacer()
                        }
                        .tag(3)
                        .onAppear {
                            // Request App Tracking Transparency permission when keyword selection page appears
                            requestTrackingPermission()
                        }
                        
                        // Page 5: Widget
                        ScrollView {
                            VStack(spacing: 20) {
                                OnboardingPageView(
                                    title: "Notifications and Widgets are Great Reminders",
                                    description: "",
                                    textColor: .black
                                )
                                .padding(.top, 60)
                                
                                // Enhanced Widget Demo Section
                                OnboardingWidgetDemoView()
                                    .padding(.horizontal, 20)
                            }
                        }
                        .tag(4)
                        
                        // Page 6: Gender Selection
                        GenderSelectionView(selectedGender: $selectedGender)
                            .tag(5)
                            .onAppear {
                                // Request notification permission when gender page appears
                                requestNotificationPermission()
                            }
                        
                        // Page 7: Age Selection
                        AgeSelectionView(selectedAge: $selectedAge)
                            .tag(6)
                        
                        // Page 8: Social Proof with App Reviews
                        SocialProofView()
                            .tag(7)

                        // Page 9: Authentication
                        OnboardingAuthPageView(
                            onAuthenticationSuccess: {
                                // Authentication successful - proceed to complete onboarding
                                Task {
                                    // Save selected gender and age to user profile
                                    if let gender = selectedGender {
                                        UserStatusManager.shared.state.profile.gender = gender
                                    }
                                    if let age = selectedAge {
                                        UserStatusManager.shared.state.profile.age = age
                                    }
                                    
                                    await OnboardingManager.shared.markOnboardingCompleted()
                                    await MainActor.run {
                                        isPresented = false
                                        onCompletion?()
                                    }
                                }
                            }
                        )
                            .tag(8)
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    #endif
                    .ignoresSafeArea(.all)
                    
                    // Page indicators - Top (Horizontal Progress Bar) - Very top of screen
                    VStack {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background line
                                Rectangle()
                                    .fill(Color.black.opacity(0.2))
                                    .frame(height: 3)
                                    .cornerRadius(1.5)
                                
                                    // Filled progress line
                                    Rectangle()
                                        .fill(Color.brandBrightGreen)
                                        .frame(width: geometry.size.width * CGFloat(currentPage + 1) / 9.0, height: 3)
                                        .cornerRadius(1.5)
                                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 50)
                        .padding(.top, 8) // Very top padding
                        Spacer()
                    }
                    
                    // Back Button - Top Left (Above everything, separate layer)
                    if currentPage > 0 {
                        VStack {
                            HStack {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        currentPage -= 1
                                    }
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.black)
                                        .frame(width: 50, height: 50)
                                        .background(Color.clear)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.leading, 10)
                                .padding(.top, 8)
                                Spacer()
                            }
                            Spacer()
                        }
                        .allowsHitTesting(true)
                    }
                    
                    // Navigation Section - Overlay at bottom
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            
                            // Navigation button - only show if not on auth page (page 8)
                                if currentPage < 8 {
                                Button(action: {
                                    // Check if transitioning from keyword selection page (page 3) to widget page (page 4)
                                    if currentPage == 3 {
                                        // Validate that at least one keyword is selected
                                        if selectedKeywords.isEmpty {
                                            return // Don't proceed if no keywords selected
                                        }
                                    }
                                    
                                    // Check if transitioning from gender selection page (page 5) to age selection page (page 6)
                                    if currentPage == 5 {
                                        // Validate that a gender is selected
                                        if selectedGender == nil {
                                            return // Don't proceed if no gender selected
                                        }
                                    }
                                    
                                    // Check if transitioning from age selection page (page 6) to social proof page (page 7)
                                    if currentPage == 6 {
                                        // Validate that an age is selected
                                        if selectedAge == nil {
                                            return // Don't proceed if no age selected
                                        }
                                    }
                                    
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        currentPage += 1
                                }
                            }) {
                                HStack(spacing: 12) {
                                        Text(NSLocalizedString("onboarding_continue", comment: ""))
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .fontWeight(.semibold)
                                    
                                        Image(systemName: "arrow.right")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill((currentPage == 3 && selectedKeywords.isEmpty) || (currentPage == 5 && selectedGender == nil) || (currentPage == 6 && selectedAge == nil) ? Color.gray : Color.brandBrightGreen)
                                        .shadow(color: (currentPage == 3 && selectedKeywords.isEmpty) || (currentPage == 5 && selectedGender == nil) || (currentPage == 6 && selectedAge == nil) ? Color.gray.opacity(0.3) : Color.brandBrightGreen.opacity(0.3), radius: 8, x: 0, y: 4)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 30)
                            }
                            
                            // Promotional text under the button - hide for auth page (page 8)
                            if currentPage < 8 {
                                Text(currentPage == 0 ? "Your Personal Growth Companion" : 
                                     currentPage == 1 ? "Trusted by 1,000+ Users" :
                                     currentPage == 2 ? "Build Better Habits Daily" :
                                     currentPage == 3 ? "AI-Powered Personalized Goal Achievement" :
                                     currentPage == 4 ? "Plan, Track & Achieve" :
                                     currentPage == 5 ? "Help Us Personalize Your Experience" :
                                     currentPage == 6 ? "Better Content for Your Life Stage" : 
                                     "Join Thousands of Satisfied Users")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 8)
                                    .padding(.horizontal, 30)
                            }
                        }
                        .padding(.bottom, 40)
                        .background(
                            Color.white
                                .opacity(0.9)
                                .blur(radius: 10)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Completion Page View
// MARK: - Onboarding Auth Page View
struct OnboardingAuthPageView: View {
    var onAuthenticationSuccess: (() -> Void)? = nil
    let userStatusManager = UserStatusManager.shared
    let authManager = AuthenticationManager.shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            // Simple white background
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                // Authentication Buttons - Simple and clean, centered
                VStack(spacing: 16) {
                    // Google Sign In
                    Button(action: handleGoogleSignIn) {
                        HStack {
                            Image("googleicon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            Text("continueWithGoogle".localized)
                                .font(.system(size: 20, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 20)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .opacity(isLoading ? 0.6 : 1.0)
                    .disabled(isLoading)
                    
                    // Apple Sign In
                    Button(action: handleAppleSignIn) {
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.title2)
                            Text("continueWithApple".localized)
                                .font(.system(size: 20, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 20)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .opacity(isLoading ? 0.6 : 1.0)
                    .disabled(isLoading)
                }
                .padding(.horizontal, 30)
                
                // Error Message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 8)
                }
                
                Spacer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserStateChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let authStatus = userInfo["authStatus"] as? String,
               authStatus == "authenticated" {
                // User just authenticated, call success callback
                onAuthenticationSuccess?()
            }
        }
    }
    
    private func handleGoogleSignIn() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                try await authManager.signInWithGoogle()
                // Success will be handled by notification observer
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func handleAppleSignIn() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                try await authManager.signInWithApple()
                // Success will be handled by notification observer
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct CompletionPageView: View {
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showButton = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                Text("Now You Can Start")
                    .font(.system(.largeTitle, design: .default))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .opacity(showTitle ? 1.0 : 0.0)
                    .offset(y: showTitle ? 0 : 20)
                    .animation(.easeOut(duration: 0.8).delay(0.2), value: showTitle)
                
                Text("Boost Your Potential")
                    .font(.system(.largeTitle, design: .default))
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .opacity(showSubtitle ? 1.0 : 0.0)
                    .offset(y: showSubtitle ? 0 : 20)
                    .animation(.easeOut(duration: 0.8).delay(0.6), value: showSubtitle)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                    .opacity(showButton ? 1.0 : 0.0)
                    .scaleEffect(showButton ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.0), value: showButton)
                
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation {
                showTitle = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation {
                    showSubtitle = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation {
                    showButton = true
                }
            }
        }
    }
}

// MARK: - Onboarding Chat Demo View
struct OnboardingChatDemoView: View {
    @State private var showUserMessage = false
    @State private var showAIMessage = false
    
    var body: some View {
        VStack(spacing: 12) {
            if showUserMessage {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("onboarding_sample_user_message", comment: ""))
                        .padding(12)
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.black.opacity(0.8))
                        .cornerRadius(18)
                        .frame(maxWidth: 220, alignment: .trailing)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if showAIMessage {
                HStack(alignment: .top) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.yellow)
                    Text(NSLocalizedString("onboarding_sample_ai_message", comment: ""))
                        .padding(12)
                        .background(Color.yellow.opacity(0.1))
                        .foregroundColor(.black.opacity(0.8))
                        .cornerRadius(18)
                        .frame(maxWidth: 220, alignment: .leading)
                    Spacer()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                showUserMessage = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.7)) {
                    showAIMessage = true
                }
            }
        }
    }
}

// MARK: - Enhanced Quote Preview View
struct OnboardingQuotePreviewView: View {
    @State private var showQuote = false
    @State private var showColumn = false
    @State private var quoteOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Animated Stoic column
            WidgetStoicColumn(
                width: 32,
                color: Color.yellow,
                shadowColor: Color.yellow.opacity(0.4)
            )
            .frame(height: 80)
            .scaleEffect(showColumn ? 1.0 : 0.5)
            .opacity(showColumn ? 1.0 : 0.0)
            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showColumn)
            
            Text(NSLocalizedString("onboarding_sample_quote", comment: ""))
                .font(.system(.title3, design: .serif))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(quoteOpacity)
                .scaleEffect(quoteOpacity > 0 ? 1.0 : 0.9)
                .animation(.easeOut(duration: 0.6).delay(0.4), value: quoteOpacity)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 32)
        .scaleEffect(showQuote ? 1.0 : 0.8)
        .opacity(showQuote ? 1.0 : 0.0)
        .animation(.spring(response: 0.7, dampingFraction: 0.7), value: showQuote)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showQuote = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showColumn = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                quoteOpacity = 1.0
            }
        }
    }
}

// MARK: - Enhanced Widget Demo View
struct OnboardingWidgetDemoView: View {
    @State private var showMainWidget = false
    @State private var showOtherWidgets = false
    @State private var widgetGlow = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Main Stoa AI Widget
            VStack(spacing: 16) {
                WidgetStoicColumn(
                    width: 50,
                    color: Color.brandBrightGreen,
                    shadowColor: Color.brandBrightGreen.opacity(0.4)
                )
                .frame(height: 100)
                
                Text("Take your vitamins and get some sunbathing")
                    .font(.system(.headline, design: .default))
                    .foregroundColor(.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 20)
            }
            .frame(width: 300, height: 220)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.brandBrightGreen.opacity(widgetGlow ? 0.4 : 0.0), lineWidth: 2)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: widgetGlow)
                    )
            )
            .scaleEffect(showMainWidget ? 1.0 : 0.7)
            .opacity(showMainWidget ? 1.0 : 0.0)
            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showMainWidget)
            
            // Other home screen widgets for context
            HStack(spacing: 20) {
                // Calendar Widget
                VStack(spacing: 12) {
                    Text("Today")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                    
                    Text("15")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.black)
                    
                    Text("Friday")
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.6))
                }
                .frame(width: 130, height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
                
                // Weather Widget
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                        Text("72°")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                    }
                    
                    Text("Sunny")
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.6))
                    
                    Text("New York")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.5))
                }
                .frame(width: 130, height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
            }
            .opacity(showOtherWidgets ? 1.0 : 0.0)
            .offset(y: showOtherWidgets ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.8), value: showOtherWidgets)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                showMainWidget = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                widgetGlow = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showOtherWidgets = true
            }
        }
    }
}

// MARK: - Onboarding Page View
struct OnboardingPageView: View {
    let title: String
    let description: String
    let textColor: Color
    let splitByBullets: Bool
    
    init(title: String, description: String, textColor: Color = .black, splitByBullets: Bool = false) {
        self.title = title
        self.description = description
        self.textColor = textColor
        self.splitByBullets = splitByBullets
    }
    
    var body: some View {
        VStack(spacing: 32) {
            // Title with enhanced styling
            Text(title)
                .font(.system(size: 40, weight: .bold, design: .default))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .shadow(color: textColor == .white ? .black.opacity(0.3) : .gray.opacity(0.2), radius: 3, x: 1, y: 1)
                .padding(.horizontal, 20)
            
            // Description - split by bullets if needed
            if splitByBullets {
                VStack(spacing: 16) {
                    ForEach(description.components(separatedBy: " • "), id: \.self) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "laurel.leading")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)

                            Text(line.trimmingCharacters(in: .whitespaces))
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(textColor.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .shadow(color: textColor == .white ? .black.opacity(0.2) : .clear, radius: 1)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)

                            Image(systemName: "laurel.trailing")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 32)
                    }
                }
            } else {
                // Regular description with enhanced styling
                Text(description)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(textColor.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(8)
                    .shadow(color: textColor == .white ? .black.opacity(0.2) : .clear, radius: 1)
            }
        }
        .padding(.vertical, 20)
    }
}



#Preview {
    OnboardingView(isPresented: .constant(true), onCompletion: nil)
} 