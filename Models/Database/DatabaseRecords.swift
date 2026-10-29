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

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case userId = "user_id"
        case jobId = "job_id"
        case resumeId = "resume_id"
        case savedAt = "saved_at"
        case appliedAt = "applied_at"
        case updatedAt = "updated_at"
        case followUpAt = "follow_up_at"
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
