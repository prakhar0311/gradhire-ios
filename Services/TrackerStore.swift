import Foundation
import Combine
import SwiftData

// MARK: - Tracker Store (app-wide)

/// The signed-in user's tracked jobs. Reads come from the SwiftData cache, so
/// the tracker and the badges on job cards show instantly and offline. Every
/// change is saved locally first and synced to Supabase in the background:
/// pending changes are pushed (as upserts on user + job, so retries never
/// duplicate), then the server rows are pulled back.
final class TrackerStore: ObservableObject {

    /// Newest activity first; never includes rows waiting to be deleted.
    @Published private(set) var items: [TrackedApplication] = []
    @Published private(set) var isSignedIn = false
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    /// True once the server rows were pulled since the last sign-in.
    @Published private(set) var hasSynced = false
    @Published var syncError: String?

    /// A guest tapped bookmark: show sign-in, then save this job.
    @Published var signInPromptJob: Job?
    /// "Did you apply to [Company]?" after returning from an apply link.
    @Published var applyPrompt: Job?

    private var statusByJob: [UUID: ApplicationStatus] = [:]

    private let repository: any ApplicationRepository
    private let context: ModelContext
    private var userId: UUID?
    private var syncTask: Task<Void, Never>?
    private var needsResync = false
    private var openedApplyJob: Job?
    private var openedApplyExternally = false

    init(repository: any ApplicationRepository) {
        self.repository = repository
        self.context = ModelContext(LocalStore.container)
    }

    // MARK: Reading

    func status(for jobId: UUID) -> ApplicationStatus? {
        statusByJob[jobId]
    }

    func item(for jobId: UUID) -> TrackedApplication? {
        items.first { $0.jobId == jobId }
    }

    func count(for status: ApplicationStatus?) -> Int {
        guard let status else { return items.count }
        return items.filter { $0.status == status }.count
    }

    /// Unsaving a job that's past Saved deletes its history, so ask first.
    func needsRemoveConfirmation(_ jobId: UUID) -> Bool {
        guard let status = status(for: jobId) else { return false }
        return status != .saved
    }

    // MARK: Account Changes

    func authChanged(_ state: AuthViewModel.State) {
        switch state {
        case .loading:
            break

        case .signedOut:
            guard isSignedIn || userId != nil || !items.isEmpty else {
                clearCache()
                return
            }
            userId = nil
            isSignedIn = false
            hasSynced = false
            syncError = nil
            applyPrompt = nil
            openedApplyJob = nil
            syncTask?.cancel()
            clearCache()
            reload()

        case .signedIn(let user):
            guard user.id != userId else { return }
            userId = user.id
            isSignedIn = true
            hasSynced = false
            syncError = nil
            removeOtherUsersRows(keeping: user.id)
            reload()
            importLegacyBookmarks()

            // Finish the save a guest started before signing in
            if let job = signInPromptJob {
                signInPromptJob = nil
                if status(for: job.id) == nil { save(job) }
            }

            scheduleSync(after: 0)
        }
    }

    // MARK: Changes

    /// Bookmark button: saves the job, or removes it if already tracked.
    /// Guests are asked to sign in first.
    func toggleSave(_ job: Job) {
        guard isSignedIn else {
            signInPromptJob = job
            return
        }
        if status(for: job.id) != nil {
            remove(job.id)
        } else {
            save(job)
        }
    }

    func save(_ job: Job, status: ApplicationStatus = .saved) {
        guard let userId else { return }

        if let model = model(for: job.id) {
            if model.syncState == .pendingDelete { model.syncState = .pendingUpsert }
            model.snapshot = job.snapshot
            model.touch()
            setStatus(status, on: model)
        } else {
            let model = TrackedJob(ownerId: userId, jobId: job.id, status: .saved, snapshot: job.snapshot)
            context.insert(model)
            setStatus(status, on: model)
        }
        commit()
    }

    func setStatus(_ status: ApplicationStatus, for jobId: UUID) {
        guard let model = model(for: jobId), model.syncState != .pendingDelete else { return }
        setStatus(status, on: model)
        model.touch()
        commit()
    }

