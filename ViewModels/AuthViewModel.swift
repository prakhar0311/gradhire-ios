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

    enum SignOutReason {
        case user
        case deleted
        case expired
    }

    /// Why the last sign-out happened (nil: the server ended the session).
    @Published private(set) var lastSignOutReason: SignOutReason?
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
            // Signed out without us asking: the server ended the session
            if case .signedIn = state, lastSignOutReason == nil {
                lastSignOutReason = .expired
            }
            state = .signedOut
            return
        }
        if self.user == nil { lastSignOutReason = nil }
        // Apple only shares the name once; keep the one we already have
        if user.name == nil, let known = self.user, known.id == user.id {
            user.name = known.name
        }
        state = .signedIn(user)
    }

    // MARK: Launch

    /// Checks the stored session (refreshing it if it expired). Returns false
    /// and signs out on this device when the server rejected it; offline, the
    /// session is kept so the app opens with cached data.
    func validateStoredSession() async -> Bool {
        // Offline: keep the session and open with cached data
        guard NetworkMonitor.shared.isConnected else { return auth.currentUser() != nil }
        let check = await auth.checkStoredSession()
        if Task.isCancelled { return true } // timed out; never sign out for that
        switch check {
        case .none:
            return false
        case .valid, .offline:
            return true
        case .invalid:
            await expireSession()
            return false
        }
    }

    /// The session can't be used any more: sign out on this device only.
    func expireSession() async {
        lastSignOutReason = .expired
        await auth.signOutLocally()
        GoogleSignInHelper.signOut()
        state = .signedOut
        resumeSaveStatus = .idle
    }

    // MARK: Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.make()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
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

                didSignIn(user)
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    // MARK: Google Sign-In

    func signInWithGoogle() async {
        isWorking = true
        defer { isWorking = false }

        do {
            let tokens = try await GoogleSignInHelper.signIn()
            let user = try await auth.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
            didSignIn(user)
        } catch {
            if !GoogleSignInHelper.isCancellation(error) {
                errorMessage = message(for: error)
            }
        }
    }

    private func didSignIn(_ user: AuthUser) {
        lastSignOutReason = nil
        state = .signedIn(user)
        resumeSaveStatus = .idle
    }

    // MARK: Sign Out / Delete

    func signOut() async {
        isWorking = true
        lastSignOutReason = .user
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
            lastSignOutReason = .deleted
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

    /// Uploads the resume already loaded on this device to resumes/{user id}/
    /// and records it as their original resume. Only runs when the user
    /// chooses Save. Returns the new resume's id.
    @discardableResult
    func saveGuestResume(pdfData data: Data, text: String?, title: String? = nil) async -> UUID? {
        resumeSaveStatus = .saving

        do {
            let fileName = "resume-\(Int(Date().timeIntervalSince1970)).pdf"
            let path = try await resumes.uploadResumeFile(data, fileName: fileName)

            var resume = NewResume(kind: .original)
            resume.title = title ?? "My resume"
            resume.filePath = path
            if let text, !text.isEmpty {
                resume.parsedData = .object(["text": .string(text)])
            }
            let record = try await resumes.createResume(resume)

            resumeSaveStatus = .saved
            return record.id
        } catch {
            resumeSaveStatus = .failed(message(for: error))
            return nil
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
