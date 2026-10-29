import SwiftUI
import Combine

// MARK: - App Router

enum AppTab: Hashable, CaseIterable {
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

    /// Changing a tab's id rebuilds its navigation stack, i.e. pops it to
    /// its first screen.
    @Published private(set) var stackIDs: [AppTab: UUID] = [:]

    func stackID(_ tab: AppTab) -> UUID {
        stackIDs[tab] ?? Self.defaultID
    }

    private static let defaultID = UUID()

    func popToRoot(_ tab: AppTab) {
        stackIDs[tab] = UUID()
    }

    /// Switches tab and shows that tab's first screen.
    func show(_ tab: AppTab) {
        popToRoot(tab)
        self.tab = tab
    }

    /// Fresh navigation for a new session.
    func reset(for phase: AppSession.Phase) {
        stackIDs = [:]
        trackerFilter = nil
        jobsTab = .forYou
        tab = phase == .signedIn ? .home : .resume
    }
}

// MARK: - Root Tab View

struct RootTabView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: AppSession
    @StateObject private var network = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        tabs
            .modifier(TrackerLifecycle(scenePhase: scenePhase, isConnected: network.isConnected))
            .modifier(ApplyPrompt())
    }

    /// Tapping the current tab goes back to its first screen. Guests tapping
    /// Tracker get the sign-in sheet and stay where they are.
    private var selection: Binding<AppTab> {
        Binding(
            get: { router.tab },
            set: { newTab in
                if newTab == .tracker && session.isGuest {
                    session.requireAccount(.tracker)
                } else if newTab == router.tab {
                    router.popToRoot(newTab)
                } else {
                    router.tab = newTab
                }
            }
        )
    }

    private var tabs: some View {
        TabView(selection: selection) {
            if session.isSignedIn {
                NavigationStack {
                    HomeView()
                }
                .id(router.stackID(.home))
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            }

            if session.isGuest {
                resumeTab
            }

            NavigationStack {
                JobListView(country: router.country, selectedTab: $router.jobsTab)
            }
            .id(router.stackID(.jobs))
            .tabItem { Label("Jobs", systemImage: "briefcase.fill") }
            .tag(AppTab.jobs)

            NavigationStack {
                TrackerView()
            }
            .id(router.stackID(.tracker))
            .tabItem {
                Label("Tracker", systemImage: session.isGuest ? "lock.fill" : "checklist")
            }
            .tag(AppTab.tracker)

            if session.isSignedIn {
                resumeTab
            }
        }
        .tint(AppTheme.lavender)
        .preferredColorScheme(.dark)
    }

    private var resumeTab: some View {
        NavigationStack {
            UploadResumeView()
        }
        .id(router.stackID(.resume))
        .tabItem { Label("Resume", systemImage: "doc.text.fill") }
        .tag(AppTab.resume)
    }
}

// MARK: - Tracker Lifecycle

/// Syncs the tracker when the app comes back or the connection returns, and
/// asks "Did you apply?" after an external apply link.
private struct TrackerLifecycle: ViewModifier {

    let scenePhase: ScenePhase
    let isConnected: Bool

    @EnvironmentObject private var tracker: TrackerStore

    func body(content: Content) -> some View {
        content
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

// MARK: - Apply Prompt

/// "Did you apply to [Company]?" after returning from an apply link.
private struct ApplyPrompt: ViewModifier {

    @EnvironmentObject private var tracker: TrackerStore

    func body(content: Content) -> some View {
        content
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
