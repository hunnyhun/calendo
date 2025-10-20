import SwiftUI
import Foundation

// MARK: - Enhanced Streaming Effects
struct StreamingEffects {
    
    // MARK: - Typing Sound Simulation
    static func simulateTypingSound() {
        // Haptic feedback to simulate typing sound
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred(intensity: 0.3)
    }
    
    // MARK: - Streaming Animation Constants
    struct AnimationConstants {
        static let textAppearDuration: Double = 0.1
        static let cursorBlinkDuration: Double = 0.8
        static let streamingIndicatorDuration: Double = 1.2
        static let pulseScale: CGFloat = 1.1
    }
}

// MARK: - Enhanced Streaming Indicator with Sound
struct EnhancedStreamingIndicator: View {
    @State private var animationOffset = 0.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var shouldPlaySound = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 5, height: 5)
                    .foregroundColor(.blue)
                    .opacity(0.3 + 0.7 * sin(animationOffset + Double(index) * 0.8))
                    .scaleEffect(pulseScale)
                    .animation(
                        Animation.easeInOut(duration: StreamingEffects.AnimationConstants.streamingIndicatorDuration)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationOffset
                    )
            }
        }
        .onAppear {
            animationOffset = 1.0
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = StreamingEffects.AnimationConstants.pulseScale
            }
            
            // Simulate typing sound after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if shouldPlaySound {
                    StreamingEffects.simulateTypingSound()
                }
            }
        }
        .onChange(of: shouldPlaySound) { _, newValue in
            if newValue {
                StreamingEffects.simulateTypingSound()
            }
        }
    }
}

// MARK: - Advanced Blinking Cursor
struct AdvancedBlinkingCursor: View {
    @State private var visible = true
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // Glow effect
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 4, height: 20)
                .blur(radius: 2)
                .opacity(glowOpacity)
                .scaleEffect(pulseScale)
            
            // Main cursor
            Rectangle()
                .fill(Color.blue.opacity(0.9))
                .frame(width: 2, height: 18)
                .opacity(visible ? 1 : 0)
                .scaleEffect(pulseScale)
        }
        .onAppear {
            // Blinking animation
            withAnimation(.easeInOut(duration: StreamingEffects.AnimationConstants.cursorBlinkDuration).repeatForever(autoreverses: true)) {
                visible.toggle()
            }
            
            // Pulse animation
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = StreamingEffects.AnimationConstants.pulseScale
            }
            
            // Glow animation
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glowOpacity = 0.6
            }
        }
    }
}

// MARK: - Streaming Message Container
struct StreamingMessageContainer: View {
    let isStreaming: Bool
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Content with streaming effects
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
                .animation(.easeInOut(duration: StreamingEffects.AnimationConstants.textAppearDuration), value: content.count)
            
            // Enhanced cursor when streaming
            if isStreaming {
                AdvancedBlinkingCursor()
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isStreaming ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Typing Indicator with Enhanced Animation
struct EnhancedTypingIndicator: View {
    @State private var animationOffset = 0.0
    @State private var dotScales: [CGFloat] = [1.0, 1.0, 1.0]
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundColor(.gray)
                    .scaleEffect(dotScales[index])
                    .offset(y: sin(animationOffset + Double(index) * 0.5) * 3)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationOffset
                    )
            }
        }
        .onAppear {
            animationOffset = 2 * .pi
            
            // Scale animation for dots
            for index in 0..<3 {
                withAnimation(
                    Animation.easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2)
                ) {
                    dotScales[index] = 1.3
                }
            }
        }
    }
}

// MARK: - Streaming Progress Bar
struct StreamingProgressBar: View {
    @State private var progress: CGFloat = 0.0
    let isStreaming: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 2)
                
                // Progress bar
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .blue.opacity(0.7)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 2)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 2)
        .onAppear {
            if isStreaming {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    progress = 1.0
                }
            }
        }
        .onChange(of: isStreaming) { _, newValue in
            if newValue {
                progress = 0.0
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    progress = 1.0
                }
            } else {
                progress = 1.0
            }
        }
    }
}
