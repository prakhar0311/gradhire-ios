import Foundation
import Combine

// MARK: - App Session

/// The one place that decides what the app shows: the launch splash, the
/// Welcome screen, a guest session or a signed-in session. It follows the
/// auth state, owns the app-wide sign-in sheet, and does the work that has to
/// happen when the session changes (moving a guest's resume to their
/// account, clearing every local trace on sign-out).
final class AppSession: ObservableObject {

    enum Phase: Equatable {
        case launching
        case welcome
        case guest
        case signedIn
    }

    /// Why the shared sign-in sheet is shown.
    enum SignInReason: Identifiable, Equatable {
        case saveJob(Job)
        case tracker
        case dashboard
        case general

        var id: String {
            switch self {
            case .saveJob(let job): return "save-\(job.id)"
            case .tracker:          return "tracker"
            case .dashboard:        return "dashboard"
            case .general:          return "general"
            }
        }
    }

    /// Shown when the user can't save another resume (app check or database).
    enum ResumeLimitPrompt: String, Identifiable {
        case originals
        case versions

        var id: String { rawValue }
    }

    @Published private(set) var phase: Phase = .launching
    @Published var signInRequest: SignInReason?
    @Published var resumeLimitPrompt: ResumeLimitPrompt?
    /// The full "Your saved resumes" list, opened from anywhere (e.g. the limit sheet)
    @Published var showsSavedResumes = false
    /// Short confirmation shown at the top of the screen (a toast)
    @Published var notice: String?
    /// Shown on the Welcome screen, e.g. after a session expired
    @Published private(set) var welcomeMessage: String?
    /// Jobs saved on this device by the previous app version, kept in memory
    /// for this session only (they're already removed from disk).
    @Published private(set) var legacyBookmarks: [Job] = []

    var isGuest: Bool { phase == .guest }
    var isSignedIn: Bool { phase == .signedIn }

    private let auth: AuthViewModel
    private let tracker: TrackerStore
    private let dashboard: DashboardViewModel
    private let resumeManager: ResumeManager
    private let matchedJobs: MatchedJobsViewModel
    private let search: JobSearchViewModel
    private let router: AppRouter

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var signedInUserId: UUID?

    init(
        auth: AuthViewModel,
        tracker: TrackerStore,
        dashboard: DashboardViewModel,
        resumeManager: ResumeManager,
        matchedJobs: MatchedJobsViewModel,
        search: JobSearchViewModel,
        router: AppRouter
    ) {
        self.auth = auth
        self.tracker = tracker
        self.dashboard = dashboard
        self.resumeManager = resumeManager
        self.matchedJobs = matchedJobs
        self.search = search
        self.router = router
    }

    // MARK: Launch

    /// Call once from the app root.
    func start() async {
        guard !started else { return }
        started = true

        legacyBookmarks = LaunchCleanup.run(hasStoredSession: auth.user != nil)

        auth.start()

        // An expired session is refreshed (or rejected) before anything shows
        if auth.user != nil {
            _ = await withTimeout(seconds: 6) { await self.auth.validateStoredSession() }
        }

        auth.$state
            .removeDuplicates()
            .sink { [weak self] state in self?.authChanged(state) }
            .store(in: &cancellables)

        // For You and the dashboard follow the active resume
        resumeManager.$activeResumeId
            .removeDuplicates()
            .sink { [weak self] id in self?.activeResumeChanged(id) }
            .store(in: &cancellables)

        // Saving, renaming or deleting a resume refreshes the dashboard's
        // server data (matches, activity) right away
        resumeManager.$savedResumes
            .map { $0.map { "\($0.id)|\($0.title ?? "")" } }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.signedInUserId != nil else { return }
                self.dashboard.scheduleRefresh(accountResumeId: self.resumeManager.activeResumeId)
            }
            .store(in: &cancellables)

