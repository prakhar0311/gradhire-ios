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

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                UploadResumeView()
            }
            .environmentObject(bookmarks)
            .environmentObject(resumeManager) // ✅ ADD
        }
    }
}




