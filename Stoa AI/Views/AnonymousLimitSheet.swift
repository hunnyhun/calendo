import SwiftUI

struct AnonymousLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showAuthSheet: Bool
    let message: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Stoic-themed header with earthy colors
            VStack(spacing: 20) {
                // Philosophical scroll icon
                Image(systemName: "scroll.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.2))
                    .symbolRenderingMode(.hierarchical)
                
                VStack(spacing: 8) {
                    Text("Join Our Philosophical Community")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Continue your philosophical conversation with Stoa AI")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 30)
            
            Spacer()
            
            // Clean benefits section
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Blessings of Faith:")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        CleanBenefitRow(icon: "infinity", text: NSLocalizedString("unlimitedMessages", comment: ""), color: .yellow.opacity(0.8))
                        CleanBenefitRow(icon: "clock", text: NSLocalizedString("chatHistory", comment: ""), color: .yellow.opacity(0.7))
                        CleanBenefitRow(icon: "quote.bubble", text: NSLocalizedString("dailyQuotes", comment: ""), color: .yellow.opacity(0.6))
                        CleanBenefitRow(icon: "icloud", text: NSLocalizedString("cloudSync", comment: ""), color: .yellow.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            // Clean action buttons
            VStack(spacing: 16) {
                Button {
                    dismiss()
                    showAuthSheet = true
                } label: {
                    HStack {
                        Image(systemName: "cross")
                            .font(.title3)
                        Text(NSLocalizedString("signUpOrLogInButton", comment: ""))
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [.yellow, .yellow.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .yellow.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("continueBrowsing", comment: ""))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

struct CleanBenefitRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    AnonymousLimitSheet(
        showAuthSheet: .constant(false),
        message: "You have reached the message limit for anonymous access. Please sign in or sign up to continue chatting."
    )
} 