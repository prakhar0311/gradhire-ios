import SwiftUI
import Combine

// MARK: - App Router

enum AppTab: Hashable {
    case home
    case jobs
    case tracker
    case resume
}

/// App-wide navigation state, so any screen can switch tabs (e.g. "Browse
/// jobs" in the tracker, "Find jobs" after uploading a resume).
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var jobsTab: JobsTab = .forYou
    @Published var trackerFilter: ApplicationStatus?
    @Published var country = "in"
}

// MARK: - Root Tab View

struct RootTabView: View {

    @EnvironmentObject private var router: AppRouter
    @StateObject private var network = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        tabs
            .modifier(TrackerLifecycle(scenePhase: scenePhase, isConnected: network.isConnected))
            .modifier(TrackerPrompts())
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                JobListView(country: router.country, selectedTab: $router.jobsTab)
            }
            .tabItem { Label("Jobs", systemImage: "briefcase.fill") }
            .tag(AppTab.jobs)

            NavigationStack {
                TrackerView()
            }
            .tabItem { Label("Tracker", systemImage: "checklist") }
            .tag(AppTab.tracker)

            NavigationStack {
                UploadResumeView()
            }
            .tabItem { Label("Resume", systemImage: "doc.text.fill") }
            .tag(AppTab.resume)
        }
        .tint(Color(red: 0.65, green: 0.55, blue: 0.98))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tracker Lifecycle

/// Keeps the tracker cache in step with who is signed in, and syncs when the
/// app comes back or the connection returns.
private struct TrackerLifecycle: ViewModifier {

    let scenePhase: ScenePhase
    let isConnected: Bool

    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var dashboard: DashboardViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var matchedJobs: MatchedJobsViewModel
    @EnvironmentObject private var router: AppRouter

    func body(content: Content) -> some View {
        content
            .task {
                tracker.authChanged(auth.state)
                dashboard.authChanged(auth.state)
                // The resume kept on this device: match it again at launch
                if let url = resumeManager.resumeURL, !matchedJobs.hasResume {
                    matchedJobs.load(resumeURL: url, country: router.country)
                }
            }
            .onChange(of: auth.state) { _, state in
                tracker.authChanged(state)
                dashboard.authChanged(state)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                tracker.checkApplyPrompt(fromForeground: true)
                tracker.scheduleSync(after: 0)
            }
            .onChange(of: isConnected) { _, isConnected in
                if isConnected { tracker.scheduleSync(after: 0) }
            }
    }
}

// MARK: - Tracker Prompts

/// Sign-in for guests who tap bookmark, and "Did you apply?" after an apply
/// link.
private struct TrackerPrompts: ViewModifier {

    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var resumeManager: ResumeManager

    @State private var showSignInPrompt = false

    func body(content: Content) -> some View {
        content
            // Guest tapped a bookmark: sign in, then the save completes
            .onChange(of: tracker.signInPromptJob) { _, job in
                if job != nil { showSignInPrompt = true }
            }
            .sheet(isPresented: $showSignInPrompt, onDismiss: {
                // Closed without signing in: forget the pending save
                if !tracker.isSignedIn { tracker.signInPromptJob = nil }
            }) {
                AccountView(reason: "Sign in to track your applications", dismissOnSignIn: true)
                    .environmentObject(auth)
                    .environmentObject(resumeManager)
                    .environmentObject(tracker)
            }
            .alert(
                tracker.applyPrompt.map { "Did you apply to \($0.company)?" } ?? "",
                isPresented: Binding(
                    get: { tracker.applyPrompt != nil },
                    set: { if !$0 { tracker.applyPrompt = nil } }
                ),
                presenting: tracker.applyPrompt
            ) { job in
                Button("Yes") { tracker.answerApplyPrompt(job, applied: true) }
                Button("Not yet", role: .cancel) { tracker.answerApplyPrompt(job, applied: false) }
            } message: { job in
                Text("We'll mark \(job.title) as Applied in your tracker.")
            }
    }
}
