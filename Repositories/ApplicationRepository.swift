import Foundation
import Supabase

// MARK: - Application Repository

/// The signed-in user's tracked jobs and their status history.
/// Row Level Security limits every query to the user's own rows.
nonisolated protocol ApplicationRepository: Sendable {
    func fetchApplications() async throws -> [ApplicationRecord]
    func createApplication(_ application: NewApplication) async throws -> ApplicationRecord
    func updateApplication(id: UUID, changes: ApplicationChanges) async throws -> ApplicationRecord
    func deleteApplication(id: UUID) async throws

    /// Creates or updates the user's row for a job (unique per user and job),
    /// so retrying a sync never makes duplicates.
    func upsertApplication(_ application: ApplicationUpsert) async throws -> ApplicationRecord

    /// Removes the user's row for a job; succeeds if it's already gone.
    func deleteApplication(userId: UUID, jobId: UUID) async throws

    /// Asks the backend to add the job to the shared jobs table (the app has
    /// no write access to it). Only needed when an upsert fails because the
    /// job isn't there yet.
    func ensureJob(id: UUID, snapshot: JobSnapshot) async throws

    /// Status history, newest first (written by a database trigger).
    func fetchEvents(applicationId: UUID) async throws -> [ApplicationEventRecord]
}

// MARK: - Supabase Implementation

nonisolated final class SupabaseApplicationRepository: ApplicationRepository {

    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    func fetchApplications() async throws -> [ApplicationRecord] {
        let client = try requireClient()
        return try await client
            .from("applications")
            .select()
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func createApplication(_ application: NewApplication) async throws -> ApplicationRecord {
        let client = try requireClient()
        return try await client
            .from("applications")
            .insert(application)
            .select()
            .single()
            .execute()
            .value
    }

    func updateApplication(id: UUID, changes: ApplicationChanges) async throws -> ApplicationRecord {
        let client = try requireClient()
        return try await client
            .from("applications")
            .update(changes)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteApplication(id: UUID) async throws {
        let client = try requireClient()
        try await client
            .from("applications")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func upsertApplication(_ application: ApplicationUpsert) async throws -> ApplicationRecord {
        let client = try requireClient()
        return try await client
            .from("applications")
            .upsert(application, onConflict: "user_id,job_id")
            .select()
            .single()
            .execute()
            .value
    }

    func deleteApplication(userId: UUID, jobId: UUID) async throws {
        let client = try requireClient()
        try await client
            .from("applications")
            .delete()
            .eq("user_id", value: userId)
            .eq("job_id", value: jobId)
            .execute()
    }

    func ensureJob(id: UUID, snapshot: JobSnapshot) async throws {
        let client = try requireClient()

        let session: Session
        do {
            session = try await client.auth.session // refreshes if needed
        } catch {
            throw RepositoryError.notSignedIn
        }

        guard let url = URL(string: APIConstants.ensureJob) else {
            throw TrackerError.jobUnavailable
        }

        var body: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "title": snapshot.title,
            "company": snapshot.company,
            "location": snapshot.location,
            "description": snapshot.description,
            "applyURL": snapshot.applyURL
        ]
        if let postedAt = snapshot.postedAt {
            body["postedAt"] = ISO8601DateFormatter().string(from: postedAt)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // allow for a backend cold start
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw JobAPIError.from(error)
        }

        guard let http = response as? HTTPURLResponse else { throw TrackerError.jobUnavailable }

        switch http.statusCode {
        case 200...299: return
        case 400, 422:  throw TrackerError.jobUnavailable // id doesn't match our feed
        case 401:       throw RepositoryError.notSignedIn
        default:        throw TrackerError.serverBusy
        }
    }

    func fetchEvents(applicationId: UUID) async throws -> [ApplicationEventRecord] {
        let client = try requireClient()
        return try await client
            .from("application_events")
            .select()
            .eq("application_id", value: applicationId)
            .order("changed_at", ascending: false)
            .execute()
            .value
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw RepositoryError.notConfigured }
        return client
    }
}

// MARK: - Tracker Errors

nonisolated enum TrackerError: LocalizedError {
    /// The job can't be added to the shared table (it didn't come from our feed)
    case jobUnavailable
    case serverBusy

    var errorDescription: String? {
        switch self {
        case .jobUnavailable: return "This job can't be tracked."
        case .serverBusy:     return "Couldn't sync right now. Your changes are saved on this device."
        }
    }

    /// Postgres foreign key violation: applications.job_id isn't in jobs yet.
    static func isMissingJob(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == "23503"
    }
}
