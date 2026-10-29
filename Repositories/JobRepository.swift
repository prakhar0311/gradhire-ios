import Foundation
import Supabase

// MARK: - Job Repository

/// Shared job rows (written by the backend, readable by everyone).
nonisolated protocol JobRepository: Sendable {
    func fetchJob(id: UUID) async throws -> JobRecord?
    func fetchJobs(ids: [UUID]) async throws -> [JobRecord]
    func fetchNewGradJobs(limit: Int, offset: Int) async throws -> [JobRecord]
}

// MARK: - Supabase Implementation

nonisolated final class SupabaseJobRepository: JobRepository {

    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    func fetchJob(id: UUID) async throws -> JobRecord? {
        let client = try requireClient()
        let rows: [JobRecord] = try await client
            .from("jobs")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func fetchJobs(ids: [UUID]) async throws -> [JobRecord] {
        guard !ids.isEmpty else { return [] }
        let client = try requireClient()
        return try await client
            .from("jobs")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    func fetchNewGradJobs(limit: Int, offset: Int) async throws -> [JobRecord] {
        let client = try requireClient()
        return try await client
            .from("jobs")
            .select()
            .eq("is_new_grad", value: true)
            .eq("is_active", value: true)
            .order("posted_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw RepositoryError.notConfigured }
        return client
    }
}
