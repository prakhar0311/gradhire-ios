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
