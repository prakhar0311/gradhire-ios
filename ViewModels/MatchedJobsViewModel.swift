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

    private var resumeData: Data?
    private var country = "in"
    private var task: Task<Void, Never>?

    /// For signed-in users whose resume is saved to their account: the
    /// resume id and session token, so the backend stores the matches for
    /// the dashboard. Set once by the app.
    var accountContext: (() async -> (resumeId: UUID, accessToken: String)?)?

    /// The resume-matched jobs are loaded (or empty) for the current resume.
    var hasLoaded: Bool { state == .loaded || state == .empty }

    var hasResume: Bool { resumeData != nil }

    /// The matched jobs in the selected sort order.
    var visibleJobs: [Job] {
        jobs.sorted(by: sort)
    }

    /// Starts matching for a newly uploaded resume, replacing any previous results.
    func load(resumeData: Data, country: String) {
        self.resumeData = resumeData
        self.country = country
        jobs = []
        reload()
    }

    /// Signed out: forget the resume and its matches.
    func reset() {
        task?.cancel()
        task = nil
        resumeData = nil
        jobs = []
        state = .idle
        sort = .bestMatch
    }

    func retry() {
        reload()
    }

    /// Pull to refresh: keeps the current list on screen while reloading.
    func refresh() async {
        guard let resumeData else { return }
        task?.cancel()

        do {
            let fetched = try await JobAPIService.shared.fetchJobsFromResume(
                pdfData: resumeData,
                country: country,
                account: await accountContext?()
            )
            apply(fetched)
        } catch is CancellationError {
            return
        } catch {
            if jobs.isEmpty { fail(with: error) }
        }
    }

    private func reload() {
        guard let resumeData else { return }

        task?.cancel()
        state = .loading

        let country = country
        task = Task {
            do {
                let fetched = try await JobAPIService.shared.fetchJobsFromResume(
                    pdfData: resumeData,
                    country: country,
                    account: await accountContext?()
                )
                guard !Task.isCancelled else { return }
                apply(fetched)
            } catch {
                guard !Task.isCancelled else { return }
                fail(with: error)
            }
        }
    }

    private func apply(_ fetched: [Job]) {
        jobs = fetched
        state = fetched.isEmpty ? .empty : .loaded
    }

    private func fail(with error: Error) {
        state = .failed(JobAPIError.from(error).localizedDescription)
    }
}
