//
//  GradHireApp.swift
//  GradHire
//
//  Created by Prakhar Ghirnikar on 27/01/26.
//
import SwiftUI
import GoogleSignIn

@main
struct GradHireApp: App {

    @StateObject private var resumeManager: ResumeManager
    @StateObject private var matchedJobs: MatchedJobsViewModel
    @StateObject private var allJobs = AllJobsViewModel()
    @StateObject private var supabase: SupabaseManager // the app's only Supabase client
    @StateObject private var auth: AuthViewModel
    @StateObject private var tracker: TrackerStore
    @StateObject private var dashboard: DashboardViewModel
    @StateObject private var router: AppRouter
    @StateObject private var session: AppSession // decides Welcome vs guest vs signed in

    init() {
        let supabase = SupabaseManager()
        _supabase = StateObject(wrappedValue: supabase)
        let auth = AuthViewModel(auth: supabase.auth, resumes: supabase.resumes)
        _auth = StateObject(wrappedValue: auth)
        let tracker = TrackerStore(repository: supabase.applications)
        _tracker = StateObject(wrappedValue: tracker)
        let dashboard = DashboardViewModel(repository: supabase.dashboard)
        _dashboard = StateObject(wrappedValue: dashboard)
        let router = AppRouter()
        _router = StateObject(wrappedValue: router)

        let resumeManager = ResumeManager(resumes: supabase.resumes, applications: supabase.applications)
        _resumeManager = StateObject(wrappedValue: resumeManager)

        // Signed-in users with a saved resume: matching also stores the matches
        let matchedJobs = MatchedJobsViewModel()
        matchedJobs.accountContext = { [weak resumeManager] in
            guard let access = await supabase.currentAccess(),
                  let resumeId = resumeManager?.accountResumeId(for: access.userId) else { return nil }
            return (resumeId, access.accessToken)
        }
        _matchedJobs = StateObject(wrappedValue: matchedJobs)

        _session = StateObject(wrappedValue: AppSession(
            auth: auth,
            tracker: tracker,
            dashboard: dashboard,
            resumeManager: resumeManager,
            matchedJobs: matchedJobs,
            router: router
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(resumeManager)
                .environmentObject(matchedJobs)
                .environmentObject(allJobs)
                .environmentObject(supabase)
                .environmentObject(auth)
                .environmentObject(tracker)
                .environmentObject(dashboard)
                .environmentObject(router)
                .environmentObject(session)
                .task { await APIService.shared.warmUpServer() }
                .task { await supabase.logConnectionCheck() }
                .task { await session.start() }
                // Google Sign-In returns to the app through its URL scheme
                .onOpenURL { url in GoogleSignInHelper.handle(url) }
        }
    }
}




