import Foundation
import Combine
import AuthenticationServices
import Supabase

// MARK: - Auth View Model (app-wide)

/// Sign-in state for the whole app. Guests can use everything they could
/// before; signing in is optional.
final class AuthViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(AuthUser)
    }

    enum ResumeSaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    /// Set right after the first sign-in when a resume is loaded; the account
    /// screen then asks "Save this resume to your account?" (opt-in).
    @Published var offerResumeSave = false
    @Published private(set) var resumeSaveStatus: ResumeSaveStatus = .idle

    private let auth: any AuthRepository
    private let resumes: any ResumeRepository
    private var listenTask: Task<Void, Never>?
    private var appleNonce: String?

    var isConfigured: Bool { auth.isConfigured }

    var user: AuthUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    init(auth: any AuthRepository, resumes: any ResumeRepository) {
        self.auth = auth
        self.resumes = resumes
        self.state = auth.currentUser().map { .signedIn($0) } ?? (auth.isConfigured ? .loading : .signedOut)
    }

    /// Follows Supabase auth changes (stored session on launch, sign-in,
    /// token refresh, sign-out). Call once from the app root.
    func start() {
        guard listenTask == nil else { return }
        listenTask = Task {
            for await user in auth.authChanges() {
                apply(user)
            }
        }
    }

    private func apply(_ user: AuthUser?) {
        guard var user else {
            state = .signedOut
            return
        }
        // Apple only shares the name once; keep the one we already have
        if user.name == nil, let known = self.user, known.id == user.id {
            user.name = known.name
        }
        state = .signedIn(user)
    }

    // MARK: Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.make()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>, hasResumeToOffer: Bool) async {
        switch result {
        case .failure(let error):
            if !AppleSignInNonce.isCancellation(error) {
                errorMessage = message(for: error)
            }

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = appleNonce
            else {
                errorMessage = AuthFlowError.missingToken.localizedDescription
                return
            }

            isWorking = true
            defer { isWorking = false }

            do {
                var user = try await auth.signInWithApple(idToken: idToken, nonce: nonce)

                // Apple sends the name only on the very first sign-in
                if let fullName = credential.fullName {
                    let name = PersonNameComponentsFormatter().string(from: fullName)
                        .trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        try? await auth.updateName(name)
                        user.name = name
                    }
                }

                didSignIn(user, hasResumeToOffer: hasResumeToOffer)
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    // MARK: Google Sign-In

    func signInWithGoogle(hasResumeToOffer: Bool) async {
        isWorking = true
        defer { isWorking = false }

        do {
            let tokens = try await GoogleSignInHelper.signIn()
            let user = try await auth.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
            didSignIn(user, hasResumeToOffer: hasResumeToOffer)
        } catch {
            if !GoogleSignInHelper.isCancellation(error) {
                errorMessage = message(for: error)
            }
        }
    }

    private func didSignIn(_ user: AuthUser, hasResumeToOffer: Bool) {
        state = .signedIn(user)
        resumeSaveStatus = .idle
        offerResumeSave = hasResumeToOffer
    }

    // MARK: Sign Out / Delete

    func signOut() async {
        isWorking = true
        await auth.signOut()
        GoogleSignInHelper.signOut()
        state = .signedOut
        resumeSaveStatus = .idle
        isWorking = false
    }

    /// Returns true when the account was deleted. Apple users confirm with
    /// Apple first so the backend can revoke their Apple tokens.
    func deleteAccount() async -> Bool {
        var appleCode: String?

        if user?.provider == "apple" {
            do {
                let authorizer = AppleReauthorizer()
                let credential = try await authorizer.authorize()
                appleCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            } catch {
                if !AppleSignInNonce.isCancellation(error) {
                    errorMessage = message(for: error)
                }
                return false
            }
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await auth.deleteAccount(appleAuthorizationCode: appleCode)
            GoogleSignInHelper.signOut()
            state = .signedOut
            resumeSaveStatus = .idle
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    // MARK: Guest Resume (opt-in)

    /// Uploads the resume the guest already loaded to resumes/{user id}/ and
    /// records it as their original resume. Only runs when the user chooses Save.
    func saveGuestResume(fileURL: URL, text: String?) async {
        resumeSaveStatus = .saving

        do {
            let data = try Data(contentsOf: fileURL)
            let fileName = "resume-\(Int(Date().timeIntervalSince1970)).pdf"
            let path = try await resumes.uploadResumeFile(data, fileName: fileName)

            var resume = NewResume(kind: .original)
            resume.title = "My resume"
            resume.filePath = path
            if let text, !text.isEmpty {
                resume.parsedData = .object(["text": .string(text)])
            }
            _ = try await resumes.createResume(resume)

            resumeSaveStatus = .saved
        } catch {
            resumeSaveStatus = .failed(message(for: error))
        }
    }

    // MARK: Errors

    private func message(for error: Error) -> String {
        if let flowError = error as? AuthFlowError { return flowError.localizedDescription }
        if let repositoryError = error as? RepositoryError { return repositoryError.localizedDescription }
        if error is URLError { return JobAPIError.from(error).localizedDescription }
        if let apiError = error as? JobAPIError { return apiError.localizedDescription }

        let text = error.localizedDescription.lowercased()
        if text.contains("provider is not enabled") || text.contains("unsupported provider") {
            return "This sign-in option isn't available yet."
        }
        if text.contains("network") || text.contains("offline") || text.contains("internet") {
            return JobAPIError.offline.localizedDescription
        }
        return "Sign-in didn't work. Please try again."
    }
}
