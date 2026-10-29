import Foundation
import Supabase

// Rows of the Supabase tables defined in gradhire-backend/supabase/migrations.
// Column names are snake_case in Postgres, so every type maps them explicitly.
//
// These types are `nonisolated` so the Supabase client can decode and encode
// them off the main actor (the app target defaults to MainActor isolation).

// MARK: - Enums (match the Postgres enum types)

nonisolated enum ResumeKind: String, Codable, Sendable, CaseIterable {
    case original
    case optimized
    case tailored
}

nonisolated enum ApplicationStatus: String, Codable, Sendable, CaseIterable {
    case saved
    case applied
    case interviewing
    case offer
    case rejected
}

// MARK: - profiles

nonisolated struct ProfileRecord: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String?
    var email: String?
    var notifyNewJobs: Bool
    var notifyFollowups: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case notifyNewJobs = "notify_new_jobs"
        case notifyFollowups = "notify_followups"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - jobs (read-only in the app; written by the backend)

nonisolated struct JobRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let source: String
    let externalId: String
    let title: String
    let company: String?
    let location: String?
    let salaryMin: Double?
    let salaryMax: Double?
    let description: String?
    let applyUrl: String?
    let postedAt: Date?
    let isNewGrad: Bool
    let firstSeenAt: Date
    let lastSeenAt: Date
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, source, title, company, location, description
        case externalId = "external_id"
        case salaryMin = "salary_min"
        case salaryMax = "salary_max"
        case applyUrl = "apply_url"
        case postedAt = "posted_at"
        case isNewGrad = "is_new_grad"
        case firstSeenAt = "first_seen_at"
        case lastSeenAt = "last_seen_at"
        case isActive = "is_active"
    }
}

// MARK: - resumes

nonisolated struct ResumeRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let kind: ResumeKind
    let parentResumeId: UUID?
    let targetJobId: UUID?
    var title: String?
    var parsedData: AnyJSON?
    var filePath: String?
    var readinessScore: Int?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case userId = "user_id"
        case parentResumeId = "parent_resume_id"
        case targetJobId = "target_job_id"
        case parsedData = "parsed_data"
        case filePath = "file_path"
        case readinessScore = "readiness_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Insert payload; user_id is filled in by the database (auth.uid()).
nonisolated struct NewResume: Encodable, Sendable {
    let kind: ResumeKind
    var parentResumeId: UUID?
    var targetJobId: UUID?
    var title: String?
    var parsedData: AnyJSON?
    var filePath: String?

    enum CodingKeys: String, CodingKey {
        case kind, title
        case parentResumeId = "parent_resume_id"
        case targetJobId = "target_job_id"
        case parsedData = "parsed_data"
        case filePath = "file_path"
    }
}

// MARK: - job_matches (read-only in the app; written by the backend)

nonisolated struct JobMatchRecord: Codable, Sendable {
    let resumeId: UUID
    let jobId: UUID
    let matchScore: Int
    let matchedSkills: [String]
    let missingSkills: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case resumeId = "resume_id"
        case jobId = "job_id"
        case matchScore = "match_score"
        case matchedSkills = "matched_skills"
        case missingSkills = "missing_skills"
        case createdAt = "created_at"
    }
}

// MARK: - applications

nonisolated struct ApplicationRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let jobId: UUID
    var status: ApplicationStatus
    var resumeId: UUID?
    var notes: String?
    let savedAt: Date
    var appliedAt: Date?
    let updatedAt: Date
    var followUpAt: Date?
    var jobSnapshot: JobSnapshot

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case userId = "user_id"
        case jobId = "job_id"
        case resumeId = "resume_id"
        case savedAt = "saved_at"
        case appliedAt = "applied_at"
        case updatedAt = "updated_at"
        case followUpAt = "follow_up_at"
        case jobSnapshot = "job_snapshot"
    }
}

