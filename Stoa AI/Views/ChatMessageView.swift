import SwiftUI
// Import the ChatMessage model
// Assuming ChatMessage is in the main target and not part of a separate module
// If ChatMessage is in a module named 'Models', it would be 'import Models'

// If ChatMessage.swift is just a file in your project directly under StoaAI/Models/,
// and your project is named StoaAI, Swift should find it without an explicit import
// for files within the same target. However, explicitly stating the model's origin
// can sometimes help, or if it were in a different module, it would be essential.
// For now, let's assume direct availability or rely on the build system to link it.

// struct ChatMessage: Identifiable, Equatable {
//     let id: String
//     var text: String
//     let isUser: Bool
//     let timestamp: Date
// }

struct ChatMessageView: View {
    let message: ChatMessage // Your existing ChatMessage model
    
    @State private var displayedText: String = ""
    @State private var characterIndex: Int = 0
    private let animationSpeed: Double = 0.02 // Adjust for faster/slower typing

    var body: some View {
        HStack {
            if message.isUser {
                Spacer() 
                Text(message.text) 
                    .padding(12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous)) // For better tap targets if needed
            } else {
                Text(displayedText) 
                    .padding(12)
                    .background(Color(uiColor: .systemGray5)) // Adapts to light/dark mode
                    .foregroundColor(Color(uiColor: .label)) // Adapts to light/dark mode
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                Spacer() 
            }
        }
        .id(message.id) // Ensure each message view has a unique ID for list updates
        .padding(.vertical, 4) // Add a little vertical spacing between messages
        .onAppear {
            if message.isUser {
                displayedText = message.text
            } else {
                // If it's an AI message and text is already populated (e.g., loading history)
                // or if animation hasn't started.
                if !message.text.isEmpty && displayedText != message.text {
                    displayedText = ""
                    characterIndex = 0
                    animateText()
                }
            }
        }
        .onChange(of: message.text) { oldValue, newValue in
            if !message.isUser {
                // If the new text doesn't start with what's currently displayed,
                // or if the new text is shorter than what's displayed (e.g., a correction from the stream),
                // then reset the animation for this message.
                if !newValue.starts(with: displayedText) || newValue.count < displayedText.count {
                    displayedText = ""    // Reset displayed text
                    characterIndex = 0    // Reset character index
                }
                
                // Always call animateText.
                // - If reset, it will start typing 'newValue' from the beginning.
                // - If not reset (newValue is an append), it will continue from where it left off.
                // - If already fully typed, it will do nothing.
                animateText()
            } else {
                // For user messages, if text changes, update it directly.
                displayedText = newValue
            }
        }
    }

    private func animateText() {
        // Guard against animating user messages or if already fully displayed
        if message.isUser || characterIndex >= message.text.count {
            // Ensure final text is accurate if animation finishes early or for user messages
            if displayedText != message.text {
                 displayedText = message.text
            }
            return
        }

        // Append one character
        let currentStringIndex = message.text.index(message.text.startIndex, offsetBy: characterIndex)
        displayedText.append(message.text[currentStringIndex])
        characterIndex += 1

        // Schedule next character
        // Ensure this runs on the main thread, though asyncAfter typically does.
        DispatchQueue.main.asyncAfter(deadline: .now() + animationSpeed) {
            // Check if the view is still around and the message text hasn't changed drastically
            // This is a safety check, primarily covered by onChange
            guard characterIndex <= message.text.count else {
                // If message text became shorter or something unexpected, ensure displayedText reflects actual
                if self.displayedText != self.message.text && !self.message.isUser {
                    self.displayedText = self.message.text
                }
                return
            }
            animateText()
        }
    }
}

struct ChatMessageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ChatMessageView(message: ChatMessage(id: "1", text: "Hello, this is a user message.", isUser: true, timestamp: Date()))
            ChatMessageView(message: ChatMessage(id: "2", text: "Hi there! I am an AI assistant providing a rather long response to demonstrate the typing animation effect. Let's see how it goes.", isUser: false, timestamp: Date()))
            ChatMessageView(message: ChatMessage(id: "3", text: "Another user.", isUser: true, timestamp: Date()))
            ChatMessageView(message: ChatMessage(id: "4", text: "AI short.", isUser: false, timestamp: Date()))
        }
        .padding()
    }
} 