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

/// The resume the user is working with. It's kept on this device only (in
/// the app's private, encrypted Application Support folder) so matches and
/// the dashboard survive a relaunch. It reaches the user's account only if
/// they choose to save it; `accountResumeId` then links the two.
final class ResumeManager: ObservableObject {

    @Published var resumeURL: URL? = nil
    @Published var resumeText: String?
    @Published private(set) var fileName: String?
    @Published private(set) var uploadedAt: Date?

    /// The saved copy in the signed-in user's account (resumes.id), if any.
    @Published private(set) var accountResumeId: UUID?
    private var accountUserId: UUID?

    private let resumes: (any ResumeRepository)?
    private let applications: (any ApplicationRepository)?

    init(resumes: (any ResumeRepository)? = nil, applications: (any ApplicationRepository)? = nil) {
        self.resumes = resumes
        self.applications = applications
        restore()
    }

    var hasResume: Bool { resumeURL != nil }

    /// The account copy for this user, if the current resume was saved by them.
    func accountResumeId(for userId: UUID?) -> UUID? {
        guard let userId, userId == accountUserId else { return nil }
        return accountResumeId
    }

    // MARK: Local Copy

    /// Keeps a newly uploaded resume on this device, replacing the previous
    /// one. A new resume isn't linked to the account until the user saves it.
    func store(pdfData: Data, text: String, fileName: String) throws -> URL {
        let folder = try Self.folder()
        let pdfURL = folder.appendingPathComponent("resume.pdf")

        try pdfData.write(to: pdfURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try Data(text.utf8).write(
            to: folder.appendingPathComponent("resume.txt"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )

        resumeURL = pdfURL
        resumeText = text
        self.fileName = fileName
        uploadedAt = Date()
        accountResumeId = nil
        accountUserId = nil
        persistMeta()
        return pdfURL
    }

    /// Records that the current resume was saved to this user's account.
    func linkToAccount(resumeId: UUID, userId: UUID) {
        accountResumeId = resumeId
        accountUserId = userId
        persistMeta()
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

    // MARK: Persistence

    private struct Meta: Codable {
        var fileName: String?
        var uploadedAt: Date?
        var accountResumeId: UUID?
        var accountUserId: UUID?
    }

    private static func folder() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = base.appendingPathComponent("Resume", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var mutableFolder = folder
            try? mutableFolder.setResourceValues(values)
        }
        return folder
    }

    private func persistMeta() {
        guard let folder = try? Self.folder() else { return }
        let meta = Meta(fileName: fileName, uploadedAt: uploadedAt, accountResumeId: accountResumeId, accountUserId: accountUserId)
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: folder.appendingPathComponent("meta.json"), options: .atomic)
    }

    private func restore() {
        guard let folder = try? Self.folder() else { return }
        let pdfURL = folder.appendingPathComponent("resume.pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path),
              let text = try? String(contentsOf: folder.appendingPathComponent("resume.txt"), encoding: .utf8),
              !text.isEmpty else { return }

        resumeURL = pdfURL
        resumeText = text

        if let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
           let meta = try? JSONDecoder().decode(Meta.self, from: data) {
            fileName = meta.fileName
            uploadedAt = meta.uploadedAt
            accountResumeId = meta.accountResumeId
            accountUserId = meta.accountUserId
        }
    }
}
