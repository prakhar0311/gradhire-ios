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

    @StateObject private var bookmarks = BookmarkManager()
    @StateObject private var resumeManager = ResumeManager() // ✅ ADD
    @StateObject private var matchedJobs = MatchedJobsViewModel()
    @StateObject private var allJobs = AllJobsViewModel()
    @StateObject private var supabase: SupabaseManager // the app's only Supabase client
    @StateObject private var auth: AuthViewModel

    init() {
        let supabase = SupabaseManager()
        _supabase = StateObject(wrappedValue: supabase)
        _auth = StateObject(wrappedValue: AuthViewModel(auth: supabase.auth, resumes: supabase.resumes))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                UploadResumeView()
            }
            .environmentObject(bookmarks)
            .environmentObject(resumeManager) // ✅ ADD
            .environmentObject(matchedJobs)
            .environmentObject(allJobs)
            .environmentObject(supabase)
            .environmentObject(auth)
            .task { await APIService.shared.warmUpServer() }
            .task { await supabase.logConnectionCheck() }
            .task { auth.start() }
            // Google Sign-In returns to the app through its URL scheme
            .onOpenURL { url in GoogleSignInHelper.handle(url) }
        }
    }
}




