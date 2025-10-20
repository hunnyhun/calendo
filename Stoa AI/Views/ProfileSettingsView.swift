import SwiftUI

struct ProfileSettingsView: View {
    @State private var name: String = ""
    @State private var ageText: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    let cloud = CloudFunctionService.shared

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("Age", text: $ageText)
                    .keyboardType(.numberPad)
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save") }
                }
                .disabled(isSaving)
            }
            if let saveMessage = saveMessage {
                Section { Text(saveMessage).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Profile")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var payload: [String: Any] = [:]
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { payload["name"] = name }
        if let age = Int(ageText) { payload["age"] = age }
        do {
            try await cloud.updateUserProfile(payload)
            await MainActor.run { saveMessage = "Saved successfully" }
        } catch {
            await MainActor.run { saveMessage = "Failed to save: \(error.localizedDescription)" }
        }
    }
}

#Preview {
    NavigationView { ProfileSettingsView() }
}