    func setNotes(_ notes: String, for jobId: UUID) {
        guard let model = model(for: jobId), model.syncState != .pendingDelete else { return }
        let trimmed = String(notes.prefix(10_000))
        guard trimmed != model.notes else { return }
        model.notes = trimmed
        model.touch()
        // Typing: wait for a pause before syncing
        commit(syncDelay: 1.5)
    }

    /// Dashboard "Mark followed up": hides the reminder for another week.
    func markFollowedUp(_ jobId: UUID) {
        guard let model = model(for: jobId), model.syncState != .pendingDelete else { return }
        model.followUpAt = Date()
        model.touch()
        commit()
    }

    func remove(_ jobId: UUID) {
        guard let model = model(for: jobId) else { return }
        model.syncState = .pendingDelete
        model.localRevision += 1
        commit()
    }

    private func setStatus(_ status: ApplicationStatus, on model: TrackedJob) {
        model.status = status
        if status.hasApplied, model.appliedAt == nil {
            model.appliedAt = Date()
        } else if status == .saved {
            model.appliedAt = nil
        }
    }

    // MARK: "Did you apply?"

    /// Called when an apply link is opened, in the in-app browser or in
    /// Safari (`externally`). Asked once per job and account, and only if the
    /// job isn't already marked as applied.
    func applyOpened(_ job: Job, externally: Bool) {
        guard isSignedIn, let userId else { return }
        if status(for: job.id)?.hasApplied == true { return }
        if askedApplyJobs(userId).contains(job.id.uuidString) { return }
        openedApplyJob = job
        openedApplyExternally = externally
    }

    /// Called when the user is back: the in-app browser closed, or the app
    /// returned to the foreground (`fromForeground`) after an external link.
    func checkApplyPrompt(fromForeground: Bool) {
        guard let job = openedApplyJob, let userId else { return }
        // Coming back to the app while the in-app browser is still open isn't
        // "back from applying"; wait for the browser to close.
        if fromForeground && !openedApplyExternally { return }
        openedApplyJob = nil
        var asked = askedApplyJobs(userId)
        asked.insert(job.id.uuidString)
        UserDefaults.standard.set(Array(asked), forKey: askedKey(userId))
        applyPrompt = job
    }

    func answerApplyPrompt(_ job: Job, applied: Bool) {
        applyPrompt = nil
        guard applied else { return }
        if status(for: job.id) != nil {
            setStatus(.applied, for: job.id)
        } else {
            save(job, status: .applied)
        }
    }

    private func askedKey(_ userId: UUID) -> String {
        "apply_prompted_v1_\(userId.uuidString.lowercased())"
    }

