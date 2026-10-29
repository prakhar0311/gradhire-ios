import Foundation
import Supabase

// MARK: - Dashboard Records

/// A resume row without its (large) parsed text.
nonisolated struct ResumeSummaryRecord: Decodable, Sendable {
    let id: UUID
    let kind: ResumeKind
    let parentResumeId: UUID?
    let title: String?
    let readinessScore: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case parentResumeId = "parent_resume_id"
        case readinessScore = "readiness_score"
        case createdAt = "created_at"
    }
}

/// One stored match with its job (job_matches → jobs).
nonisolated struct DashboardMatchRecord: Decodable, Sendable {
    let matchScore: Int
    let missingSkills: [String]
    let job: MatchedJobRecord?

    enum CodingKeys: String, CodingKey {
        case matchScore = "match_score"
        case missingSkills = "missing_skills"
        case job = "jobs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchScore = try container.decode(Int.self, forKey: .matchScore)
        missingSkills = (try? container.decode([String].self, forKey: .missingSkills)) ?? []
        job = try container.decodeIfPresent(MatchedJobRecord.self, forKey: .job)
    }
}

nonisolated struct MatchedJobRecord: Decodable, Sendable {
    let id: UUID
    let title: String
    let company: String?
    let location: String?
    let description: String?
    let applyUrl: String?
    let postedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, company, location, description
        case applyUrl = "apply_url"
        case postedAt = "posted_at"
    }
}

/// A status change with the tracked job's snapshot (application_events → applications).
nonisolated struct ActivityEventRecord: Decodable, Sendable {
    let id: UUID
    let fromStatus: ApplicationStatus?
    let toStatus: ApplicationStatus
    let changedAt: Date
    let application: ActivityApplicationRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case fromStatus = "from_status"
        case toStatus = "to_status"
        case changedAt = "changed_at"
        case application = "applications"
    }
}

nonisolated struct ActivityApplicationRecord: Decodable, Sendable {
    let jobId: UUID
    let jobSnapshot: JobSnapshot

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobSnapshot = "job_snapshot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(UUID.self, forKey: .jobId)
        jobSnapshot = (try? container.decode(JobSnapshot.self, forKey: .jobSnapshot)) ?? JobSnapshot()
    }
}

// MARK: - Dashboard Repository

/// Reads for the dashboard. Each call is one small request, so sections load
/// (and fail) independently. Row Level Security limits everything to the user.
nonisolated protocol DashboardRepository: Sendable {
    func fetchWeeklyGoal(userId: UUID) async throws -> Int?
    func updateWeeklyGoal(_ goal: Int?, userId: UUID) async throws

    /// Newest first, without parsed text.
    func fetchResumeSummaries() async throws -> [ResumeSummaryRecord]
    /// The latest stored matches for a resume, best first, with their jobs.
    func fetchMatches(resumeId: UUID) async throws -> [DashboardMatchRecord]
    /// Newest status changes across the user's tracked jobs.
    func fetchRecentEvents(limit: Int) async throws -> [ActivityEventRecord]
}

// MARK: - Supabase Implementation

nonisolated final class SupabaseDashboardRepository: DashboardRepository {

    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    private struct GoalRow: Codable {
        let weeklyGoal: Int?

        enum CodingKeys: String, CodingKey {
            case weeklyGoal = "weekly_goal"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(weeklyGoal, forKey: .weeklyGoal) // explicit null turns it off
        }
    }

    func fetchWeeklyGoal(userId: UUID) async throws -> Int? {
        let client = try requireClient()
        let rows: [GoalRow] = try await client
            .from("profiles")
            .select("weekly_goal")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first?.weeklyGoal
    }

    func updateWeeklyGoal(_ goal: Int?, userId: UUID) async throws {
        let client = try requireClient()
        try await client
            .from("profiles")
            .update(GoalRow(weeklyGoal: goal))
            .eq("id", value: userId)
            .execute()
    }

    func fetchResumeSummaries() async throws -> [ResumeSummaryRecord] {
        let client = try requireClient()
        return try await client
            .from("resumes")
            .select("id,kind,parent_resume_id,title,readiness_score,created_at")
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    func fetchMatches(resumeId: UUID) async throws -> [DashboardMatchRecord] {
        let client = try requireClient()
        return try await client
            .from("job_matches")
            .select("match_score,missing_skills,jobs(id,title,company,location,description,apply_url,posted_at)")
            .eq("resume_id", value: resumeId)
            .order("match_score", ascending: false)
            .limit(50)
            .execute()
            .value
    }

    func fetchRecentEvents(limit: Int) async throws -> [ActivityEventRecord] {
        let client = try requireClient()
        return try await client
            .from("application_events")
            .select("id,from_status,to_status,changed_at,applications(job_id,job_snapshot)")
            .order("changed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw RepositoryError.notConfigured }
        return client
    }
}
