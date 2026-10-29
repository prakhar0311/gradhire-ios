import Foundation
import SwiftData

// MARK: - Tracked Job (SwiftData offline cache)

/// Local copy of one row in Supabase `applications`, so the tracker loads
/// instantly and works offline. Changes are made here first and marked
/// pending; TrackerStore pushes them to Supabase and then pulls the server
/// rows back.
///
/// Every row belongs to one signed-in user (`ownerId`); the cache is cleared
/// on sign-out and only the current user's rows are ever read.
@Model
final class TrackedJob {

    /// "<ownerId>|<jobId>", one row per user and job (same as the server)
    @Attribute(.unique) var key: String

    var ownerId: UUID
    var jobId: UUID
    var applicationId: UUID?

    var statusRaw: String
    var notes: String
    var savedAt: Date
    var appliedAt: Date?
    var updatedAt: Date
    /// When the user last followed up (dashboard "Mark followed up")
    var followUpAt: Date?

    var syncRaw: String
    /// Bumped on every local edit, so a sync response never overwrites an
    /// edit made while it was in flight.
    var localRevision: Int

    // Job snapshot
    var title: String
    var company: String
    var location: String
    var applyURL: String
    var postedAt: Date?
    var contractTime: String?
    var matchScore: Int?
    var jobDescription: String

    init(ownerId: UUID, jobId: UUID, status: ApplicationStatus, snapshot: JobSnapshot) {
        self.key = Self.key(ownerId: ownerId, jobId: jobId)
        self.ownerId = ownerId
        self.jobId = jobId
        self.applicationId = nil
        self.statusRaw = status.rawValue
        self.notes = ""
        self.savedAt = Date()
        self.appliedAt = nil
        self.updatedAt = Date()
        self.syncRaw = SyncState.pendingUpsert.rawValue
        self.localRevision = 0
        self.title = snapshot.title
        self.company = snapshot.company
        self.location = snapshot.location
        self.applyURL = snapshot.applyURL
        self.postedAt = snapshot.postedAt
        self.contractTime = snapshot.contractTime
        self.matchScore = snapshot.matchScore
        self.jobDescription = snapshot.description
    }

    static func key(ownerId: UUID, jobId: UUID) -> String {
        "\(ownerId.uuidString.lowercased())|\(jobId.uuidString.lowercased())"
    }

    enum SyncState: String {
        case synced
        case pendingUpsert
        case pendingDelete
    }

    var status: ApplicationStatus {
        get { ApplicationStatus(rawValue: statusRaw) ?? .saved }
        set { statusRaw = newValue.rawValue }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncRaw) ?? .pendingUpsert }
        set { syncRaw = newValue.rawValue }
    }

    var snapshot: JobSnapshot {
        get {
            JobSnapshot(
                title: title, company: company, location: location, applyURL: applyURL,
                postedAt: postedAt, contractTime: contractTime, matchScore: matchScore,
                description: jobDescription
            )
        }
        set {
            title = newValue.title
            company = newValue.company
            location = newValue.location
            applyURL = newValue.applyURL
            postedAt = newValue.postedAt
            contractTime = newValue.contractTime
            matchScore = newValue.matchScore
            jobDescription = newValue.description
        }
    }

    /// Records a local edit that still has to reach Supabase.
    func touch() {
        updatedAt = Date()
        localRevision += 1
        if syncState != .pendingDelete { syncState = .pendingUpsert }
    }

    /// Takes the server's version of the row (only when nothing is pending).
    func apply(_ record: ApplicationRecord) {
        applicationId = record.id
        status = record.status
        notes = record.notes ?? ""
        savedAt = record.savedAt
        appliedAt = record.appliedAt
        updatedAt = record.updatedAt
        followUpAt = record.followUpAt
        // Keep the richer local snapshot if the server one is empty
        if !record.jobSnapshot.title.isEmpty { snapshot = record.jobSnapshot }
        syncState = .synced
    }
}

// MARK: - Tracked Application (value type for views)

struct TrackedApplication: Identifiable, Equatable {
    let jobId: UUID
    let applicationId: UUID?
    let status: ApplicationStatus
    let notes: String
    let savedAt: Date
    let appliedAt: Date?
    let updatedAt: Date
    let followUpAt: Date?
    let snapshot: JobSnapshot
    let isPendingSync: Bool

    var id: UUID { jobId }

    init(_ model: TrackedJob) {
        jobId = model.jobId
        applicationId = model.applicationId
        status = model.status
        notes = model.notes
        savedAt = model.savedAt
        appliedAt = model.appliedAt
        updatedAt = model.updatedAt
        followUpAt = model.followUpAt
        snapshot = model.snapshot
        isPendingSync = model.syncState != .synced
    }

    /// Applied at least `days` ago, still Applied, and not followed up in the
    /// last `days` days: time for a gentle follow-up (at most once a week).
    func isFollowUpDue(now: Date = Date(), days: Int = 7) -> Bool {
        guard status == .applied, let appliedAt else { return false }
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        guard appliedAt <= cutoff else { return false }
        if let followUpAt { return followUpAt <= cutoff }
        return true
    }

    /// The job as the rest of the app shows it (from the saved snapshot).
    var job: Job {
        Job(
            id: jobId,
            title: snapshot.title,
            company: snapshot.company,
            location: snapshot.location,
            description: snapshot.description,
            matchScore: snapshot.matchScore,
            applyURL: snapshot.applyURL,
            postedAt: snapshot.postedAt,
            contractTime: snapshot.contractTime
        )
    }
}

// MARK: - Job → Snapshot

extension Job {
    var snapshot: JobSnapshot {
        JobSnapshot(
            title: title, company: company, location: location, applyURL: applyURL,
            postedAt: postedAt, contractTime: contractTime, matchScore: matchScore,
            description: description
        )
    }
}

// MARK: - Status Helpers

extension ApplicationStatus {

    var title: String {
        switch self {
        case .saved:        return "Saved"
        case .applied:      return "Applied"
        case .interviewing: return "Interviewing"
        case .offer:        return "Offer"
        case .rejected:     return "Rejected"
        }
    }

    var icon: String {
        switch self {
        case .saved:        return "bookmark.fill"
        case .applied:      return "paperplane.fill"
        case .interviewing: return "person.2.fill"
        case .offer:        return "star.fill"
        case .rejected:     return "xmark.circle.fill"
        }
    }

    /// The usual next step, offered as the quick swipe action.
    var next: ApplicationStatus? {
        switch self {
        case .saved:        return .applied
        case .applied:      return .interviewing
        case .interviewing: return .offer
        case .offer, .rejected: return nil
        }
    }

    /// Statuses that mean the user already applied.
    var hasApplied: Bool {
        switch self {
        case .applied, .interviewing, .offer: return true
        case .saved, .rejected:               return false
        }
    }
}
