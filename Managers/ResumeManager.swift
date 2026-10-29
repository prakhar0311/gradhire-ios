//
//  ResumeManager.swift
//  GradHire
//
//  Created by Prakhar Ghirnikar on 09/02/26.
//


import Foundation
import Combine
import Supabase

// MARK: - Resume Manager

/// The resume the user is working with.
///
/// - Guests: kept in memory only, for this session. Nothing is written to
///   disk, so quitting the app forgets it.
/// - Signed-in users: also kept on this device (the app's private, encrypted
///   Application Support folder, per user) so it survives a relaunch, and
///   linked to the copy in their account (`accountResumeId`) once saved.
final class ResumeManager: ObservableObject {

    @Published private(set) var pdfData: Data?
    @Published private(set) var resumeText: String?
    @Published private(set) var fileName: String?
    @Published private(set) var uploadedAt: Date?

    /// The saved copy in the signed-in user's account (resumes.id), if any.
    @Published private(set) var accountResumeId: UUID?
    private var accountUserId: UUID?

    /// Set while signed in; nil means "memory only" (guest).
    private var ownerId: UUID?

    private let resumes: (any ResumeRepository)?
    private let applications: (any ApplicationRepository)?

    init(resumes: (any ResumeRepository)? = nil, applications: (any ApplicationRepository)? = nil) {
        self.resumes = resumes
        self.applications = applications
    }

    var hasResume: Bool { pdfData != nil }

    /// The account copy for this user, if the current resume was saved by them.
    func accountResumeId(for userId: UUID?) -> UUID? {
        guard let userId, userId == accountUserId else { return nil }
        return accountResumeId
    }

    // MARK: Session

    /// Signed in: restores this user's resume from the device, or keeps (and
    /// stores) the one already in memory from the guest session.
    func signedIn(userId: UUID) {
        guard ownerId != userId else { return }
        ownerId = userId
        if hasResume {
            persist()
        } else {
            restore(for: userId)
        }
    }

    /// Signed out (or account deleted): forget the resume and remove every
    /// copy on this device.
    func signedOut() {
        ownerId = nil
        clearMemory()
        Self.removeAllStoredResumes()
    }

    // MARK: Changes

    /// A newly uploaded resume replaces the current one. It isn't linked to
    /// the account until the user saves it.
    func replace(pdfData: Data, text: String, fileName: String) {
        self.pdfData = pdfData
        resumeText = text
        self.fileName = fileName
        uploadedAt = Date()
        accountResumeId = nil
        accountUserId = nil
        persist()
    }

    /// Records that the current resume was saved to this user's account.
    func linkToAccount(resumeId: UUID, userId: UUID) {
        accountResumeId = resumeId
        accountUserId = userId
        persist()
    }

    private func clearMemory() {
        pdfData = nil
        resumeText = nil
        fileName = nil
        uploadedAt = nil
        accountResumeId = nil
        accountUserId = nil
    }

    // MARK: Tailored Versions

    /// Saves an optimized resume as a tailored version of the account copy.
    /// Only for users who saved their resume; never raises.
    func saveTailored(job: Job, text: String, score: Int?, userId: UUID?) async {
        guard let resumes, let parentId = accountResumeId(for: userId), !text.isEmpty else { return }

        var resume = NewResume(kind: .tailored)
        resume.parentResumeId = parentId
        resume.targetJobId = job.id
        resume.title = "Tailored for \(job.company)"
        resume.parsedData = .object(["text": .string(text), "job_title": .string(job.title)])
        resume.readinessScore = score

        do {
            _ = try await resumes.createResume(resume)
        } catch where TrackerError.isMissingJob(error) {
            // The job isn't in the shared table yet; add it and retry once
            guard let applications else { return }
            try? await applications.ensureJob(id: job.id, snapshot: job.snapshot)
            _ = try? await resumes.createResume(resume)
        } catch {
            // Best effort: the optimization itself already succeeded
        }
    }

    // MARK: Device Storage (signed-in users only)

    private struct Meta: Codable {
        var fileName: String?
        var uploadedAt: Date?
        var accountResumeId: UUID?
        var accountUserId: UUID?
    }

    /// Application Support/Resume, excluded from backups.
    static func rootFolder() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return base.appendingPathComponent("Resume", isDirectory: true)
    }

    private static func folder(for userId: UUID) -> URL? {
        guard var root = rootFolder() else { return nil }
        if !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? root.setResourceValues(values)
        }
        let folder = root.appendingPathComponent(userId.uuidString.lowercased(), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func removeAllStoredResumes() {
        guard let root = rootFolder() else { return }
        try? FileManager.default.removeItem(at: root)
    }

    private func persist() {
        // Guests: never written to disk
        guard let ownerId, let pdfData, let resumeText, let folder = Self.folder(for: ownerId) else { return }
        let protection: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

        try? pdfData.write(to: folder.appendingPathComponent("resume.pdf"), options: protection)
        try? Data(resumeText.utf8).write(to: folder.appendingPathComponent("resume.txt"), options: protection)

        let meta = Meta(fileName: fileName, uploadedAt: uploadedAt, accountResumeId: accountResumeId, accountUserId: accountUserId)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: folder.appendingPathComponent("meta.json"), options: protection)
        }
    }

    private func restore(for userId: UUID) {
        guard let folder = Self.folder(for: userId),
              let data = try? Data(contentsOf: folder.appendingPathComponent("resume.pdf")),
              let text = try? String(contentsOf: folder.appendingPathComponent("resume.txt"), encoding: .utf8),
              !text.isEmpty else { return }

        pdfData = data
        resumeText = text

        if let metaData = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
           let meta = try? JSONDecoder().decode(Meta.self, from: metaData) {
            fileName = meta.fileName
            uploadedAt = meta.uploadedAt
            accountResumeId = meta.accountResumeId
            accountUserId = meta.accountUserId
        }
    }
}
