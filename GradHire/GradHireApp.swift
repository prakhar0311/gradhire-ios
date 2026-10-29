//
//  GradHireApp.swift
//  GradHire
//
//  Created by Prakhar Ghirnikar on 27/01/26.
//
import SwiftUI

@main
struct GradHireApp: App {

    @StateObject private var bookmarks = BookmarkManager()
    @StateObject private var resumeManager = ResumeManager() // ✅ ADD
    @StateObject private var matchedJobs = MatchedJobsViewModel()
    @StateObject private var allJobs = AllJobsViewModel()
    @StateObject private var supabase = SupabaseManager() // the app's only Supabase client

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
            .task { await APIService.shared.warmUpServer() }
            .task { await supabase.logConnectionCheck() }
        }
    }
}




