import SwiftUI

struct StoicColumn: View {
    // Configurable parameters
    let width: CGFloat
    let color: Color
    let shadowColor: Color
    var isAnimating: Bool = false
    
    // Computed properties for maintaining proportions
    private var height: CGFloat { width * 2.5 }
    private var baseWidth: CGFloat { width * 1.3 }
    private var capitalWidth: CGFloat { width * 1.3 }
    private var baseHeight: CGFloat { height * 0.15 }
    private var capitalHeight: CGFloat { height * 0.15 }
    private var shaftHeight: CGFloat { height * 0.7 }
    private var lineWidth: CGFloat { width * 0.05 }
    
    // Animation state
    @State private var glowIntensity: CGFloat = 0.0
    
    // Initializer with default values
    init(
        width: CGFloat = 40, 
        color: Color = Color(red: 0.4, green: 0.3, blue: 0.2), // Earthy brown
        shadowColor: Color = Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.3),
        isAnimating: Bool = false
    ) {
        self.width = width
        self.color = color
        self.shadowColor = shadowColor
        self.isAnimating = isAnimating
    }
    
    var body: some View {
        ZStack {
            // Glow effect for animation
            if isAnimating {
                VStack(spacing: 0) {
                    // Capital glow
                    Rectangle()
                        .stroke(color, lineWidth: lineWidth * 3)
                        .frame(width: capitalWidth, height: capitalHeight)
                        .blur(radius: 8 * glowIntensity)
                        .opacity(0.6 * glowIntensity)
                    
                    // Shaft glow
                    Rectangle()
                        .stroke(color, lineWidth: lineWidth * 3)
                        .frame(width: width, height: shaftHeight)
                        .blur(radius: 10 * glowIntensity)
                        .opacity(0.6 * glowIntensity)
                    
                    // Base glow
                    Rectangle()
                        .stroke(color, lineWidth: lineWidth * 3)
                        .frame(width: baseWidth, height: baseHeight)
                        .blur(radius: 8 * glowIntensity)
                        .opacity(0.6 * glowIntensity)
                }
            }
            
            // Main column structure - clean line art style
            VStack(spacing: 0) {
                // Capital (top) - simple rectangle outline
                Rectangle()
                    .stroke(color, lineWidth: lineWidth)
                    .frame(width: capitalWidth, height: capitalHeight)
                
                // Shaft with fluting lines
                ZStack {
                    // Main shaft outline
                    Rectangle()
                        .stroke(color, lineWidth: lineWidth)
                        .frame(width: width, height: shaftHeight)
                    
                    // Vertical fluting lines (3-4 lines)
                    HStack(spacing: width * 0.2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(color)
                                .frame(width: lineWidth * 0.7, height: shaftHeight * 0.9)
                        }
                    }
                }
                
                // Base (bottom) - simple rectangle outline
                Rectangle()
                    .stroke(color, lineWidth: lineWidth)
                    .frame(width: baseWidth, height: baseHeight)
            }
        }
        .frame(width: baseWidth, height: height)
        .compositingGroup()
        .onAppear {
            if isAnimating {
                withAnimation(Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    glowIntensity = 1.0
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 30) {
        StoicColumn(width: 60, color: .black, shadowColor: .gray.opacity(0.3), isAnimating: true)
        
        StoicColumn(width: 40, color: Color(red: 0.3, green: 0.3, blue: 0.3), shadowColor: .gray.opacity(0.3))
        
        StoicColumn(width: 30, color: Color(red: 0.2, green: 0.4, blue: 0.6), shadowColor: .blue.opacity(0.3))
    }
    .padding()
    .background(Color.white)
}