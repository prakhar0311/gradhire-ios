import Foundation
import Combine
import SwiftData

// MARK: - Dashboard View Model

/// Server-backed dashboard sections for the signed-in user: resume card,
/// stored matches, recent activity and the weekly goal. Each loads (and
/// fails) on its own; the last good data is cached per user and shown first.
///
/// Pipeline, this week and follow-ups come straight from the tracker cache,
/// and matches on this device come from MatchedJobsViewModel; the view
/// combines them.
final class DashboardViewModel: ObservableObject {

    enum SectionStatus: Equatable {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var data = DashboardServerData()
    @Published private(set) var resumeStatus: SectionStatus = .loading
    @Published private(set) var matchesStatus: SectionStatus = .loading
    @Published private(set) var activityStatus: SectionStatus = .loading
    @Published private(set) var goalStatus: SectionStatus = .loading
    /// True once cached or fresh data has been shown for this user.
    @Published private(set) var hasData = false

    private let repository: any DashboardRepository
    private let context: ModelContext
    private var userId: UUID?
    private var refreshTask: Task<Void, Never>?
    private var sinceDates: [String: Date] = [:]

    static let activityLimit = 5

    init(repository: any DashboardRepository) {
        self.repository = repository
        self.context = ModelContext(LocalStore.container)
    }

    // MARK: Account Changes

