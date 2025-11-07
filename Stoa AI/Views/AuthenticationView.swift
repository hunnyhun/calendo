import SwiftUI
import RevenueCat

// MARK: - Background Components
struct PhilosophicalBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        // Base gradient
        LinearGradient(
            colors: [
                Color(red: 0.2, green: 0.3, blue: 0.4),  // Deep slate blue
                Color(red: 0.3, green: 0.4, blue: 0.5),  // Medium slate blue  
                Color(red: 0.4, green: 0.5, blue: 0.6),  // Light slate blue
                Color(red: 0.2, green: 0.25, blue: 0.35) // Dark slate
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .hueRotation(.degrees(animateGradient ? 2 : 0))
        .onAppear {
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
        .ignoresSafeArea()
    }
}

struct PhilosophicalParticles: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Background sparkles - increased from 40 to 60 with wider range
            ForEach(0..<60) { index in
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: CGFloat.random(in: 1.5...4.5))
                    .offset(
                        x: CGFloat.random(in: -300...300),
                        y: CGFloat.random(in: -600...600)
                    )
                    .animation(
                        Animation.linear(duration: Double.random(in: 4...9))
                            .repeatForever(autoreverses: true)
                            .delay(Double.random(in: 0...4)),
                        value: animate
                    )
            }
            
            // Twinkling sparkles - increased from 25 to 35 with more motion
            ForEach(0..<35) { index in
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: CGFloat.random(in: 1...3.5))
                    .offset(
                        x: CGFloat.random(in: -250...250),
                        y: CGFloat.random(in: -500...500)
                    )
                    .scaleEffect(animate ? CGFloat.random(in: 1.1...1.4) : CGFloat.random(in: 0.4...0.7))
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 1.5...4))
                            .repeatForever(autoreverses: true)
                            .delay(Double.random(in: 0...3)),
                        value: animate
                    )
            }
            
            // Small fast-moving dots - new element
            ForEach(0..<20) { index in
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: CGFloat.random(in: 1...2))
                    .offset(
                        x: CGFloat.random(in: -280...280) + (animate ? CGFloat.random(in: -40...40) : 0),
                        y: CGFloat.random(in: -550...550) + (animate ? CGFloat.random(in: -40...40) : 0)
                    )
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 0.8...1.5))
                            .repeatForever(autoreverses: true),
                        value: animate
                    )
            }
            
            // Glowing holy lights - increased from 10 to 15 with more variety
            ForEach(0..<15) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [.white, .white.opacity(0)]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 5
                        )
                    )
                    .frame(width: CGFloat.random(in: 4...9))
                    .offset(
                        x: CGFloat.random(in: -240...240),
                        y: CGFloat.random(in: -480...480)
                    )
                    .opacity(animate ? CGFloat.random(in: 0.6...0.8) : CGFloat.random(in: 0.2...0.4))
                    .scaleEffect(animate ? CGFloat.random(in: 0.9...1.2) : CGFloat.random(in: 0.7...0.9))
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 2...6))
                            .repeatForever(autoreverses: true)
                            .delay(Double.random(in: 0...3)),
                        value: animate
                    )
            }
            
            // Cross-shaped sparkles - increased from 8 to 12 with more motion
            ForEach(0..<12) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat.random(in: 10...20)))
                    .foregroundColor(.white.opacity(0.5))
                    .offset(
                        x: CGFloat.random(in: -220...220) + (animate ? CGFloat.random(in: -25...25) : 0),
                        y: CGFloat.random(in: -450...450) + (animate ? CGFloat.random(in: -25...25) : 0)
                    )
                    .opacity(animate ? CGFloat.random(in: 0.7...0.9) : CGFloat.random(in: 0.3...0.5))
                    .scaleEffect(animate ? CGFloat.random(in: 1.0...1.3) : CGFloat.random(in: 0.7...0.9))
                    .rotationEffect(Angle(degrees: animate ? Double.random(in: -15...15) : 0))
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 2...4))
                            .repeatForever(autoreverses: true)
                            .delay(Double.random(in: 0...2)),
                        value: animate
                    )
            }
            
            // Additional star symbols - new element
            ForEach(0..<8) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: CGFloat.random(in: 4...8)))
                    .foregroundColor(.white.opacity(0.4))
                    .offset(
                        x: CGFloat.random(in: -200...200),
                        y: CGFloat.random(in: -400...400)
                    )
                    .opacity(animate ? CGFloat.random(in: 0.6...0.8) : CGFloat.random(in: 0.2...0.4))
                    .scaleEffect(animate ? CGFloat.random(in: 1.0...1.2) : CGFloat.random(in: 0.6...0.8))
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 3...5))
                            .repeatForever(autoreverses: true)
                            .delay(Double.random(in: 0...2)),
                        value: animate
                    )
            }
        }
        .onAppear { 
            // Start animation with debug log
            print("DEBUG: [HolySparkles] Starting animation with enhanced particles")
            animate.toggle() 
        }
    }
}

