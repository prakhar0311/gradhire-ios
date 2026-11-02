import Foundation
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

// MARK: - Events

/// Every analytics event the app logs, in one place. Parameters only ever
/// hold fixed values (the small enums below) or numbers: never resume text,
/// names, emails, search text, job details or any other personal data.
/// To add an event (e.g. for the paywall), add a case, its name and its
/// parameters below.
enum AnalyticsEvent: Equatable {
    case appOpened
    case guestContinued
    case signInCompleted(provider: Provider)
    case signOut
    case accountDeleted
    case resumeUploaded(account: Account)
    case resumeOptimized(scoreBefore: Int, scoreAfter: Int)
    /// Defined for the "Do you have these skills?" step; not logged while
    /// that step isn't in the app
    case skillConfirmed
    case resumeDownloaded(source: DownloadSource)
    case resumeSetActive
    case jobsViewed(tab: JobsTabName)
    case jobSearch(queryLength: Int)
    case jobFilterUsed(filter: JobFilter)
    case jobDetailViewed
    case jobSaved
    case jobUnsaved
    case applyTapped(source: ApplySource)
    case applicationMarkedApplied(source: AppliedSource)
    case trackerStatusChanged(newStatus: ApplicationStatus)
    case limitReached(limit: Limit)
    case errorShown(screen: Screen, type: ErrorKind)

    enum Provider: String { case apple, google, other }
    enum Account: String { case guest, signedIn = "signed_in" }
    enum DownloadSource: String { case optimize, savedResumes = "saved_resumes" }
    enum JobsTabName: String { case forYou = "for_you", allJobs = "all_jobs" }
    enum JobFilter: String { case sort }
    enum ApplySource: String { case jobDetail = "job_detail", trackerDetail = "tracker_detail", optimizedResume = "optimized_resume" }
    enum AppliedSource: String { case prompt, tracker }
    enum Limit: String {
        case savedResumes = "saved_resumes"
        case tailoredVersions = "tailored_versions"
        case aiUsage = "ai_usage"
        case jobMatching = "job_matching"
        case requests
    }
    enum Screen: String {
        case signIn = "sign_in", account, upload, forYou = "for_you", allJobs = "all_jobs", search
        case optimize, savedResumes = "saved_resumes", tracker
    }

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .guestContinued: "guest_continued"
        case .signInCompleted: "sign_in_completed"
        case .signOut: "sign_out"
        case .accountDeleted: "account_deleted"
        case .resumeUploaded: "resume_uploaded"
        case .resumeOptimized: "resume_optimized"
        case .skillConfirmed: "skill_confirmed"
        case .resumeDownloaded: "resume_downloaded"
        case .resumeSetActive: "resume_set_active"
        case .jobsViewed: "jobs_viewed"
        case .jobSearch: "job_search"
        case .jobFilterUsed: "job_filter_used"
        case .jobDetailViewed: "job_detail_viewed"
        case .jobSaved: "job_saved"
        case .jobUnsaved: "job_unsaved"
        case .applyTapped: "apply_tapped"
        case .applicationMarkedApplied: "application_marked_applied"
        case .trackerStatusChanged: "tracker_status_changed"
        case .limitReached: "limit_reached"
        case .errorShown: "error_shown"
        }
    }

    /// Values are only these enums' raw values (String) or Int.
    var parameters: [String: AnyHashable] {
        switch self {
        case .signInCompleted(let provider): ["provider": provider.rawValue]
        case .resumeUploaded(let account): ["account": account.rawValue]
        case .resumeOptimized(let before, let after): ["score_before": before, "score_after": after]
        case .resumeDownloaded(let source): ["source": source.rawValue]
        case .jobsViewed(let tab): ["tab": tab.rawValue]
        case .jobSearch(let length): ["query_length": length]
        case .jobFilterUsed(let filter): ["filter": filter.rawValue]
        case .applyTapped(let source): ["source": source.rawValue]
        case .applicationMarkedApplied(let source): ["source": source.rawValue]
        case .trackerStatusChanged(let status): ["new_status": status.rawValue]
        case .limitReached(let limit): ["limit": limit.rawValue]
        case .errorShown(let screen, let type): ["screen": screen.rawValue, "error_type": type.rawValue]
        default: [:]
        }
    }
}

extension AnalyticsEvent.Provider {
    init(_ provider: String?) {
        self = Self(rawValue: provider ?? "") ?? .other
    }
}

// MARK: - Error Kinds

/// What kind of error a user saw, without its message.
enum ErrorKind: String {
    case offline, timeout, server, invalidPDF = "invalid_pdf", limit, unknown

    init(_ error: Error) {
        if error is ResumeSaveError {
            self = .limit
            return
        }
        switch error {
        case JobAPIError.offline: self = .offline
        case JobAPIError.timedOut: self = .timeout
        case JobAPIError.server, JobAPIError.invalidResponse: self = .server
        default:
            switch (error as? URLError)?.code {
            case .notConnectedToInternet?, .networkConnectionLost?, .dataNotAllowed?: self = .offline
            case .timedOut?: self = .timeout
            case .some: self = .server
            case nil: self = .unknown
            }
        }
    }
}

// MARK: - Telemetry

/// Firebase Analytics and Crashlytics behind one switch. Without
/// GoogleService-Info.plist (it's kept out of Git) nothing is configured
/// and every call does nothing; nothing here can fail the app.
enum Telemetry {

    private(set) static var isEnabled = false

    /// Call once, at launch.
    static func configure() {
        guard !isEnabled,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil,
              // Unit tests never send data
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        FirebaseApp.configure()
        isEnabled = true
    }

    static func log(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        let parameters = event.parameters
        Analytics.logEvent(event.name, parameters: parameters.isEmpty ? nil : parameters)
    }

    /// Crash reports carry the signed-in user's Supabase id (never an email
    /// or name); nil clears it (sign-out, account deleted).
    static func setUser(_ id: UUID?) {
        guard isEnabled else { return }
        Crashlytics.crashlytics().setUserID(id?.uuidString.lowercased() ?? "")
    }
}
