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

    @Published private(set) var phase: Phase = .launching
    @Published var signInRequest: SignInReason?
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
        router: AppRouter
    ) {
        self.auth = auth
        self.tracker = tracker
        self.dashboard = dashboard
        self.resumeManager = resumeManager
        self.matchedJobs = matchedJobs
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

            resumeManager.signedIn(userId: user.id) // keeps a guest's resume
            tracker.authChanged(state)
            dashboard.authChanged(state)

            if !legacyBookmarks.isEmpty {
                tracker.importJobs(legacyBookmarks)
                legacyBookmarks = []
            }

            if wasGuest {
                moveGuestResumeToAccount(userId: user.id)
            } else {
                router.tab = .home
                // The resume kept on this device: match it again
                if let data = resumeManager.pdfData, !matchedJobs.hasResume {
                    matchedJobs.load(resumeData: data, country: router.country)
                }
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
    /// account (the sign-in sheet says so up front), then matching runs again
    /// so the matches are stored too.
    private func moveGuestResumeToAccount(userId: UUID) {
        guard let data = resumeManager.pdfData,
              resumeManager.accountResumeId(for: userId) == nil else {
            notice = "Signed in. Your progress is now saved."
            return
        }
        let text = resumeManager.resumeText
        let title = resumeManager.fileName

        Task {
            if let id = await auth.saveGuestResume(pdfData: data, text: text, title: title) {
                resumeManager.linkToAccount(resumeId: id, userId: userId)
                notice = "Signed in. Your resume is saved to your account."
                if matchedJobs.hasResume { await matchedJobs.refresh() }
            } else {
                notice = "Signed in. Your resume couldn't be saved; it's still on this device."
            }
        }
    }

    // MARK: Sign-out Cleanup

    /// Sign-out, account deletion or an expired session: nothing from the
    /// previous user stays on this device.
    private func clearLocalData() {
        resumeManager.signedOut()
        matchedJobs.reset()
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
        URLCache.shared.removeAllCachedResponses()
        clearTemporaryFiles()
    }

    private static func clearTemporaryFiles() {
        let tmp = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.pathExtension.lowercased() == "pdf" {
            try? FileManager.default.removeItem(at: item)
        }
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
