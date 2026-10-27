import Foundation
import Combine

// MARK: - All New Grad Jobs ("All Jobs")

final class AllJobsViewModel: ObservableObject {

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var state: JobsLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreError: String?
    @Published private(set) var refreshError: String?
    @Published private(set) var hasMore = false

    private var country = "in"
    private var nextPage = 1
    private var loadedAt: Date?
    private var task: Task<Void, Never>?

    // Matches the backend cache TTL; older lists are refetched on appear.
    private let staleAfter: TimeInterval = 30 * 60

    /// Loads the first page unless a fresh list for this country is already in memory.
    func loadIfNeeded(country: String) {
        if country != self.country {
            self.country = country
            jobs = []
            state = .idle
        }

        switch state {
        case .idle, .failed:
            loadFirstPage()
        case .loading:
            return
        case .loaded, .empty:
            let isStale = loadedAt.map { Date().timeIntervalSince($0) > staleAfter } ?? true
            if isStale {
                Task { await refresh() }
            }
        }
    }

    func retry() {
        loadFirstPage()
    }

    /// Pull to refresh: keeps the current list on screen while reloading page 1.
    func refresh() async {
        task?.cancel()
        isLoadingMore = false
        refreshError = nil

        do {
            let page = try await JobAPIService.shared.fetchNewGradJobs(country: country, page: 1)
            applyFirstPage(page)
        } catch is CancellationError {
            return
        } catch {
            if jobs.isEmpty {
                state = .failed(JobAPIError.from(error).localizedDescription)
            } else {
                refreshError = JobAPIError.from(error).localizedDescription
            }
        }
    }

    /// Infinite scroll: called when the end of the list becomes visible.
    func loadMoreIfNeeded() {
        guard state == .loaded, hasMore, !isLoadingMore, loadMoreError == nil else { return }
        loadMore()
    }

    func retryLoadMore() {
        loadMoreError = nil
        loadMore()
    }

    func dismissRefreshError() {
        refreshError = nil
    }

    // MARK: - Private

    private func loadFirstPage() {
        task?.cancel()
        state = .loading
        isLoadingMore = false
        loadMoreError = nil
        refreshError = nil

        let country = country
        task = Task {
            do {
                let page = try await JobAPIService.shared.fetchNewGradJobs(country: country, page: 1)
                guard !Task.isCancelled else { return }
                applyFirstPage(page)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(JobAPIError.from(error).localizedDescription)
            }
        }
    }

    private func loadMore() {
        isLoadingMore = true

        let country = country
        let pageNumber = nextPage
        task = Task {
            defer { if !Task.isCancelled { isLoadingMore = false } }

            do {
                let page = try await JobAPIService.shared.fetchNewGradJobs(country: country, page: pageNumber)
                guard !Task.isCancelled else { return }

                // The backend list can shift between pages; skip anything already shown
                let knownIDs = Set(jobs.map(\.id))
                jobs.append(contentsOf: page.jobs.filter { !knownIDs.contains($0.id) })
                hasMore = page.hasMore
                nextPage = pageNumber + 1
            } catch {
                guard !Task.isCancelled else { return }
                loadMoreError = JobAPIError.from(error).localizedDescription
            }
        }
    }

    private func applyFirstPage(_ page: NewGradJobsPage) {
        jobs = page.jobs
        hasMore = page.hasMore
        nextPage = 2
        loadedAt = Date()
        loadMoreError = nil
        state = page.jobs.isEmpty ? .empty : .loaded
    }
}
