import SwiftUI

struct BlogView: View {
    @Binding var selectedFeature: Models.Feature
    @Environment(\.colorScheme) private var colorScheme
    
    // Initializer with navigation binding
    init(selectedFeature: Binding<Models.Feature> = .constant(.blog)) {
        self._selectedFeature = selectedFeature
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content with padding
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
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
                
                Text("Blog")
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
            Spacer()
            
            Text("Blog")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("Popular habits and tasks will be shown here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    BlogView(selectedFeature: .constant(.blog))
}

