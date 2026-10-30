import Foundation
import Combine

// MARK: - Load State

enum JobsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

// MARK: - Matched Jobs ("For You")

final class MatchedJobsViewModel: ObservableObject {

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var state: JobsLoadState = .idle

    // Lives with the app-level view model, so it survives job detail and back
    @Published var sort: JobSort = .bestMatch

    /// Guests: the uploaded PDF is matched directly.
    private var resumeData: Data?
    /// Signed in: the active saved resume; matches are stored per resume.
    private(set) var accountResumeId: UUID?
    private var country = "in"
    private var task: Task<Void, Never>?

    /// Set once by the app, for signed-in users' stored matches.
    var repository: (any ResumeRepository)?
    var accessToken: (() async -> String?)?

    /// Stored matches older than this are refreshed in the background.
    private let refreshAfter: TimeInterval = 6 * 60 * 60
    private static let refreshedKeyPrefix = "matches_refreshed_v1_"

    /// The resume-matched jobs are loaded (or empty) for the current resume.
    var hasLoaded: Bool { state == .loaded || state == .empty }

    var hasResume: Bool { resumeData != nil || accountResumeId != nil }

    /// The matched jobs in the selected sort order.
    var visibleJobs: [Job] {
        jobs.sorted(by: sort)
    }

    /// Guests: starts matching for a newly uploaded resume, replacing any
    /// previous results.
    func load(resumeData: Data, country: String) {
        self.resumeData = resumeData
        accountResumeId = nil
        self.country = country
        jobs = []
        reload()
    }

    /// Signed in: matches for the active saved resume. Stored matches show
    /// first (`cached` even sooner); new jobs are matched in the background
    /// only when the stored ones are missing or older than six hours.
    func loadAccount(resumeId: UUID, country: String, cached: [Job] = []) {
        if resumeId == accountResumeId, hasLoaded || state == .loading { return }
        accountResumeId = resumeId
        resumeData = nil
        self.country = country
        jobs = cached
        state = cached.isEmpty ? .loading : .loaded

        task?.cancel()
        task = Task { await loadAccountMatches(resumeId: resumeId, force: false) }
    }

    /// Signed out: forget the resume and its matches.
    func reset() {
        task?.cancel()
        task = nil
        resumeData = nil
        accountResumeId = nil
        jobs = []
        state = .idle
        sort = .bestMatch
    }

    func retry() {
        if let accountResumeId {
            state = jobs.isEmpty ? .loading : state
            task?.cancel()
            task = Task { await loadAccountMatches(resumeId: accountResumeId, force: false) }
        } else {
            reload()
        }
    }

    /// Pull to refresh: keeps the current list on screen while reloading.
    func refresh() async {
        task?.cancel()

        if let accountResumeId {
            await loadAccountMatches(resumeId: accountResumeId, force: true)
            return
        }

        guard let resumeData else { return }
        do {
            let fetched = try await JobAPIService.shared.fetchJobsFromResume(pdfData: resumeData, country: country)
            apply(fetched)
        } catch is CancellationError {
            return
        } catch {
            if jobs.isEmpty { fail(with: error) }
        }
    }

    /// Removes every "matches refreshed" time (sign-out).
    static func removeRefreshTimes(from defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(refreshedKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Private

    private func reload() {
        guard let resumeData else { return }

        task?.cancel()
        state = .loading

        let country = country
        task = Task {
            do {
                let fetched = try await JobAPIService.shared.fetchJobsFromResume(pdfData: resumeData, country: country)
                guard !Task.isCancelled else { return }
                apply(fetched)
            } catch {
                guard !Task.isCancelled else { return }
                fail(with: error)
            }
        }
    }

    private func loadAccountMatches(resumeId: UUID, force: Bool) async {
        var hasStored = false

        if !force, let repository,
           let stored = try? await repository.fetchStoredMatches(resumeId: resumeId) {
            guard accountResumeId == resumeId, !Task.isCancelled else { return }
            let storedJobs = stored.compactMap(\.asJob)
            if !storedJobs.isEmpty {
                apply(storedJobs)
                hasStored = true
            }
        }

        let isFresh = refreshedAt(resumeId).map { Date().timeIntervalSince($0) < refreshAfter } ?? false
        if hasStored, isFresh, !force { return }

        do {
            guard let token = await accessToken?() else { throw RepositoryError.notSignedIn }
            let fetched = try await JobAPIService.shared.fetchJobsForResume(
                resumeId: resumeId, accessToken: token, country: country
            )
            guard accountResumeId == resumeId, !Task.isCancelled else { return }
            apply(fetched)
            UserDefaults.standard.set(Date(), forKey: Self.refreshedKeyPrefix + resumeId.uuidString)
        } catch is CancellationError {
            return
        } catch {
            guard accountResumeId == resumeId, !Task.isCancelled else { return }
            // Stored (or cached) matches stay on screen if the refresh fails
            if jobs.isEmpty { fail(with: error) }
        }
    }

    private func refreshedAt(_ resumeId: UUID) -> Date? {
        UserDefaults.standard.object(forKey: Self.refreshedKeyPrefix + resumeId.uuidString) as? Date
    }

    private func apply(_ fetched: [Job]) {
        jobs = fetched
        state = fetched.isEmpty ? .empty : .loaded
    }

    private func fail(with error: Error) {
        state = .failed(JobAPIError.from(error).localizedDescription)
    }
}
