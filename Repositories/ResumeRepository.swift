import Foundation
import Supabase

// MARK: - Resume Repository

/// The signed-in user's resumes, their files in the private "resumes" bucket,
/// and their job matches. Row Level Security limits everything to the user.
nonisolated protocol ResumeRepository: Sendable {
    func fetchResumes() async throws -> [ResumeRecord]
    /// Every saved resume, newest first, without the (large) parsed text.
    func fetchResumeList() async throws -> [SavedResumeRecord]
    /// The saved text of one resume (parsed_data.text), if any.
    func fetchResumeText(id: UUID) async throws -> String?
    func createResume(_ resume: NewResume) async throws -> ResumeRecord
    func renameResume(id: UUID, title: String) async throws
    func deleteResume(id: UUID) async throws

    func fetchActiveResumeId(userId: UUID) async throws -> UUID?
    func setActiveResumeId(_ id: UUID?, userId: UUID) async throws
    func fetchLimits() async throws -> ResumeLimits

    /// Uploads a PDF to resumes/{user_id}/{fileName} and returns its storage path.
    func uploadResumeFile(_ data: Data, fileName: String) async throws -> String
    func signedURL(forPath path: String, expiresIn seconds: Int) async throws -> URL
    /// Downloads a file through a short-lived signed URL (the bucket is private).
    func downloadResumeFile(atPath path: String) async throws -> Data
    func deleteResumeFile(atPath path: String) async throws

    func fetchMatches(resumeId: UUID) async throws -> [JobMatchRecord]
    /// Stored matches with their jobs, best first (for the For You tab).
    func fetchStoredMatches(resumeId: UUID) async throws -> [StoredMatchRecord]
}

// MARK: - Records

/// A resume row without its parsed text.
nonisolated struct SavedResumeRecord: Decodable, Sendable {
    let id: UUID
    let kind: ResumeKind
    let parentResumeId: UUID?
    let title: String?
    let filePath: String?
    let readinessScore: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case parentResumeId = "parent_resume_id"
        case filePath = "file_path"
        case readinessScore = "readiness_score"
        case createdAt = "created_at"
    }
}

/// How many resumes a user may save (public.resume_limits).
nonisolated struct ResumeLimits: Codable, Sendable, Equatable {
    var maxOriginals: Int
    var maxVersions: Int

    /// Used until the server's values load (same as the database default).
    static let standard = ResumeLimits(maxOriginals: 3, maxVersions: 10)

    enum CodingKeys: String, CodingKey {
        case maxOriginals = "max_originals"
        case maxVersions = "max_versions"
    }
}

/// One stored match with its matched/missing skills and job.
nonisolated struct StoredMatchRecord: Decodable, Sendable {
    let matchScore: Int
    let matchedSkills: [String]
    let missingSkills: [String]
    let job: MatchedJobRecord?

    enum CodingKeys: String, CodingKey {
        case matchScore = "match_score"
        case matchedSkills = "matched_skills"
        case missingSkills = "missing_skills"
        case job = "jobs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchScore = try container.decode(Int.self, forKey: .matchScore)
        matchedSkills = (try? container.decode([String].self, forKey: .matchedSkills)) ?? []
        missingSkills = (try? container.decode([String].self, forKey: .missingSkills)) ?? []
        job = try container.decodeIfPresent(MatchedJobRecord.self, forKey: .job)
    }

    var asJob: Job? {
        guard let job else { return nil }
        return Job(
            id: job.id, title: job.title, company: job.company ?? "", location: job.location ?? "",
            description: job.description ?? "", matchScore: matchScore, applyURL: job.applyUrl ?? "",
            postedAt: job.postedAt, contractTime: nil,
            matchedSkills: matchedSkills, missingSkills: missingSkills
        )
    }
}

// MARK: - Errors

nonisolated enum ResumeSaveError: LocalizedError, Equatable {
    /// The database refused: too many original resumes
    case originalLimit
    /// The database refused: too many tailored/optimized versions
    case versionLimit

    var errorDescription: String? {
        switch self {
        case .originalLimit: return "You've reached the limit for saved resumes."
        case .versionLimit:  return "You've reached the limit for tailored versions."
        }
    }

    /// Maps the limit trigger's error (RESUME_LIMIT_*) to a friendly case.
    static func from(_ error: Error) -> ResumeSaveError? {
        let text = (error as? PostgrestError)?.message ?? error.localizedDescription
        if text.contains("RESUME_LIMIT_ORIGINAL") { return .originalLimit }
        if text.contains("RESUME_LIMIT_VERSION") { return .versionLimit }
        return nil
    }
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

    func fetchResumeList() async throws -> [SavedResumeRecord] {
        let client = try requireClient()
        return try await client
            .from("resumes")
            .select("id,kind,parent_resume_id,title,file_path,readiness_score,created_at")
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    private struct TextRow: Decodable {
        let parsedData: AnyJSON?

        enum CodingKeys: String, CodingKey {
            case parsedData = "parsed_data"
        }
    }

    func fetchResumeText(id: UUID) async throws -> String? {
        let client = try requireClient()
        let rows: [TextRow] = try await client
            .from("resumes")
            .select("parsed_data")
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        guard case .object(let object)? = rows.first?.parsedData,
              case .string(let text)? = object["text"] else { return nil }
        return text
    }

    private struct TitleRow: Encodable {
        let title: String
    }

    func renameResume(id: UUID, title: String) async throws {
        let client = try requireClient()
        try await client
            .from("resumes")
            .update(TitleRow(title: title))
            .eq("id", value: id)
            .execute()
    }

    private struct ActiveRow: Codable {
        let activeResumeId: UUID?

        enum CodingKeys: String, CodingKey {
            case activeResumeId = "active_resume_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(activeResumeId, forKey: .activeResumeId) // explicit null clears it
        }
    }

    func fetchActiveResumeId(userId: UUID) async throws -> UUID? {
        let client = try requireClient()
        let rows: [ActiveRow] = try await client
            .from("profiles")
            .select("active_resume_id")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first?.activeResumeId
    }

    func setActiveResumeId(_ id: UUID?, userId: UUID) async throws {
        let client = try requireClient()
        try await client
            .from("profiles")
            .update(ActiveRow(activeResumeId: id))
            .eq("id", value: userId)
            .execute()
    }

    func fetchLimits() async throws -> ResumeLimits {
        let client = try requireClient()
        let rows: [ResumeLimits] = try await client
            .from("resume_limits")
            .select("max_originals,max_versions")
            .eq("plan", value: "free")
            .limit(1)
            .execute()
            .value
        return rows.first ?? .standard
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

    func downloadResumeFile(atPath path: String) async throws -> Data {
        let url = try await signedURL(forPath: path, expiresIn: 60)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
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

    func fetchStoredMatches(resumeId: UUID) async throws -> [StoredMatchRecord] {
        let client = try requireClient()
        return try await client
            .from("job_matches")
            .select("match_score,matched_skills,missing_skills,jobs(id,title,company,location,description,apply_url,posted_at)")
            .eq("resume_id", value: resumeId)
            .order("match_score", ascending: false)
            .limit(60)
            .execute()
            .value
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw RepositoryError.notConfigured }
        return client
    }
}