    private func askedApplyJobs(_ userId: UUID) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: askedKey(userId)) ?? [])
    }

    // MARK: History

    /// Status history for a tracked job, newest first. nil while the job
    /// hasn't reached the server yet, or when offline.
    func events(for jobId: UUID) async -> [ApplicationEventRecord]? {
        guard let applicationId = item(for: jobId)?.applicationId else { return nil }
        return try? await repository.fetchEvents(applicationId: applicationId)
    }

    // MARK: Sync

    func scheduleSync(after delay: TimeInterval = 0.5) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Pushes pending changes, then pulls the server rows. Safe to call any
    /// time; overlapping calls are merged into one more pass.
    func sync() async {
        guard let owner = userId else { return }
        guard NetworkMonitor.shared.isConnected else { return }

        if isSyncing {
            needsResync = true
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        repeat {
            needsResync = false
            await syncOnce(owner)
        } while needsResync && userId == owner
    }

    private func syncOnce(_ owner: UUID) async {
        do {
            try await pushPending(owner)
            let records = try await repository.fetchApplications()
            guard userId == owner else { return } // signed out mid-sync
            applyServerRows(records, owner: owner)
            syncError = nil
            hasSynced = true
        } catch {
            guard userId == owner else { return }
            syncError = Self.message(for: error)
        }
        reload()
    }

    private func pushPending(_ owner: UUID) async throws {
        let pending = models(owner: owner).filter { $0.syncState != .synced }

        for model in pending {
            guard userId == owner else { return }

            let revision = model.localRevision
            let jobId = model.jobId

            if model.syncState == .pendingDelete {
                try await repository.deleteApplication(userId: owner, jobId: jobId)
                guard userId == owner else { return }
                if model.localRevision == revision, model.syncState == .pendingDelete {
                    context.delete(model)
                }
                continue
            }

            let payload = ApplicationUpsert(
                userId: owner,
                jobId: jobId,
                status: model.status,
                notes: model.notes.isEmpty ? nil : model.notes,
                savedAt: model.savedAt,
                appliedAt: model.appliedAt,
                followUpAt: model.followUpAt,
                jobSnapshot: model.snapshot
            )

            let record: ApplicationRecord
            do {
                record = try await upsertEnsuringJob(payload)
            } catch TrackerError.jobUnavailable {
                // Can never sync; drop it rather than retrying forever
                guard userId == owner else { return }
                context.delete(model)
                syncError = TrackerError.jobUnavailable.localizedDescription
                continue
            }

            guard userId == owner else { return }
            if model.localRevision == revision {
                model.apply(record)
            } else {
                model.applicationId = record.id // edited meanwhile; push again
                needsResync = true
            }
        }

        try? context.save()
    }

    /// The job must exist in the shared jobs table first. The backend usually
    /// added it when serving the feed; if not, ask it to and retry once.
    private func upsertEnsuringJob(_ payload: ApplicationUpsert) async throws -> ApplicationRecord {
        do {
            return try await repository.upsertApplication(payload)
        } catch let error where TrackerError.isMissingJob(error) {
            try await repository.ensureJob(id: payload.jobId, snapshot: payload.jobSnapshot)
            return try await repository.upsertApplication(payload)
        }
    }

    private func applyServerRows(_ records: [ApplicationRecord], owner: UUID) {
        let byJob = Dictionary(records.map { ($0.jobId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()

        for model in models(owner: owner) {
            seen.insert(model.jobId)
            guard model.syncState == .synced else { continue } // local change wins

            if let record = byJob[model.jobId] {
                model.apply(record)
            } else {
                context.delete(model) // removed on another device
            }
        }

        for record in records where !seen.contains(record.jobId) {
            let model = TrackedJob(ownerId: owner, jobId: record.jobId, status: record.status, snapshot: record.jobSnapshot)
            model.apply(record)
            context.insert(model)
        }

        try? context.save()
    }

    // MARK: Cache

    private func commit(syncDelay: TimeInterval = 0.3) {
        try? context.save()
        reload()
        scheduleSync(after: syncDelay)
    }

    private func reload() {
        guard let userId else {
            items = []
            statusByJob = [:]
            pendingCount = 0
            return
        }

        let all = models(owner: userId)
        pendingCount = all.filter { $0.syncState != .synced }.count

        let visible = all
            .filter { $0.syncState != .pendingDelete }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { TrackedApplication($0) }

        items = visible
        statusByJob = Dictionary(visible.map { ($0.jobId, $0.status) }, uniquingKeysWith: { first, _ in first })
    }

    private func models(owner: UUID) -> [TrackedJob] {
        let descriptor = FetchDescriptor<TrackedJob>(predicate: #Predicate { $0.ownerId == owner })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func model(for jobId: UUID) -> TrackedJob? {
        guard let userId else { return nil }
        let key = TrackedJob.key(ownerId: userId, jobId: jobId)
        var descriptor = FetchDescriptor<TrackedJob>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Defense in depth: the cache is cleared on sign-out, but never show
    /// rows that belong to anyone else.
    private func removeOtherUsersRows(keeping owner: UUID) {
        try? context.delete(model: TrackedJob.self, where: #Predicate { $0.ownerId != owner })
        try? context.save()
    }

    private func clearCache() {
        try? context.delete(model: TrackedJob.self)
        try? context.save()
    }

    private func importLegacyBookmarks() {
        let jobs = LegacyBookmarks.take()
        guard !jobs.isEmpty else { return }
        for job in jobs.reversed() where status(for: job.id) == nil {
            save(job)
        }
    }

    // MARK: Errors

    private static func message(for error: Error) -> String {
        if let trackerError = error as? TrackerError { return trackerError.localizedDescription }
        if let repositoryError = error as? RepositoryError { return repositoryError.localizedDescription }
        if error is URLError || error is JobAPIError {
            return "You're offline. Changes are saved on this device and will sync later."
        }
        return TrackerError.serverBusy.localizedDescription
    }
}