struct AuthenticationView: View {
    // MARK: - Properties
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var animateCross = false
    @State private var showNotificationAlert = false
    @State private var showAuthSuccessAlert = false
    @State private var showSubscriptionSuccessAlert = false
    
    // Callback for when authentication succeeds
    var onAuthenticationSuccess: (() -> Void)? = nil
    
    // MARK: - Environment
    let authManager = AuthenticationManager.shared
    let notificationManager = NotificationManager.shared
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                // White Background
                Color.white
                    .ignoresSafeArea()
                
                // Main Content
                VStack(spacing: 0) {
                    // Logo and Title
                    VStack(spacing: 32) {
                        // App Logo
                        Image("logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 10)
                            .padding(.top, 60)
                        
                        // Big Calendo Text
                        Text("Calendo")
                            .font(.system(size: 56, weight: .bold, design: .default))
                            .foregroundColor(.black)
                    }
                    .padding(.top, 40)
                    
                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 16, design: .default))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    Spacer()
                    
                    // Authentication Buttons
                    VStack(spacing: 16) {
                        // Google Sign In
                        Button(action: handleGoogleSignIn) {
                            HStack {
                                Image("googleicon")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                Text("continueWithGoogle".localized)
                                    .font(.system(size: 18, weight: .medium, design: .default))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(25)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 10)
                        }
                        .opacity(isLoading ? 0.6 : 1.0)
                        .disabled(isLoading)
                        .animation(.easeInOut(duration: 0.2), value: isLoading)
                        
                        // Apple Sign In
                        Button(action: handleAppleSignIn) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.title2)
                                Text("continueWithApple".localized)
                                    .font(.system(size: 18, weight: .medium, design: .default))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .foregroundColor(.white)
                            .cornerRadius(25)
                            .shadow(color: .black.opacity(0.1), radius: 10)
                        }
                        .opacity(isLoading ? 0.6 : 1.0)
                        .disabled(isLoading)
                        .animation(.easeInOut(duration: 0.2), value: isLoading)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 50)
                }
                
                // --- ADD Loading Overlay --- 
                if isLoading {
                    ZStack {
                        // Semi-transparent background
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                            .transition(.opacity) // Fade in/out
                        
                        // Centered ProgressView
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(2.0) // Make it larger
                    }
                    .animation(.easeInOut(duration: 0.3), value: isLoading) // Animate the overlay
                }
                // --- END Loading Overlay ---
            }
        }
        .alert("authSuccessTitle".localized, isPresented: $showAuthSuccessAlert) {
            Button("ok".localized) {
                onAuthenticationSuccess?()
                dismiss()
            }
        } message: {
            Text("authSuccessMessage".localized)
        }
        .alert("subscriptionSuccessTitle".localized, isPresented: $showSubscriptionSuccessAlert) {
            Button("ok".localized) {
                dismiss()
            }
        } message: {
            Text("subscriptionSuccessMessage".localized)
        }
    }
    
    // MARK: - Actions
    private func handleGoogleSignIn() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                // Attempt Google Sign In
                print("DEBUG: [AuthView] Attempting Google sign in")
                try await authManager.signInWithGoogle()
                
                // Check if notification permission is needed (optional, can be moved)
                // await checkAndRequestNotificationPermission()
                
                print("DEBUG: [AuthView] Google sign in successful")
                showAuthSuccessAlert = true
            } catch {
                print("ERROR: [AuthView] Google Sign In Failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription // Show error message
            }
            isLoading = false
        }
    }
    
    private func handleAppleSignIn() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                // Attempt Apple Sign In
                print("DEBUG: [AuthView] Attempting Apple sign in")
                try await authManager.signInWithApple()
                
                // Check if notification permission is needed (optional, can be moved)
                // await checkAndRequestNotificationPermission()
                
                print("DEBUG: [AuthView] Apple sign in successful")
                showAuthSuccessAlert = true
            } catch {
                print("ERROR: [AuthView] Apple Sign In Failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription // Show error message
            }
            isLoading = false
        }
    }
    
    // Helper to check if an error is a cancellation
    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Check for common cancellation error codes and domains
        if nsError.domain == "com.google.GIDSignIn" && nsError.code == -5 {
            return true // Google Sign In cancellation
        }
        
        if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && 
           (nsError.code == 1000 || nsError.code == 1001) {
            return true // Apple Sign In cancellation
        }
        
        // Check for common cancellation error messages
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("cancel") || 
               errorString.contains("cancelled") || 
               errorString.contains("canceled")
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview
#Preview {
    AuthenticationView()
} 