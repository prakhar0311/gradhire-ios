import Foundation
import Combine
import Supabase

// MARK: - Supabase Manager

/// Owns the app's single Supabase client and the repositories built on it.
/// Created once in GradHireApp and injected; nothing else creates a client.
///
/// Configuration comes from Info.plist (filled from Config/Secrets.xcconfig).
/// Only the PUBLISHABLE (anon) key may be used here; the secret/service_role
/// key belongs on the backend only.
final class SupabaseManager: ObservableObject {

    nonisolated let client: SupabaseClient?

    let auth: any AuthRepository
    let jobs: any JobRepository
    let resumes: any ResumeRepository
    let applications: any ApplicationRepository

    var isConfigured: Bool { client != nil }

    init(bundle: Bundle = .main) {
        let client = Self.makeClient(bundle: bundle)
        self.client = client
        self.auth = SupabaseAuthRepository(client: client)
        self.jobs = SupabaseJobRepository(client: client)
        self.resumes = SupabaseResumeRepository(client: client)
        self.applications = SupabaseApplicationRepository(client: client)
    }

    // MARK: Configuration

    private static func makeClient(bundle: Bundle) -> SupabaseClient? {
        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
            let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
            url.scheme == "https",
            url.host?.isEmpty == false
        else { return nil }

        let trimmedKey = key.trimmingCharacters(in: .whitespaces)

        // Unfilled placeholder or empty value: treat as "not configured"
        guard !trimmedKey.isEmpty,
              !trimmedKey.hasPrefix("your-"),
              !trimmedKey.contains("$(") else { return nil }

        // Refuse a secret key outright; it would bypass Row Level Security
        guard !isSecretKey(trimmedKey) else {
            assertionFailure("Secrets.xcconfig contains a Supabase SECRET key. Use the publishable key in the app.")
            return nil
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: trimmedKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    /// True for new-format secret keys and legacy service_role JWTs.
    private static func isSecretKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return true }

        // Legacy keys are JWTs; the payload's "role" says anon or service_role
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let role = json["role"] as? String else { return false }

        return role == "service_role"
    }

    // MARK: Debug Connection Check

    /// Debug builds only: confirms the app can reach Supabase by reading one
    /// row from jobs (readable by guests). Never shown to users.
    func logConnectionCheck() async {
        #if DEBUG
        guard let client else {
            print("Supabase: not configured (fill in Config/Secrets.xcconfig)")
            return
        }

        do {
            try await client.from("jobs").select("id").limit(1).execute()
            print("Supabase: reachable (jobs table readable with the publishable key)")
        } catch {
            print("Supabase: connection check failed: \(error.localizedDescription)")
        }
        #endif
    }
}

// MARK: - Repository Errors

nonisolated enum RepositoryError: LocalizedError {
    case notConfigured
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cloud sync isn't set up yet."
        case .notSignedIn:   return "Please sign in to continue."
        }
    }
}
