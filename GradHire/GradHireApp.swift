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

    @StateObject private var resumeManager = ResumeManager()
    @StateObject private var matchedJobs = MatchedJobsViewModel()
    @StateObject private var allJobs = AllJobsViewModel()
    @StateObject private var supabase: SupabaseManager // the app's only Supabase client
    @StateObject private var auth: AuthViewModel
    @StateObject private var tracker: TrackerStore
    @StateObject private var router = AppRouter()

    init() {
        let supabase = SupabaseManager()
        _supabase = StateObject(wrappedValue: supabase)
        _auth = StateObject(wrappedValue: AuthViewModel(auth: supabase.auth, resumes: supabase.resumes))
        _tracker = StateObject(wrappedValue: TrackerStore(repository: supabase.applications))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(resumeManager)
                .environmentObject(matchedJobs)
                .environmentObject(allJobs)
                .environmentObject(supabase)
                .environmentObject(auth)
                .environmentObject(tracker)
                .environmentObject(router)
                .task { await APIService.shared.warmUpServer() }
                .task { await supabase.logConnectionCheck() }
                .task { auth.start() }
                // Google Sign-In returns to the app through its URL scheme
                .onOpenURL { url in GoogleSignInHelper.handle(url) }
        }
    }
}




