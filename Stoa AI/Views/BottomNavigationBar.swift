import SwiftUI

struct BottomNavigationBar: View {
    @Binding var selectedFeature: Models.Feature
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Reminders Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedFeature = .reminders
                }
            }) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 28))
                    .foregroundColor(selectedFeature == .reminders ? Color.brandPrimary : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            
            // Calendar Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedFeature = .calendar
                }
            }) {
                Image(systemName: "calendar")
                    .font(.system(size: 28))
                    .foregroundColor(selectedFeature == .calendar ? Color.brandPrimary : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            
            // Chat Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedFeature = .chat
                }
            }) {
                Image(systemName: "message.fill")
                    .font(.system(size: 28))
                    .foregroundColor(selectedFeature == .chat ? Color.brandPrimary : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            
            // Tracking Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedFeature = .tracking
                }
            }) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 28))
                    .foregroundColor(selectedFeature == .tracking ? Color.brandPrimary : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            
            // Blog Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedFeature = .blog
                }
            }) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 28))
                    .foregroundColor(selectedFeature == .blog ? Color.brandPrimary : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .white))
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

