import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices
import FirebaseCore
import FirebaseFunctions
import CryptoKit
import UIKit

// AuthenticationManager: Handles all authentication related operations
@Observable final class AuthenticationManager {
    // MARK: - Properties
    var user: User?
    var errorMessage: String?
    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    
    // MARK: - Singleton
    static let shared = AuthenticationManager()
    private init() {
        setupAuthStateListener()
    }
    
    // MARK: - Auth State
    private func setupAuthStateListener() {
        // Store listener handle to prevent deallocation
        let handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil
                Logger.debug("Auth state changed. User: \(user?.uid ?? "nil")", logger: Logger.auth)
            }
        }
        Logger.debug("Auth state listener setup with handle: \(handle)", logger: Logger.auth)
    }
    
    // MARK: - Sign In Methods
    
    // Google Sign In
    func signInWithGoogle() async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            Logger.error("Failed to get Google client ID", logger: Logger.auth)
            throw AuthError.clientIDNotFound
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let rootViewController = try await getRootViewController()
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                Logger.error("Failed to get ID token from Google Sign In", logger: Logger.auth)
                throw AuthError.tokenError
            }
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            
            // Sign in with Google credential
            try await authenticateWithCredential(credential, provider: "Google")
            
            // Ensure device registration after Google sign in
            await ensureDeviceRegistration()
        } catch {
            Logger.error("Google sign in error", logger: Logger.auth, error: error)
            throw error
        }
    }
    
    // Apple Sign In
    func signInWithApple() async throws {
        let nonce = randomNonceString()
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let rootViewController = try await getRootViewController()
        
        do {
            let result = try await performAppleSignIn(request, on: rootViewController)
            guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                Logger.error("Failed to extract Apple ID token", logger: Logger.auth)
                throw AuthError.credentialError
            }
            
            let credential = OAuthProvider.credential(
                providerID: .apple,
                idToken: idTokenString,
                rawNonce: nonce,
                accessToken: nil
            )
            
            // Sign in with Apple credential
            try await authenticateWithCredential(credential, provider: "Apple")
            
            // Ensure device registration after Apple sign in
            await ensureDeviceRegistration()
        } catch {
            Logger.error("Apple sign in error", logger: Logger.auth, error: error)
            throw error
        }
    }
    
    // Sign Out
    func signOut() async throws {
        do {
            try Auth.auth().signOut()
            self.user = nil // Update local state immediately
            Logger.debug("Successfully signed out from Firebase", logger: Logger.auth)
        } catch let signOutError {
            Logger.error("Sign out error", logger: Logger.auth, error: signOutError)
            throw signOutError
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get root view controller for presenting auth UI
    private func getRootViewController() async throws -> UIViewController {
        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = await windowScene.windows.first,
              let rootViewController = await window.rootViewController else {
            Logger.error("Failed to get root view controller", logger: Logger.auth)
            throw AuthError.presentationError
        }
        return rootViewController
    }
    
    /// Sign in with credential
    private func authenticateWithCredential(_ credential: AuthCredential, provider: String) async throws {
            let authResult = try await Auth.auth().signIn(with: credential)
            self.user = authResult.user
            Logger.info("Successfully signed in with \(provider). User: \(authResult.user.uid)", logger: Logger.auth)
    }
    
    /// Ensure device registration after authentication with retry logic
    private func ensureDeviceRegistration() async {
        Logger.debug("Ensuring device registration after authentication", logger: Logger.auth)
        
        var retryCount = 0
        
        while retryCount < AppConfiguration.Auth.maxDeviceRegistrationRetries {
            // Check if user ID is available
            if UserStatusManager.shared.state.userId != nil {
                Logger.debug("User ID available, proceeding with device registration", logger: Logger.auth)
                break
            }
            
            Logger.debug("User ID not yet available, retrying (attempt \(retryCount + 1)/\(AppConfiguration.Auth.maxDeviceRegistrationRetries))", logger: Logger.auth)
            
            // Wait before retry
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConfiguration.Auth.deviceRegistrationRetryDelay) {
                    continuation.resume()
                }
            }
            retryCount += 1
        }
        
        if UserStatusManager.shared.state.userId == nil {
            Logger.warning("Failed to get user ID after \(AppConfiguration.Auth.maxDeviceRegistrationRetries) attempts, device registration may fail", logger: Logger.auth)
        }
        
        // Use NotificationManager's ensureDeviceRegistration method
        await NotificationManager.shared.ensureDeviceRegistration()
    }
    
    // Store delegate as a property to prevent deallocation
    private var appleSignInDelegate: AppleSignInDelegate?
    
    @MainActor
    func performAppleSignIn(_ request: ASAuthorizationAppleIDRequest, on controller: UIViewController) async throws -> ASAuthorization {
        return try await withCheckedThrowingContinuation { continuation in
            let authController = ASAuthorizationController(authorizationRequests: [request])
            // Store delegate in property to maintain strong reference
            self.appleSignInDelegate = AppleSignInDelegate(continuation: continuation)
            authController.delegate = self.appleSignInDelegate
            authController.presentationContextProvider = self.appleSignInDelegate
            authController.performRequests()
        }
    }
    
    // MARK: - Crypto Helpers
    
    // Generate random nonce for Apple Sign In
    func randomNonceString(length: Int = AppConfiguration.Auth.nonceLength) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 { return }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
    
    // SHA256 hash for nonce using CryptoKit
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Custom Errors
extension AuthenticationManager {
    enum AuthError: LocalizedError {
        case clientIDNotFound
        case presentationError
        case tokenError
        case credentialError
        
        var errorDescription: String? {
            switch self {
            case .clientIDNotFound:
                return "Failed to get Google client ID"
            case .presentationError:
                return "Unable to present sign-in screen"
            case .tokenError:
                return "Failed to get authentication token"
            case .credentialError:
                return "Invalid credentials provided"
            }
        }
    }
}

// MARK: - Apple Sign In Delegate
@MainActor
private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let continuation: CheckedContinuation<ASAuthorization, Error>
    
    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window found")
        }
        return window
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization)
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
}
