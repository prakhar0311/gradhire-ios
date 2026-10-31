//
//  GradHireTests.swift
//  GradHireTests
//
//  Created by Prakhar Ghirnikar on 27/01/26.
//

import Foundation
import Testing
@testable import GradHire

// MARK: - Test Doubles

/// No network: every server call fails as if offline.
private struct OfflineApplications: ApplicationRepository {
    func fetchApplications() async throws -> [ApplicationRecord] { throw URLError(.notConnectedToInternet) }
    func createApplication(_ application: NewApplication) async throws -> ApplicationRecord { throw URLError(.notConnectedToInternet) }
    func updateApplication(id: UUID, changes: ApplicationChanges) async throws -> ApplicationRecord { throw URLError(.notConnectedToInternet) }
    func deleteApplication(id: UUID) async throws { throw URLError(.notConnectedToInternet) }
    func upsertApplication(_ application: ApplicationUpsert) async throws -> ApplicationRecord { throw URLError(.notConnectedToInternet) }
    func deleteApplication(userId: UUID, jobId: UUID) async throws { throw URLError(.notConnectedToInternet) }
    func ensureJob(id: UUID, snapshot: JobSnapshot) async throws { throw URLError(.notConnectedToInternet) }
    func fetchEvents(applicationId: UUID) async throws -> [ApplicationEventRecord] { [] }
}

/// An account with fixed saved resumes and limits.
private struct FixedResumes: ResumeRepository {
    var list: [SavedResumeRecord]
    var limits = ResumeLimits.standard

    func fetchResumes() async throws -> [ResumeRecord] { [] }
    func fetchResumeList() async throws -> [SavedResumeRecord] { list }
    func fetchResumeText(id: UUID) async throws -> String? { "Resume text" }
    func createResume(_ resume: NewResume) async throws -> ResumeRecord { throw URLError(.notConnectedToInternet) }
    func renameResume(id: UUID, title: String) async throws {}
    func deleteResume(id: UUID) async throws {}
    func fetchActiveResumeId(userId: UUID) async throws -> UUID? { list.first?.id }
    func setActiveResumeId(_ id: UUID?, userId: UUID) async throws {}
    func fetchLimits() async throws -> ResumeLimits { limits }
    func uploadResumeFile(_ data: Data, fileName: String) async throws -> String { "user/\(fileName)" }
    func signedURL(forPath path: String, expiresIn seconds: Int) async throws -> URL { URL(string: "https://example.com")! }
    func downloadResumeFile(atPath path: String) async throws -> Data { Data() }
    func deleteResumeFile(atPath path: String) async throws {}
    func fetchMatches(resumeId: UUID) async throws -> [JobMatchRecord] { [] }
    func fetchStoredMatches(resumeId: UUID) async throws -> [StoredMatchRecord] { [] }
}

private func job(_ title: String = "iOS Developer") -> Job {
    Job(id: UUID(), title: title, company: "Example", location: "Pune", description: "Build apps in Swift.",
        matchScore: nil, applyURL: "https://www.adzuna.in/details/1", postedAt: nil, contractTime: nil)
}

private func original(_ title: String, daysAgo: Double = 0) -> SavedResumeRecord {
    SavedResumeRecord(id: UUID(), kind: .original, parentResumeId: nil, title: title, filePath: nil,
                      readinessScore: nil, createdAt: Date().addingTimeInterval(-daysAgo * 86_400))
}

// MARK: - Badge / Status Mapping

@MainActor
struct StatusTests {

    @Test func everyStatusHasItsOwnTitleAndColor() {
        let titles = ApplicationStatus.allCases.map(\.title)
        #expect(titles == ["Saved", "Applied", "Interviewing", "Offer", "Rejected"])
        #expect(Set(ApplicationStatus.allCases.map { "\($0.color)" }).count == ApplicationStatus.allCases.count)
    }

    @Test func appliedMeansAppliedOrLater() {
        #expect(!ApplicationStatus.saved.hasApplied)
        #expect(ApplicationStatus.applied.hasApplied)
        #expect(ApplicationStatus.interviewing.hasApplied)
        #expect(ApplicationStatus.offer.hasApplied)
        #expect(!ApplicationStatus.rejected.hasApplied)
    }

    /// The badge on job cards reads tracker.status(for:): it must follow
    /// every change, and only a job past Saved asks before removing.
    @Test func trackerStatusFollowsChanges() {
        let tracker = TrackerStore(repository: OfflineApplications())
        tracker.authChanged(.signedIn(AuthUser(id: UUID(), email: nil, name: "Test", provider: "email")))
        defer { tracker.authChanged(.signedOut) }

        let saved = job()
        tracker.toggleSave(saved)
        #expect(tracker.status(for: saved.id) == .saved)
        #expect(!tracker.needsRemoveConfirmation(saved.id))

        for status in [ApplicationStatus.applied, .interviewing, .offer, .rejected] {
            tracker.setStatus(status, for: saved.id)
            #expect(tracker.status(for: saved.id) == status)
            #expect(tracker.needsRemoveConfirmation(saved.id))
        }

        tracker.remove(saved.id)
        #expect(tracker.status(for: saved.id) == nil)
    }

