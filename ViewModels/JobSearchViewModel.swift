import Foundation
import Combine

// MARK: - Job Search ("All Jobs" search)

/// Searches every entry-level job on the backend. Kept apart from the All
/// Jobs feed, so clearing the search brings the feed back as it was.
final class JobSearchViewModel: ObservableObject {

    static let maxQueryLength = 100
    static let minQueryLength = 2
    static let suggestions = ["iOS Developer", "Data Analyst", "Backend", "Frontend", "Python", "Java", "Remote"]

    /// What's in the search field
    @Published var text = "" {
        didSet { textChanged() }
    }

    /// The cleaned query the results belong to; nil shows the normal feed
    @Published private(set) var activeQuery: String?
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var state: JobsLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreError: String?
    @Published private(set) var refreshError: String?
    @Published private(set) var hasMore = false
    @Published private(set) var total = 0
    @Published private(set) var totalIsExact = true
    @Published private(set) var recentSearches: [String] = []

    var isSearching: Bool { activeQuery != nil }

    private var country = "in"
    private var nextPage = 1
    private var debounceTask: Task<Void, Never>?
    private var task: Task<Void, Never>?
    private let debounce: UInt64 = 400_000_000

    /// Signed-in users keep recent searches on this device; guests only in memory
    private var userId: UUID?
    private static let recentsKeyPrefix = "recent_searches_v1_"
    private static let maxRecentSearches = 5

    // MARK: Input

    func setCountry(_ country: String) {
        guard country != self.country else { return }
        self.country = country
        if let activeQuery { start(activeQuery) }
    }

    /// Return key: search now and remember the query.
    func submit() {
        guard let query = Self.clean(text) else { return }
        if query != activeQuery || state.isFailed { start(query) }
        addRecentSearch(query)
    }

    /// A suggestion chip or recent search was tapped.
    func select(_ term: String) {
        text = term
        submit()
    }

    func clear() {
        text = ""
    }

    /// A result was opened: worth remembering.
    func resultOpened() {
        if let activeQuery { addRecentSearch(activeQuery) }
    }

    func removeRecentSearch(_ term: String) {
        recentSearches.removeAll { $0 == term }
        saveRecentSearches()
    }

    // MARK: Results

    func retry() {
        if let activeQuery { start(activeQuery) }
    }

    /// Pull to refresh: keeps the current results on screen while reloading.
    func refresh() async {
        guard let query = activeQuery else { return }
        task?.cancel()
        isLoadingMore = false
        refreshError = nil

        do {
            let page = try await JobAPIService.shared.fetchNewGradJobs(country: country, page: 1, query: query)
            guard query == activeQuery else { return }
            applyFirstPage(page)
        } catch is CancellationError {
            return
        } catch {
            guard query == activeQuery else { return }
            if jobs.isEmpty {
                state = .failed(JobAPIError.from(error).localizedDescription)
            } else {
                refreshError = JobAPIError.from(error).localizedDescription
            }
        }
    }

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

    // MARK: Account

    func signedIn(userId: UUID) {
        guard userId != self.userId else { return }
        // Searches made as a guest a moment ago carry over to the account
        let guestSearches = self.userId == nil ? recentSearches : []
        self.userId = userId
        let stored = UserDefaults.standard.stringArray(forKey: Self.recentsKey(userId)) ?? []
        recentSearches = Array(uniqued(guestSearches + stored).prefix(Self.maxRecentSearches))
        saveRecentSearches()
    }

    /// Sign-out, account deletion or a new guest session: nothing carries over.
    func signedOut() {
        if let userId {
            UserDefaults.standard.removeObject(forKey: Self.recentsKey(userId))
        }
        userId = nil
        recentSearches = []
        text = ""
    }

    static func removeAllStoredSearches(from defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(recentsKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Query Cleaning

    /// Same rules as the backend: letters, digits, spaces and + # . - / only,
    /// whitespace collapsed, at most 100 characters. Nil if under 2 characters.
    static func clean(_ raw: String) -> String? {
        let allowed = raw.replacingOccurrences(of: "[^\\p{L}\\p{N}\\s+#./-]", with: " ", options: .regularExpression)
        let collapsed = allowed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let limited = String(collapsed.prefix(maxQueryLength)).trimmingCharacters(in: .whitespaces)
        return limited.count >= minQueryLength ? limited : nil
    }

    // MARK: - Private

    private func textChanged() {
        if text.count > Self.maxQueryLength {
            text = String(text.prefix(Self.maxQueryLength))
        }

        debounceTask?.cancel()

        guard let query = Self.clean(text) else {
            // Cleared (or too short): back to the feed
            task?.cancel()
            activeQuery = nil
            resetResults()
            return
        }

        guard query.lowercased() != activeQuery?.lowercased() else { return }

        debounceTask = Task { [debounce] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            start(query)
        }
    }

    private func start(_ query: String) {
        debounceTask?.cancel()
        task?.cancel()
        activeQuery = query
        resetResults()
        state = .loading

        let country = country
        task = Task {
            do {
                let page = try await JobAPIService.shared.fetchNewGradJobs(country: country, page: 1, query: query)
                // A newer query may have started while this one was in flight
                guard !Task.isCancelled, query == activeQuery else { return }
                applyFirstPage(page)
            } catch {
                guard !Task.isCancelled, query == activeQuery else { return }
                state = .failed(JobAPIError.from(error).localizedDescription)
            }
        }
    }

    private func loadMore() {
        guard let query = activeQuery else { return }
        isLoadingMore = true

        let country = country
        let pageNumber = nextPage
        task = Task {
            defer { if !Task.isCancelled, query == activeQuery { isLoadingMore = false } }

            do {
                let page = try await JobAPIService.shared.fetchNewGradJobs(country: country, page: pageNumber, query: query)
                guard !Task.isCancelled, query == activeQuery else { return }

                let knownIDs = Set(jobs.map(\.id))
                jobs.append(contentsOf: page.jobs.filter { !knownIDs.contains($0.id) })
                hasMore = page.hasMore
                total = max(page.total ?? jobs.count, jobs.count)
                totalIsExact = page.totalIsExact ?? !page.hasMore
                nextPage = pageNumber + 1
            } catch {
                guard !Task.isCancelled, query == activeQuery else { return }
                loadMoreError = JobAPIError.from(error).localizedDescription
            }
        }
    }

    private func applyFirstPage(_ page: NewGradJobsPage) {
        jobs = page.jobs
        hasMore = page.hasMore
        total = max(page.total ?? page.jobs.count, page.jobs.count)
        totalIsExact = page.totalIsExact ?? !page.hasMore
        nextPage = 2
        loadMoreError = nil
        state = page.jobs.isEmpty ? .empty : .loaded
    }

    private func resetResults() {
        jobs = []
        state = .idle
        isLoadingMore = false
        loadMoreError = nil
        refreshError = nil
        hasMore = false
        total = 0
        totalIsExact = true
    }

    private func addRecentSearch(_ query: String) {
        recentSearches = Array(uniqued([query] + recentSearches).prefix(Self.maxRecentSearches))
        saveRecentSearches()
    }

    private func saveRecentSearches() {
        // Guests' searches are never written to disk
        guard let userId else { return }
        UserDefaults.standard.set(recentSearches, forKey: Self.recentsKey(userId))
    }

    /// Case-insensitive, keeping the first (newest) spelling.
    private func uniqued(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func recentsKey(_ userId: UUID) -> String {
        recentsKeyPrefix + userId.uuidString
    }
}

private extension JobsLoadState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
