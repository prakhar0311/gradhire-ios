import Foundation
import Supabase

// MARK: - Auth User

nonisolated struct AuthUser: Equatable, Sendable {
    let id: UUID
    let email: String?
    var name: String?
    let provider: String? // "apple", "google" (or "email" for test accounts)
}

// MARK: - Errors

/// Result of checking the stored session at launch.
nonisolated enum StoredSessionCheck: Sendable {
    case none     // nobody signed in
    case valid
    case offline  // expired but couldn't refresh (no network): keep it for now
    case invalid  // the server rejected it: sign out
}

nonisolated enum AuthFlowError: LocalizedError {
    case notConfigured
    case googleNotConfigured
    case missingToken
    case sessionExpired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:       return "Sign-in isn't available right now."
        case .googleNotConfigured: return "Google sign-in isn't set up yet."
        case .missingToken:        return "Sign-in didn't complete. Please try again."
        case .sessionExpired:      return "Your session has expired. Please sign in again."
        case .server(let message): return message
        }
    }
}

// MARK: - Auth Repository

/// Supabase Auth for the app. Sign-in uses native Apple / Google flows whose
/// ID tokens are exchanged for a Supabase session.
nonisolated protocol AuthRepository: Sendable {
    var isConfigured: Bool { get }

    func currentUser() -> AuthUser?
    /// Emits the signed-in user (or nil) on every auth change, starting with the stored session.
    func authChanges() -> AsyncStream<AuthUser?>

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUser
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthUser

    /// Saves the display name to the auth user and the profile row.
    func updateName(_ name: String) async throws
    func signOut() async
    /// Clears the session on this device only (no network call).
    func signOutLocally() async

    /// Checks the stored session at launch, refreshing it if it expired.
    func checkStoredSession() async -> StoredSessionCheck

    /// Deletes the account through the backend (files, Apple token, auth user,
    /// and every row that cascades from it), then clears the local session.
    func deleteAccount(appleAuthorizationCode: String?) async throws
}

// MARK: - Supabase Implementation

nonisolated final class SupabaseAuthRepository: AuthRepository {

    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    var isConfigured: Bool { client != nil }

    func currentUser() -> AuthUser? {
        client?.auth.currentSession.map { Self.makeUser($0.user) }
    }

    func authChanges() -> AsyncStream<AuthUser?> {
        guard let client else {
            return AsyncStream { continuation in
                continuation.yield(nil)
                continuation.finish()
            }
        }

        let changes = client.auth.authStateChanges

        return AsyncStream { continuation in
            let task = Task {
                for await change in changes {
                    continuation.yield(change.session.map { Self.makeUser($0.user) })
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUser {
        let client = try requireClient()
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return Self.makeUser(session.user)
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthUser {
        let client = try requireClient()
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken, accessToken: accessToken)
        )
        return Self.makeUser(session.user)
    }

    func updateName(_ name: String) async throws {
        let client = try requireClient()
        let user = try await client.auth.update(user: UserAttributes(data: ["full_name": .string(name)]))

        try await client
            .from("profiles")
            .update(["name": name])
            .eq("id", value: user.id)
            .execute()
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
        } catch {
            // Offline or already invalid on the server: still clear this device
            try? await client.auth.signOut(scope: .local)
        }
    }

    func signOutLocally() async {
        try? await client?.auth.signOut(scope: .local)
    }

    func checkStoredSession() async -> StoredSessionCheck {
        guard let client, let stored = client.auth.currentSession else { return .none }
        guard stored.isExpired else { return .valid }
        do {
            _ = try await client.auth.refreshSession()
            return .valid
        } catch is URLError {
            return .offline // keep the session; it refreshes once back online
        } catch is CancellationError {
            return .offline // gave up waiting: not a rejection
        } catch {
            if Task.isCancelled { return .offline }
            return .invalid // revoked, expired refresh token, or deleted user
        }
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        let client = try requireClient()

        let session: Session
        do {
            session = try await client.auth.session // refreshes if needed
        } catch {
            throw AuthFlowError.sessionExpired
        }

        guard let url = URL(string: APIConstants.deleteAccount) else {
            throw AuthFlowError.server("Could not delete your account. Please try again.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 60 // allow for a backend cold start
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let appleAuthorizationCode {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["apple_authorization_code": appleAuthorizationCode]
            )
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw JobAPIError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthFlowError.server("Could not delete your account. Please try again.")
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw AuthFlowError.sessionExpired }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw AuthFlowError.server(detail)
            }
            throw AuthFlowError.server("Could not delete your account. Please try again.")
        }

        // The server-side session is gone with the user; clear this device
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: Helpers

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw AuthFlowError.notConfigured }
        return client
    }

    private static func makeUser(_ user: User) -> AuthUser {
        let name = user.userMetadata["full_name"]?.stringValue ?? user.userMetadata["name"]?.stringValue
        return AuthUser(
            id: user.id,
            email: user.email,
            name: name?.isEmpty == false ? name : nil,
            provider: user.appMetadata["provider"]?.stringValue
        )
    }
}