        // A guest tapping bookmark asks to sign in through the shared sheet
        tracker.$signInPromptJob
            .compactMap { $0 }
            .sink { [weak self] job in self?.signInRequest = .saveJob(job) }
            .store(in: &cancellables)
    }

    private func authChanged(_ state: AuthViewModel.State) {
        switch state {
        case .loading:
            break

        case .signedOut:
            let wasSignedIn = signedInUserId != nil
            signedInUserId = nil
            tracker.authChanged(.signedOut)
            dashboard.authChanged(.signedOut)

            if wasSignedIn {
                clearLocalData()
                welcomeMessage = auth.lastSignOutReason == .expired
                    ? "Your session expired. Please sign in again."
                    : nil
                setPhase(.welcome)
            } else if phase == .launching {
                // Nobody signed in (or the stored session was rejected):
                // nothing on this device may belong to a user
                clearLocalData()
                welcomeMessage = auth.lastSignOutReason == .expired
                    ? "Your session expired. Please sign in again."
                    : nil
                setPhase(.welcome)
            }
            // A guest stays a guest (sign-in sheet cancelled, etc.)

        case .signedIn(let user):
            guard user.id != signedInUserId else { return }
            let wasGuest = phase == .guest
            signedInUserId = user.id
            welcomeMessage = nil

            search.signedIn(userId: user.id)
            tracker.authChanged(state)
            dashboard.authChanged(state) // its cached matches seed For You
            let hasGuestUpload = resumeManager.signedIn(userId: user.id) // keeps a guest's resume

            if !legacyBookmarks.isEmpty {
                tracker.importJobs(legacyBookmarks)
                legacyBookmarks = []
            }

            if wasGuest, hasGuestUpload {
                moveGuestResumeToAccount()
            } else if wasGuest {
                notice = "Signed in. Your progress is now saved."
            } else {
                router.tab = .home
            }

            signInRequest = nil
            setPhase(.signedIn)
        }
    }

    private func setPhase(_ newPhase: Phase) {
        guard phase != newPhase else { return }
        phase = newPhase
    }

    // MARK: Guest

    func continueAsGuest() {
        welcomeMessage = nil
        search.signedOut()
        router.reset(for: .guest)
        setPhase(.guest)
    }

    /// Account-only features call this instead of failing or showing an
    /// empty screen.
    func requireAccount(_ reason: SignInReason) {
        signInRequest = reason
    }

    /// The shared sign-in sheet closed without signing in.
    func signInSheetDismissed() {
        if !isSignedIn { tracker.signInPromptJob = nil }
    }

    /// A guest signed in during this session: their resume goes to the new
    /// account (the sign-in sheet says so up front) and becomes active. If the
    /// account is already full, the account's own active resume is used.
    private func moveGuestResumeToAccount() {
        Task {
            do {
                try await resumeManager.saveUnsavedUpload()
                notice = "Signed in. Your resume is saved to your account."
            } catch ResumeSaveError.originalLimit {
                notice = "Signed in. Your account already has the most resumes it can save."
                resumeLimitPrompt = .originals
            } catch {
                notice = "Signed in. Your resume couldn't be saved to your account."
            }
        }
    }

    // MARK: Active Resume

    /// Signed in: For You shows the active resume's matches; the dashboard's
    /// cached matches for it show first.
    private func activeResumeChanged(_ id: UUID?) {
        guard signedInUserId != nil else { return }

        guard let id else {
            if resumeManager.accountStatus == .loaded { matchedJobs.reset() }
            dashboard.scheduleRefresh(accountResumeId: nil)
            return
        }

        let cached: [Job]
        if dashboard.data.resume?.id == id {
            cached = dashboard.data.matches.map(\.job)
        } else if matchedJobs.accountResumeId == nil, matchedJobs.hasLoaded {
            // A guest's matches for the resume just saved
            cached = matchedJobs.jobs
        } else {
            cached = []
        }
        matchedJobs.loadAccount(resumeId: id, country: router.country, cached: cached)
        dashboard.scheduleRefresh(accountResumeId: id)
    }

    /// The limit sheet's "Manage saved resumes".
    func manageSavedResumes() {
        resumeLimitPrompt = nil
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000) // let the sheet close first
            showsSavedResumes = true
        }
    }

    // MARK: Sign-out Cleanup

    /// Sign-out, account deletion or an expired session: nothing from the
    /// previous user stays on this device.
    private func clearLocalData() {
        resumeManager.signedOut()
        matchedJobs.reset()
        search.signedOut()
        resumeLimitPrompt = nil
        showsSavedResumes = false
        OptimizeResumeViewModel.clearCache()
        router.reset(for: .welcome)
        LaunchCleanup.removeUserData()
    }

    // MARK: Helpers

    private func withTimeout(seconds: Double, _ work: @escaping () async -> Bool) async -> Bool? {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

// MARK: - Launch Cleanup

/// Removes guest data (and data from earlier app versions) from the device.
enum LaunchCleanup {

    private static let versionKey = "launch_cleanup_version"
    private static let currentVersion = 1

    /// Runs at every launch. Returns old-version bookmarks to keep in memory
    /// for this session (they're deleted from disk here).
    static func run(hasStoredSession: Bool) -> [Job] {
        clearTemporaryFiles()
        removeOldDownloads()
        UserDefaults.standard.removeObject(forKey: "dashboard_last_visit_v1_guest")

        if !hasStoredSession {
            // Nobody is signed in, so nothing on disk may belong to a user
            ResumeManager.removeAllStoredResumes()
        }

        if UserDefaults.standard.integer(forKey: versionKey) < currentVersion {
            removeUnscopedResumeFiles()
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
        }

        return LegacyBookmarks.take()
    }

    /// Everything tied to a signed-in user that isn't already cleared by its
    /// owner (tracker and dashboard caches clear themselves).
    static func removeUserData() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("apply_prompted_") || key.hasPrefix("dashboard_last_visit_") {
            defaults.removeObject(forKey: key)
        }
        JobSearchViewModel.removeAllStoredSearches(from: defaults)
        MatchedJobsViewModel.removeRefreshTimes(from: defaults)
        URLCache.shared.removeAllCachedResponses()
        clearTemporaryFiles()
    }

    private static func clearTemporaryFiles() {
        let tmp = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.pathExtension.lowercased() == "pdf" {
            try? FileManager.default.removeItem(at: item)
        }
        // Saved-resume previews and shares; left behind if the app was
        // killed while one was open
        try? FileManager.default.removeItem(at: tmp.appendingPathComponent("SavedResumes", isDirectory: true))
    }

    /// Optimized resumes the previous version kept in Documents.
    private static func removeOldDownloads() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let items = (try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent.hasPrefix("Optimized_Resume_") {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// The first 2B builds kept the resume at the top of Resume/ for anyone,
    /// guests included. Per-user folders replace that.
    private static func removeUnscopedResumeFiles() {
        guard let root = ResumeManager.rootFolder() else { return }
        for name in ["resume.pdf", "resume.txt", "meta.json"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }
}
