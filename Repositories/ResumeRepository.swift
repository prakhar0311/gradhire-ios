import Foundation
import Supabase

// MARK: - Resume Repository

/// The signed-in user's resumes, their files in the private "resumes" bucket,
/// and their job matches. Row Level Security limits everything to the user.
nonisolated protocol ResumeRepository: Sendable {
    func fetchResumes() async throws -> [ResumeRecord]
    func createResume(_ resume: NewResume) async throws -> ResumeRecord
    func deleteResume(id: UUID) async throws

    /// Uploads a PDF to resumes/{user_id}/{fileName} and returns its storage path.
    func uploadResumeFile(_ data: Data, fileName: String) async throws -> String
    func signedURL(forPath path: String, expiresIn seconds: Int) async throws -> URL
    func deleteResumeFile(atPath path: String) async throws

    func fetchMatches(resumeId: UUID) async throws -> [JobMatchRecord]
}

// MARK: - Supabase Implementation

nonisolated final class SupabaseResumeRepository: ResumeRepository {

    private static let bucket = "resumes"

    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    func fetchResumes() async throws -> [ResumeRecord] {
        let client = try requireClient()
        return try await client
            .from("resumes")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createResume(_ resume: NewResume) async throws -> ResumeRecord {
        let client = try requireClient()
        return try await client
            .from("resumes")
            .insert(resume)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteResume(id: UUID) async throws {
        let client = try requireClient()
        try await client
            .from("resumes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func uploadResumeFile(_ data: Data, fileName: String) async throws -> String {
        let client = try requireClient()
        guard let userId = client.auth.currentUser?.id else { throw RepositoryError.notSignedIn }

        // Storage policies compare the first folder with auth.uid()::text,
        // which is lowercase; UUID.uuidString is uppercase.
        let path = "\(userId.uuidString.lowercased())/\(fileName)"

        try await client.storage
            .from(Self.bucket)
            .upload(path, data: data, options: FileOptions(contentType: "application/pdf", upsert: true))

        return path
    }

    func signedURL(forPath path: String, expiresIn seconds: Int) async throws -> URL {
        let client = try requireClient()
        return try await client.storage
            .from(Self.bucket)
            .createSignedURL(path: path, expiresIn: seconds)
    }

    func deleteResumeFile(atPath path: String) async throws {
        let client = try requireClient()
        _ = try await client.storage
            .from(Self.bucket)
            .remove(paths: [path])
    }

    func fetchMatches(resumeId: UUID) async throws -> [JobMatchRecord] {
        let client = try requireClient()
        return try await client
            .from("job_matches")
            .select()
            .eq("resume_id", value: resumeId)
            .order("match_score", ascending: false)
            .execute()
            .value
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw RepositoryError.notConfigured }
        return client
    }
}
