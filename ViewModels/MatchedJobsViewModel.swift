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

    private var resumeURL: URL?
    private var country = "in"
    private var task: Task<Void, Never>?

    var hasResume: Bool { resumeURL != nil }

    /// The matched jobs in the selected sort order.
    var visibleJobs: [Job] {
        jobs.sorted(by: sort)
    }

    /// Starts matching for a newly uploaded resume, replacing any previous results.
    func load(resumeURL: URL, country: String) {
        self.resumeURL = resumeURL
        self.country = country
        jobs = []
        reload()
    }

    func retry() {
        reload()
    }

    /// Pull to refresh: keeps the current list on screen while reloading.
    func refresh() async {
        guard let resumeURL else { return }
        task?.cancel()

        do {
            let fetched = try await JobAPIService.shared.fetchJobsFromResume(
                fileURL: resumeURL,
                country: country
            )
            apply(fetched)
        } catch is CancellationError {
            return
        } catch {
            if jobs.isEmpty { fail(with: error) }
        }
    }

    private func reload() {
        guard let resumeURL else { return }

        task?.cancel()
        state = .loading

        let country = country
        task = Task {
            do {
                let fetched = try await JobAPIService.shared.fetchJobsFromResume(
                    fileURL: resumeURL,
                    country: country
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