extension ApplicationRecord {

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        jobId = try container.decode(UUID.self, forKey: .jobId)
        status = try container.decode(ApplicationStatus.self, forKey: .status)
        resumeId = try container.decodeIfPresent(UUID.self, forKey: .resumeId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        appliedAt = try container.decodeIfPresent(Date.self, forKey: .appliedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        followUpAt = try container.decodeIfPresent(Date.self, forKey: .followUpAt)
        // A malformed snapshot must not hide the application
        jobSnapshot = (try? container.decodeIfPresent(JobSnapshot.self, forKey: .jobSnapshot)) ?? JobSnapshot()
    }
}

/// The key job fields saved with an application, so a tracked job still
/// displays after it closes or disappears from Adzuna.
nonisolated struct JobSnapshot: Codable, Sendable, Equatable {
    var title: String = ""
    var company: String = ""
    var location: String = ""
    var applyURL: String = ""
    var postedAt: Date?
    var contractTime: String?
    var matchScore: Int?
    var description: String = ""

    /// The description is shortened to keep the row small.
    static let descriptionLimit = 4000

    enum CodingKeys: String, CodingKey {
        case title, company, location, description
        case applyURL = "apply_url"
        case postedAt = "posted_at"
        case contractTime = "contract_time"
        case matchScore = "match_score"
    }

    init() {}

    init(
        title: String, company: String, location: String, applyURL: String,
        postedAt: Date?, contractTime: String?, matchScore: Int?, description: String
    ) {
        self.title = title
        self.company = company
        self.location = location
        self.applyURL = applyURL
        self.postedAt = postedAt
        self.contractTime = contractTime
        self.matchScore = matchScore
        self.description = String(description.prefix(Self.descriptionLimit))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        company = (try? container.decodeIfPresent(String.self, forKey: .company)) ?? ""
        location = (try? container.decodeIfPresent(String.self, forKey: .location)) ?? ""
        applyURL = (try? container.decodeIfPresent(String.self, forKey: .applyURL)) ?? ""
        postedAt = try? container.decodeIfPresent(Date.self, forKey: .postedAt)
        contractTime = try? container.decodeIfPresent(String.self, forKey: .contractTime)
        matchScore = try? container.decodeIfPresent(Int.self, forKey: .matchScore)
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? ""
    }
}

/// Insert-or-update payload for a tracked job (one row per user and job).
/// follow_up_at and resume_id are left out, so a sync never clears them.
nonisolated struct ApplicationUpsert: Encodable, Sendable {
    let userId: UUID
    let jobId: UUID
    let status: ApplicationStatus
    let notes: String?
    let savedAt: Date
    let appliedAt: Date?
    let jobSnapshot: JobSnapshot

    enum CodingKeys: String, CodingKey {
        case status, notes
        case userId = "user_id"
        case jobId = "job_id"
        case savedAt = "saved_at"
        case appliedAt = "applied_at"
        case jobSnapshot = "job_snapshot"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(status, forKey: .status)
        // Explicit nulls, so clearing notes or moving back to Saved syncs too
        try container.encode(notes, forKey: .notes)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(appliedAt, forKey: .appliedAt)
        try container.encode(jobSnapshot, forKey: .jobSnapshot)
    }
}

/// Insert payload; user_id is filled in by the database (auth.uid()).
nonisolated struct NewApplication: Encodable, Sendable {
    let jobId: UUID
    var status: ApplicationStatus = .saved
    var resumeId: UUID?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case status, notes
        case jobId = "job_id"
        case resumeId = "resume_id"
    }
}

/// Partial update payload; nil fields are left out of the request.
nonisolated struct ApplicationChanges: Encodable, Sendable {
    var status: ApplicationStatus?
    var notes: String?
    var appliedAt: Date?
    var followUpAt: Date?

    enum CodingKeys: String, CodingKey {
        case status, notes
        case appliedAt = "applied_at"
        case followUpAt = "follow_up_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(appliedAt, forKey: .appliedAt)
        try container.encodeIfPresent(followUpAt, forKey: .followUpAt)
    }
}

// MARK: - application_events (read-only; written by a database trigger)

nonisolated struct ApplicationEventRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let applicationId: UUID
    let fromStatus: ApplicationStatus?
    let toStatus: ApplicationStatus
    let changedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case applicationId = "application_id"
        case fromStatus = "from_status"
        case toStatus = "to_status"
        case changedAt = "changed_at"
    }
}

// MARK: - device_tokens

nonisolated struct DeviceTokenRecord: Codable, Sendable {
    let userId: UUID
    let apnsToken: String
    let environment: String // "sandbox" or "production"
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case environment
        case userId = "user_id"
        case apnsToken = "apns_token"
        case updatedAt = "updated_at"
    }
}
