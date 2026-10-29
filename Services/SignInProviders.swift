import Foundation
import UIKit
import CryptoKit
import AuthenticationServices
import GoogleSignIn

// MARK: - Sign in with Apple: Nonce

/// Apple signs the SHA-256 of a random nonce into its ID token; Supabase checks
/// the raw nonce against it, so a stolen ID token can't be replayed.
enum AppleSignInNonce {

    static func make(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}

// MARK: - Sign in with Apple: Re-confirmation

/// Runs Sign in with Apple without a button. Used before account deletion to
/// get a fresh authorization code, which the backend uses to revoke the
/// user's Apple tokens (an App Store requirement).
final class AppleReauthorizer: NSObject, ASAuthorizationControllerDelegate,
                               ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func authorize() async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: AuthFlowError.missingToken)
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.activeKeyWindow ?? ASPresentationAnchor()
    }
}

// MARK: - Google Sign-In

enum GoogleSignInHelper {

    /// The iOS OAuth client ID from Info.plist, or nil while it's a placeholder.
    static var clientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !id.isEmpty, !id.hasPrefix("your-"), !id.contains("$(") else { return nil }
        return id
    }

    static func signIn() async throws -> (idToken: String, accessToken: String) {
        guard let clientID else { throw AuthFlowError.googleNotConfigured }
        guard let presenter = UIApplication.shared.topViewController else { throw AuthFlowError.missingToken }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

        guard let idToken = result.user.idToken?.tokenString else { throw AuthFlowError.missingToken }
        return (idToken, result.user.accessToken.tokenString)
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// Completes the Google flow when it returns to the app through the URL scheme.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.Code.canceled.rawValue
    }
}

// MARK: - Presentation Helpers

extension UIApplication {

    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// The view controller currently on top, for SDKs that present their own UI.
    var topViewController: UIViewController? {
        var top = activeKeyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