    func authChanged(_ state: AuthViewModel.State) {
        switch state {
        case .loading:
            break
        case .signedOut:
            refreshTask?.cancel()
            userId = nil
            data = DashboardServerData()
            hasData = false
            setAll(.loading)
            try? context.delete(model: DashboardCache.self)
            try? context.save()
        case .signedIn(let user):
            guard user.id != userId else { return }
            userId = user.id
            setAll(.loading)
            let owner = user.id
            try? context.delete(model: DashboardCache.self, where: #Predicate { $0.ownerId != owner })
            loadCache(for: user.id)
        }
    }

    // MARK: Refresh

    /// Refreshes every section in parallel. `accountResumeId` is the resume on
    /// this device that's saved to the account (if any); without it the
    /// newest saved resume is used.
    func refresh(accountResumeId: UUID?) async {
        guard let owner = userId else { return }

        async let goalTask: Void = refreshGoal(owner)
        async let activityTask: Void = refreshActivity(owner)
        async let resumeTask: UUID? = refreshResume(owner, preferred: accountResumeId)

        let resumeId = await resumeTask
        await refreshMatches(owner, resumeId: resumeId ?? accountResumeId)
        _ = await (goalTask, activityTask)

        guard userId == owner else { return }
        saveCache(for: owner)
    }

    func scheduleRefresh(accountResumeId: UUID?) {
        refreshTask?.cancel()
        refreshTask = Task { await refresh(accountResumeId: accountResumeId) }
    }

    /// Returns the resume whose matches the dashboard should show.
    private func refreshResume(_ owner: UUID, preferred: UUID?) async -> UUID? {
        if !hasData { resumeStatus = .loading }
        do {
            let resumes = try await repository.fetchResumeSummaries()
            guard userId == owner else { return nil }

            let originals = resumes.filter { $0.kind == .original }
            let current = originals.first { $0.id == preferred } ?? originals.first

            if let current {
                data.resume = ResumeCardData(
                    id: current.id,
                    title: current.title ?? "My resume",
                    readinessScore: current.readinessScore,
                    createdAt: current.createdAt
                )
                data.tailoredCount = resumes.filter { $0.kind == .tailored && $0.parentResumeId == current.id }.count
            } else {
                data.resume = nil
                data.tailoredCount = 0
            }

            // Tailored resumes also appear in recent activity
            tailoredActivity = resumes
                .filter { $0.kind == .tailored }
                .prefix(Self.activityLimit)
                .map { resume in
                    ActivityItem(
                        id: "resume-\(resume.id.uuidString)",
                        kind: .tailored,
                        date: resume.createdAt,
                        title: resume.title ?? "Tailored resume",
                        detail: resume.readinessScore.map { "Match score \($0)" } ?? "Tailored resume",
                        status: nil,
                        jobId: nil
                    )
                }
            mergeActivity()

            resumeStatus = .loaded
            hasData = true
            return current?.id
        } catch {
            guard userId == owner else { return nil }
            resumeStatus = .failed
            return nil
        }
    }

    private func refreshMatches(_ owner: UUID, resumeId: UUID?) async {
        if !hasData { matchesStatus = .loading }
        guard let resumeId else {
            data.matches = []
            matchesStatus = resumeStatus == .failed ? .failed : .loaded
            return
        }
        do {
            let records = try await repository.fetchMatches(resumeId: resumeId)
            guard userId == owner else { return }
            data.matches = records.compactMap(DashboardMatch.init(record:))
            matchesStatus = .loaded
        } catch {
            guard userId == owner else { return }
            matchesStatus = .failed
        }
    }

    private var statusActivity: [ActivityItem] = []
    private var tailoredActivity: [ActivityItem] = []

    private func refreshActivity(_ owner: UUID) async {
        if !hasData { activityStatus = .loading }
        do {
            let events = try await repository.fetchRecentEvents(limit: Self.activityLimit)
            guard userId == owner else { return }
            statusActivity = events.map(Self.activityItem)
            mergeActivity()
            activityStatus = .loaded
        } catch {
            guard userId == owner else { return }
            activityStatus = .failed
        }
    }

    private func mergeActivity() {
        data.activity = Array(
            (statusActivity + tailoredActivity)
                .sorted { $0.date > $1.date }
                .prefix(Self.activityLimit)
        )
    }

    private static func activityItem(_ event: ActivityEventRecord) -> ActivityItem {
        let snapshot = event.application?.jobSnapshot ?? JobSnapshot()
        let job = snapshot.title.isEmpty ? "a job" : snapshot.title

        let title: String
        switch (event.fromStatus, event.toStatus) {
        case (nil, .saved):       title = "Saved \(job)"
        case (_, .applied):       title = "Applied to \(job)"
        case (_, .interviewing):  title = "Interviewing for \(job)"
        case (_, .offer):         title = "Got an offer for \(job)"
        case (_, .rejected):      title = "\(job): not selected"
        case (_, .saved):         title = "Moved \(job) back to Saved"
        }

        return ActivityItem(
            id: "event-\(event.id.uuidString)",
            kind: .status,
            date: event.changedAt,
            title: title,
            detail: snapshot.company,
            status: event.toStatus,
            jobId: event.application?.jobId
        )
    }

    // MARK: Weekly Goal

    private func refreshGoal(_ owner: UUID) async {
        if !hasData { goalStatus = .loading }
        do {
            let goal = try await repository.fetchWeeklyGoal(userId: owner)
            guard userId == owner else { return }
            data.weeklyGoal = goal
            goalStatus = .loaded
        } catch {
            guard userId == owner else { return }
            goalStatus = .failed
        }
    }

    /// nil turns the goal off. Shown immediately; reverted if saving fails.
    func setWeeklyGoal(_ goal: Int?) async -> Bool {
        guard let owner = userId else { return false }
        let previous = data.weeklyGoal
        data.weeklyGoal = goal.map { min(max($0, 1), 50) }
        do {
            try await repository.updateWeeklyGoal(data.weeklyGoal, userId: owner)
            saveCache(for: owner)
            return true
        } catch {
            guard userId == owner else { return false }
            data.weeklyGoal = previous
            return false
        }
    }

    func retryGoal() {
        guard let owner = userId else { return }
        Task { await refreshGoal(owner) }
    }

    // MARK: Last Visit

    /// The start of "new since your last visit", fixed for this app session.
    /// Calling this records now as the latest visit for next time.
    func sinceLastVisit(for key: String) -> Date {
        if let date = sinceDates[key] { return date }
        let storageKey = "dashboard_last_visit_v1_\(key)"
        let stored = UserDefaults.standard.object(forKey: storageKey) as? Date
        // First visit: treat the last week as new
        let since = stored ?? Date().addingTimeInterval(-7 * 24 * 60 * 60)
        sinceDates[key] = since
        UserDefaults.standard.set(Date(), forKey: storageKey)
        return since
    }

    // MARK: Cache

    private func setAll(_ status: SectionStatus) {
        resumeStatus = status
        matchesStatus = status
        activityStatus = status
        goalStatus = status
    }

    private func loadCache(for owner: UUID) {
        var descriptor = FetchDescriptor<DashboardCache>(predicate: #Predicate { $0.ownerId == owner })
        descriptor.fetchLimit = 1
        guard let cache = try? context.fetch(descriptor).first,
              let cached = try? JSONDecoder().decode(DashboardServerData.self, from: cache.payload) else {
            data = DashboardServerData()
            hasData = false
            return
        }
        data = cached
        statusActivity = cached.activity.filter { $0.kind == .status }
        tailoredActivity = cached.activity.filter { $0.kind == .tailored }
        hasData = true
    }

    private func saveCache(for owner: UUID) {
        guard let payload = try? JSONEncoder().encode(data) else { return }
        var descriptor = FetchDescriptor<DashboardCache>(predicate: #Predicate { $0.ownerId == owner })
        descriptor.fetchLimit = 1
        if let cache = try? context.fetch(descriptor).first {
            cache.payload = payload
            cache.updatedAt = Date()
        } else {
            context.insert(DashboardCache(ownerId: owner, payload: payload))
        }
        try? context.save()
    }
}
