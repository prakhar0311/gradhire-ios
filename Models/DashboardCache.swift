import Foundation
import SwiftData

// MARK: - Dashboard Data

/// What the dashboard loads from Supabase. Cached per user (SwiftData), so
/// the dashboard shows instantly and offline, then refreshes.
struct DashboardServerData: Codable, Equatable {
    var resume: ResumeCardData?
    var tailoredCount = 0
    var matches: [DashboardMatch] = []
    var activity: [ActivityItem] = []
    var weeklyGoal: Int?
}

struct ResumeCardData: Codable, Equatable {
    let id: UUID
    let title: String
    let readinessScore: Int?
    let createdAt: Date
}

/// A matched job as the dashboard shows it (from the device or from Supabase).
struct DashboardMatch: Codable, Equatable, Identifiable {
    let jobId: UUID
    let title: String
    let company: String
    let location: String
    let description: String
    let applyURL: String
    let postedAt: Date?
    let score: Int
    let missingSkills: [String]

    var id: UUID { jobId }

    init(job: Job) {
        jobId = job.id
        title = job.title
        company = job.company
        location = job.location
        description = job.description
        applyURL = job.applyURL
        postedAt = job.postedAt
        score = job.matchScore ?? 0
        missingSkills = job.missingSkills ?? []
    }

    init?(record: DashboardMatchRecord) {
        guard let job = record.job else { return nil }
        jobId = job.id
        title = job.title
        company = job.company ?? ""
        location = job.location ?? ""
        description = job.description ?? ""
        applyURL = job.applyUrl ?? ""
        postedAt = job.postedAt
        score = record.matchScore
        missingSkills = record.missingSkills
    }

    var job: Job {
        Job(
            id: jobId, title: title, company: company, location: location,
            description: description, matchScore: score, applyURL: applyURL,
            postedAt: postedAt, contractTime: nil, missingSkills: missingSkills
        )
    }
}

/// One line in "Recent activity".
struct ActivityItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case status
        case tailored
    }

    let id: String
    let kind: Kind
    let date: Date
    let title: String
    let detail: String
    let status: ApplicationStatus?
    let jobId: UUID?
}

// MARK: - Dashboard Cache (SwiftData)

@Model
final class DashboardCache {

    @Attribute(.unique) var ownerId: UUID
    var payload: Data
    var updatedAt: Date

    init(ownerId: UUID, payload: Data) {
        self.ownerId = ownerId
        self.payload = payload
        self.updatedAt = Date()
    }
}
