import Foundation
import Security

enum KeychainError: Error {
    case saveError(OSStatus)
    case loadError(OSStatus)
    case unexpectedData
    case unhandledError(status: OSStatus)
}

class KeychainHelper {

    static let shared = KeychainHelper()
    private init() {} // Singleton

    private let service = "com.hunnyhun.stoicism" // Replace with your actual app identifier
    
    
} 