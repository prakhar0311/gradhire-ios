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
    @StateObject private var jobSearch: JobSearchViewModel
    @StateObject private var supabase: SupabaseManager // the app's only Supabase client
    @StateObject private var auth: AuthViewModel
    @StateObject private var tracker: TrackerStore
    @StateObject private var dashboard: DashboardViewModel
    @StateObject private var router: AppRouter
    @StateObject private var session: AppSession // decides Welcome vs guest vs signed in

    init() {
        let supabase = SupabaseManager()
        _supabase = StateObject(wrappedValue: supabase)
        let auth = AuthViewModel(auth: supabase.auth)
        _auth = StateObject(wrappedValue: auth)
        let tracker = TrackerStore(repository: supabase.applications)
        _tracker = StateObject(wrappedValue: tracker)
        let dashboard = DashboardViewModel(repository: supabase.dashboard)
        _dashboard = StateObject(wrappedValue: dashboard)
        let router = AppRouter()
        _router = StateObject(wrappedValue: router)

        let resumeManager = ResumeManager(resumes: supabase.resumes, applications: supabase.applications)
        _resumeManager = StateObject(wrappedValue: resumeManager)

        // Signed-in users: For You reads and refreshes the active resume's stored matches
        let matchedJobs = MatchedJobsViewModel()
        matchedJobs.repository = supabase.resumes
        matchedJobs.accessToken = { await supabase.currentAccess()?.accessToken }
        _matchedJobs = StateObject(wrappedValue: matchedJobs)

        let jobSearch = JobSearchViewModel()
        _jobSearch = StateObject(wrappedValue: jobSearch)

        _session = StateObject(wrappedValue: AppSession(
            auth: auth,
            tracker: tracker,
            dashboard: dashboard,
            resumeManager: resumeManager,
            matchedJobs: matchedJobs,
            search: jobSearch,
            router: router
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(resumeManager)
                .environmentObject(matchedJobs)
                .environmentObject(allJobs)
                .environmentObject(jobSearch)
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




