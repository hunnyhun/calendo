import SwiftUI

struct SettingsViewWrapper: View {
    // Navigation binding for bottom bar
    @Binding var selectedFeature: Models.Feature
    @Binding var showPaywall: Bool
    
    // Initializer with navigation binding
    init(selectedFeature: Binding<Models.Feature> = .constant(.settings), showPaywall: Binding<Bool>) {
        self._selectedFeature = selectedFeature
        self._showPaywall = showPaywall
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Settings View Content
            SettingsView(showPaywall: $showPaywall)
            
            // Bottom Navigation Bar
            BottomNavigationBar(selectedFeature: $selectedFeature)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    SettingsViewWrapper(showPaywall: .constant(false))
}

