import SwiftUI

// MARK: - View Type Toggle (Custom Three-Option Toggle)
struct ViewTypeToggle: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) private var colorScheme
    
    private let tabs: [String] = ["Active", "All", "Completed"]
    
    // Helper computed properties
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }
    
    private func textColor(for index: Int) -> Color {
        if selectedTab == index {
            return .white
        } else {
            return colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let buttonWidth = geometry.size.width / CGFloat(tabs.count)
            
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
                        .offset(x: CGFloat(selectedTab) * buttonWidth)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTab)
                    
                    Spacer()
                }
                
                // Buttons overlay
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = index
                            }
                        }) {
                            Text(tab)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(textColor(for: index))
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

