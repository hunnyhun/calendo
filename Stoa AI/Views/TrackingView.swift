import SwiftUI

struct TrackingView: View {
    // Navigation binding for bottom bar
    @Binding var selectedFeature: Models.Feature
    
    // Initializer with navigation binding
    init(selectedFeature: Binding<Models.Feature> = .constant(.tracking)) {
        self._selectedFeature = selectedFeature
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content with padding
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content - placeholder for now
                contentView
            }
            .padding(.horizontal, 15)
            
            Spacer()
            
            // Bottom Navigation Bar - extends to edges
            BottomNavigationBar(selectedFeature: $selectedFeature)
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 16) {
            // Title
            HStack {
                Spacer()
                
                Text("Tracking")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Content View
    private var contentView: some View {
        VStack(spacing: 20) {
            Text("Tracking View")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("This view will be designed later")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    TrackingView(selectedFeature: .constant(.tracking))
}