    @Test func guestsCannotTrackJobs() {
        let tracker = TrackerStore(repository: OfflineApplications())
        let wanted = job()
        tracker.toggleSave(wanted)
        #expect(tracker.status(for: wanted.id) == nil)
        #expect(tracker.signInPromptJob == wanted)
    }
}

// MARK: - Guest vs Signed In

@MainActor
struct SessionStateTests {

    @Test func guestResumeLivesInMemoryOnly() {
        let manager = ResumeManager()
        #expect(manager.availability == .none)

        manager.replace(pdfData: Data("pdf".utf8), text: "Resume", fileName: "Me.pdf")
        #expect(manager.availability == .available)
        #expect(manager.accountResumeId(for: UUID()) == nil)

        // Signing in carries the guest's upload over (to be saved)
        #expect(manager.signedIn(userId: UUID()))
        manager.signedOut()
        #expect(manager.availability == .none)
        #expect(manager.pdfData == nil)
        #expect(manager.resumeText == nil)
    }

    @Test func guestRecentSearchesAreNeverStored() {
        let search = JobSearchViewModel()
        let before = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("recent_searches_v1_") }
        search.text = "Swift"
        search.submit()
        #expect(search.recentSearches == ["Swift"])
        let after = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("recent_searches_v1_") }
        #expect(Set(before) == Set(after))
        search.signedOut()
        #expect(search.recentSearches.isEmpty)
    }

    @Test func signedInRecentSearchesAreRemovedOnSignOut() {
        let search = JobSearchViewModel()
        let user = UUID()
        search.signedIn(userId: user)
        search.text = "Python"
        search.submit()
        let key = "recent_searches_v1_" + user.uuidString
        #expect(UserDefaults.standard.stringArray(forKey: key) == ["Python"])
        search.signedOut()
        #expect(UserDefaults.standard.stringArray(forKey: key) == nil)
    }
}

// MARK: - Resume Limits

@MainActor
struct ResumeLimitTests {

    @Test func atTheLimitSavingIsRefusedBeforeUploading() async {
        let repository = FixedResumes(list: [original("A"), original("B", daysAgo: 1), original("C", daysAgo: 2)])
        let manager = ResumeManager(resumes: repository)
        _ = manager.signedIn(userId: UUID())
        await manager.reloadAccount()

        #expect(manager.originalCount == 3)
        #expect(manager.isAtOriginalLimit)
        await #expect(throws: ResumeSaveError.originalLimit) {
            try await manager.saveNewOriginal(pdfData: Data("pdf".utf8), text: "Resume", fileName: "New.pdf")
        }
        manager.signedOut()
    }

    @Test func belowTheLimitIsAllowed() async {
        let manager = ResumeManager(resumes: FixedResumes(list: [original("A")]))
        _ = manager.signedIn(userId: UUID())
        await manager.reloadAccount()
        #expect(!manager.isAtOriginalLimit)
        #expect(manager.activeResume?.title == "A")
        manager.signedOut()
    }

    @Test func serverLimitErrorsMapToFriendlyCases() {
        #expect(ResumeSaveError.from(NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "RESUME_LIMIT_ORIGINAL"])) == .originalLimit)
        #expect(ResumeSaveError.from(NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "RESUME_LIMIT_VERSION"])) == .versionLimit)
        #expect(ResumeSaveError.from(URLError(.timedOut)) == nil)
    }
}

// MARK: - Input Checks

@MainActor
struct InputTests {

    @Test func searchQueriesAreCleanedLikeTheServer() {
        #expect(JobSearchViewModel.clean("  iOS   developer ") == "iOS developer")
        #expect(JobSearchViewModel.clean("C++") == "C++")
        #expect(JobSearchViewModel.clean("<script>") == "script")
        #expect(JobSearchViewModel.clean("a") == nil)
        #expect(JobSearchViewModel.clean(String(repeating: "x", count: 150))?.count == 100)
    }

    @Test func onlyCompleteWebLinksCanBeOpened() {
        #expect(ApplyLinkButton<EmptyLabel>.applyURL("https://www.adzuna.in/details/1") != nil)
        #expect(ApplyLinkButton<EmptyLabel>.applyURL("  https://example.com/job  ") != nil)
        #expect(ApplyLinkButton<EmptyLabel>.applyURL("") == nil)
        #expect(ApplyLinkButton<EmptyLabel>.applyURL("not a url") == nil)
        #expect(ApplyLinkButton<EmptyLabel>.applyURL("javascript:alert(1)") == nil)
        #expect(ApplyLinkButton<EmptyLabel>.applyURL("https://") == nil)
    }
}

import SwiftUI
private typealias EmptyLabel = EmptyView
