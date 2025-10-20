import SwiftUI

struct PremiumLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showPaywall: Bool
    let message: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Stoic-themed premium header with earthy colors
            VStack(spacing: 20) {
                // Philosophical column icon
                Image(systemName: "book.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.2))
                    .symbolRenderingMode(.hierarchical)
                
                VStack(spacing: 8) {
                    Text("Unlock Philosophical Wisdom")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Receive the full depth of Stoa AI's philosophical guidance")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 30)
            
            Spacer()
            
            // Clean premium benefits section
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Sacred Premium Gifts:")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        CleanPremiumBenefitRow(icon: "infinity", text: NSLocalizedString("unlimitedMessages", comment: ""), color: .yellow.opacity(0.9))
                        CleanPremiumBenefitRow(icon: "bolt", text: NSLocalizedString("fasterResponses", comment: ""), color: .yellow.opacity(0.8))
                        CleanPremiumBenefitRow(icon: "quote.bubble", text: NSLocalizedString("unlimitedQuotes", comment: ""), color: .yellow.opacity(0.7))
                        CleanPremiumBenefitRow(icon: "heart", text: NSLocalizedString("prioritySupport", comment: ""), color: .yellow.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            // Clean action buttons
            VStack(spacing: 16) {
                Button {
                    dismiss()
                    showPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "crown")
                            .font(.title3)
                        Text(NSLocalizedString("upgradeToPremium", comment: ""))
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
                    Text(NSLocalizedString("maybeLater", comment: ""))
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

struct CleanPremiumBenefitRow: View {
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
    PremiumLimitSheet(
        showPaywall: .constant(false),
        message: "You have reached the message limit for the free tier. Please upgrade to premium for unlimited messages."
    )
} 