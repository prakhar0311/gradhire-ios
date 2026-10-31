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

/// The one place that decides which resume the app works with.
///
/// - Guests: the resume they uploaded, kept in memory only for this session.
///   Nothing is written to disk, so quitting the app forgets it.
/// - Signed-in users: their ACTIVE resume, chosen from the resumes saved to
///   their account (profiles.active_resume_id; by default the newest
///   original). For You, Home, Optimize and the saved-resumes list all read
///   it from here. The active resume and the list are also kept on this device
///   (the app's private Application Support folder, per user) so they show
///   at once on relaunch; everything is removed on sign-out.
final class ResumeManager: ObservableObject {

    enum Availability: Equatable {
        /// No resume yet (guests), or none saved to the account
        case none
        /// Signed in, still finding out which resume is active
        case loading
        case available
        /// Signed in, the account couldn't be read and nothing is cached
        case failed
    }

    enum AccountStatus: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    // The active resume's content (or a guest's upload)
    @Published private(set) var pdfData: Data?
    @Published private(set) var resumeText: String?
    @Published private(set) var fileName: String?
    @Published private(set) var uploadedAt: Date?

    // The signed-in user's saved resumes
    @Published private(set) var savedResumes: [SavedResume] = []
    @Published private(set) var activeResumeId: UUID?
    @Published private(set) var limits: ResumeLimits = .standard
    @Published private(set) var accountStatus: AccountStatus = .idle
    @Published private(set) var saveStatus: SaveStatus = .idle

    /// Set while signed in; nil means "memory only" (guest).
    private var ownerId: UUID?
    /// Which saved resume pdfData/resumeText belong to (nil: not loaded, or
    /// an upload that isn't saved yet).
    private var contentResumeId: UUID?
    /// A guest's resume, kept after signing in until it's saved to the account.
    private var hasUnsavedUpload = false
    private var refreshTask: Task<Void, Never>?

    private let resumes: (any ResumeRepository)?
    private let applications: (any ApplicationRepository)?

    init(resumes: (any ResumeRepository)? = nil, applications: (any ApplicationRepository)? = nil) {
        self.resumes = resumes
        self.applications = applications
    }

    // MARK: State

    var hasResume: Bool { pdfData != nil || activeResumeId != nil }

    var availability: Availability {
        guard ownerId != nil else { return pdfData != nil ? .available : .none }
        if activeResumeId != nil || hasUnsavedUpload { return .available }
        switch accountStatus {
        case .loaded:         return .none
        case .failed:         return .failed
        case .idle, .loading: return .loading
        }
    }

    var activeResume: SavedResume? {
        guard let activeResumeId else { return nil }
        return savedResumes.first { $0.id == activeResumeId }
    }

    /// The active resume, for this user.
    func accountResumeId(for userId: UUID?) -> UUID? {
        guard let userId, userId == ownerId else { return nil }
        return activeResumeId
    }

    var originalCount: Int { savedResumes.filter { $0.kind == .original }.count }
    var versionCount: Int { savedResumes.filter(\.isVersion).count }
    var isAtOriginalLimit: Bool { originalCount >= limits.maxOriginals }
    var isAtVersionLimit: Bool { versionCount >= limits.maxVersions }

    /// The version replaced when tailoring at the limit.
    var oldestVersion: SavedResume? {
        savedResumes.filter(\.isVersion).min { $0.createdAt < $1.createdAt }
    }

    /// Originals (newest first), each with its versions; versions whose
    /// original is gone come last, on their own.
    var resumeGroups: [SavedResumeGroup] {
        let originals = savedResumes.filter { $0.kind == .original }
        let originalIds = Set(originals.map(\.id))
        let versions = savedResumes.filter(\.isVersion)

        var groups = originals.map { original in
            SavedResumeGroup(
                original: original,
                versions: versions.filter { $0.parentResumeId == original.id }
            )
        }
        for version in versions where version.parentResumeId.map({ !originalIds.contains($0) }) ?? true {
            groups.append(SavedResumeGroup(original: nil, versions: [version]))
        }
        return groups
    }

    // MARK: Session

    /// Signed in: shows this user's cached resumes at once, then loads the
    /// account. Returns true when a guest's upload is waiting to be saved to
    /// the account (the caller saves it with `saveUnsavedUpload()`).
    @discardableResult
    func signedIn(userId: UUID) -> Bool {
        guard ownerId != userId else { return false }
        let carriesGuestUpload = ownerId == nil && pdfData != nil
        ownerId = userId
        accountStatus = .idle

        if carriesGuestUpload {
            hasUnsavedUpload = true
            contentResumeId = nil
        } else {
            restore(for: userId)
            refreshAccount()
        }
        return carriesGuestUpload
    }

    /// Signed out (or account deleted): forget everything and remove every
    /// copy on this device.
    func signedOut() {
        refreshTask?.cancel()
        refreshTask = nil
        ownerId = nil
        clearContent()
        savedResumes = []
        activeResumeId = nil
        limits = .standard
        accountStatus = .idle
        saveStatus = .idle
        hasUnsavedUpload = false
        Self.removeAllStoredResumes()
    }

    /// Reloads the list, the active resume and the limits.
    func refreshAccount() {
        refreshTask?.cancel()
        refreshTask = Task { await loadAccount() }
    }

    func reloadAccount() async {
        refreshTask?.cancel()
        await loadAccount()
    }

    private func loadAccount() async {
        guard let resumes, let owner = ownerId else { return }
        if accountStatus != .loaded { accountStatus = .loading }

        do {
            async let listTask = resumes.fetchResumeList()
            async let activeTask = resumes.fetchActiveResumeId(userId: owner)
            async let limitsTask = try? resumes.fetchLimits()
            let (list, serverActive, serverLimits) = try await (listTask, activeTask, limitsTask)
            guard ownerId == owner, !Task.isCancelled else { return }

            savedResumes = list.map(SavedResume.init(record:))
            if let serverLimits { limits = serverLimits }

            // The stored choice, else the newest original
            let active = serverActive.flatMap { id in savedResumes.first { $0.id == id } }
                ?? savedResumes.first { $0.kind == .original }
            if active?.id != serverActive {
                try? await resumes.setActiveResumeId(active?.id, userId: owner)
            }
            guard ownerId == owner else { return }

            activeResumeId = active?.id
            if active == nil, !hasUnsavedUpload { clearContent() }
            accountStatus = .loaded
            persist()

            await loadActiveContent()
        } catch {
            guard ownerId == owner, !Task.isCancelled else { return }
            accountStatus = .failed
        }
    }

    /// Loads the active resume's text and PDF (once per resume).
    private func loadActiveContent() async {
        guard let resumes, let owner = ownerId, !hasUnsavedUpload,
              let active = activeResume, contentResumeId != active.id else { return }

        // A tailored version without its own PDF uses its original's
        let parent = active.parentResumeId.flatMap { id in savedResumes.first { $0.id == id } }
        let path = active.filePath ?? parent?.filePath

        async let textTask = try? resumes.fetchResumeText(id: active.id)
        async let pdfTask: Data? = {
            guard let path else { return nil }
            return try? await resumes.downloadResumeFile(atPath: path)
        }()
        let (text, pdf) = await (textTask, pdfTask)
        guard ownerId == owner, activeResumeId == active.id else { return }

        resumeText = text ?? nil
        pdfData = pdf
        fileName = active.displayTitle
        uploadedAt = active.createdAt
        contentResumeId = active.id
        persist()
    }

    // MARK: Guest Upload

    /// A newly uploaded resume, for guests (memory only).
    func replace(pdfData: Data, text: String, fileName: String) {
        self.pdfData = pdfData
        resumeText = text
        self.fileName = fileName
        uploadedAt = Date()
        contentResumeId = nil
    }

    /// Saves the resume a guest uploaded before signing in. If it can't be
    /// saved, the account's active resume takes over.
    func saveUnsavedUpload() async throws {
        guard hasUnsavedUpload, let data = pdfData, let text = resumeText else { return }
        await loadAccount()

        do {
            hasUnsavedUpload = false
            try await saveNewOriginal(pdfData: data, text: text, fileName: fileName ?? "My resume")
        } catch {
            contentResumeId = nil
            clearContent()
            await loadActiveContent()
            throw error
        }
    }

    // MARK: Saving

    /// Uploads a new original resume to the account and makes it active.
    /// Throws `ResumeSaveError.originalLimit` at the limit (checked here for
    /// a friendly message, and again by the database).
    func saveNewOriginal(pdfData data: Data, text: String, fileName: String) async throws {
        guard let resumes, let owner = ownerId else { throw RepositoryError.notSignedIn }
        guard !isAtOriginalLimit else { throw ResumeSaveError.originalLimit }

        saveStatus = .saving
        var path: String?

        do {
            let storedPath = try await resumes.uploadResumeFile(data, fileName: "resume-\(Self.timestamp()).pdf")
            path = storedPath

            var resume = NewResume(kind: .original)
            resume.title = Self.title(fromFileName: fileName)
            resume.filePath = storedPath
            if !text.isEmpty {
                resume.parsedData = .object(["text": .string(text)])
            }
            let record = try await resumes.createResume(resume)
            guard ownerId == owner else { return }

            try? await resumes.setActiveResumeId(record.id, userId: owner)

            let saved = SavedResume(record: record)
            savedResumes.insert(saved, at: 0)
            activeResumeId = saved.id
            self.pdfData = data
            resumeText = text
            self.fileName = saved.displayTitle
            uploadedAt = saved.createdAt
            contentResumeId = saved.id
            hasUnsavedUpload = false
            saveStatus = .saved
            persist()
        } catch {
            // Nothing half-saved: remove the uploaded file again
            if let path { try? await resumes.deleteResumeFile(atPath: path) }
            let mapped: Error = ResumeSaveError.from(error) ?? error
            saveStatus = .failed(mapped.localizedDescription)
            // The database said "full": this device's counts were out of date
            if mapped is ResumeSaveError { await loadAccount() }
            throw mapped
        }
    }

    /// Saves an optimized resume as a tailored version of the active resume's
    /// original, with `pdf`: the same one-page PDF the user previews and
    /// downloads. `replacingOldest` first deletes the oldest version (the
    /// user confirmed). Throws `ResumeSaveError.versionLimit` at the limit.
    func saveTailored(
        job: Job,
        text: String,
        pdf: Data?,
        score: Int?,
        replacingOldest: Bool = false
    ) async throws {
        guard let resumes, let owner = ownerId, let active = activeResume, !text.isEmpty else { return }
        let parentId = active.kind == .original ? active.id : (active.parentResumeId ?? active.id)

        // The user confirmed: make room even if this device's count is out
        // of date (the database is what said "full")
        if replacingOldest, let oldest = oldestVersion {
            try await delete(oldest)
        } else if isAtVersionLimit {
            throw ResumeSaveError.versionLimit
        }

        var path: String?
        if let pdf {
            path = try? await resumes.uploadResumeFile(pdf, fileName: "tailored-\(Self.timestamp()).pdf")
        }

        var resume = NewResume(kind: .tailored)
        resume.parentResumeId = parentId
        resume.targetJobId = job.id
        resume.title = "Tailored for \(job.company)"
        resume.filePath = path
        resume.parsedData = .object([
            "text": .string(text),
            "job_title": .string(job.title),
            "company": .string(job.company)
        ])
        resume.readinessScore = score

        do {
            let record: ResumeRecord
            do {
                record = try await resumes.createResume(resume)
            } catch where TrackerError.isMissingJob(error) {
                // The job isn't in the shared table yet; add it and retry once
                guard let applications else { throw error }
                try await applications.ensureJob(id: job.id, snapshot: job.snapshot)
                record = try await resumes.createResume(resume)
            }
            guard ownerId == owner else { return }
            savedResumes.insert(SavedResume(record: record), at: 0)
            persist()
        } catch {
            if let path { try? await resumes.deleteResumeFile(atPath: path) }
            guard let limitError = ResumeSaveError.from(error) else { throw error }
            // The database said "full": this device's counts were out of date
            await loadAccount()
            throw limitError
        }
    }

    // MARK: Managing Saved Resumes

    /// Makes a saved resume the one used for matching.
    func setActive(_ resume: SavedResume) async throws {
        guard let resumes, let owner = ownerId, resume.id != activeResumeId else { return }
        try await resumes.setActiveResumeId(resume.id, userId: owner)
        guard ownerId == owner else { return }
        hasUnsavedUpload = false
        activeResumeId = resume.id
        persist()
        await loadActiveContent()
    }

    func rename(_ resume: SavedResume, to newTitle: String) async throws {
        guard let resumes else { return }
        let title = String(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty, title != resume.title else { return }

        try await resumes.renameResume(id: resume.id, title: title)
        guard let index = savedResumes.firstIndex(where: { $0.id == resume.id }) else { return }
        savedResumes[index].title = title
        if resume.id == activeResumeId { fileName = title }
        persist()
    }

    /// Deletes a resume, its PDF and (for an original) its versions. If the
    /// active resume goes, the newest remaining original becomes active.
    func delete(_ resume: SavedResume) async throws {
        guard let resumes, let owner = ownerId else { return }

        let versions = resume.kind == .original
            ? savedResumes.filter { $0.parentResumeId == resume.id }
            : []

        // Each file goes first, so a row never points at a missing file and
        // no file is left without its row
        for item in versions + [resume] {
            if let path = item.filePath {
                try await resumes.deleteResumeFile(atPath: path)
            }
            try await resumes.deleteResume(id: item.id)
            guard ownerId == owner else { return }
            savedResumes.removeAll { $0.id == item.id }
        }

        if let activeResumeId, !savedResumes.contains(where: { $0.id == activeResumeId }) {
            let next = savedResumes.first { $0.kind == .original }
            try? await resumes.setActiveResumeId(next?.id, userId: owner)
            guard ownerId == owner else { return }
            self.activeResumeId = next?.id
            contentResumeId = nil
            clearContent()
            await loadActiveContent()
        }
        persist()
    }

    /// A temporary PDF of a saved resume, for viewing or sharing.
    func downloadPDF(of resume: SavedResume) async throws -> Data {
        guard let resumes, let path = resume.filePath else { throw RepositoryError.notConfigured }
        return try await resumes.downloadResumeFile(atPath: path)
    }

    func savedText(of resume: SavedResume) async throws -> String? {
        guard let resumes else { return nil }
        return try await resumes.fetchResumeText(id: resume.id)
    }

    // MARK: Helpers

    private func clearContent() {
        pdfData = nil
        resumeText = nil
        fileName = nil
        uploadedAt = nil
        contentResumeId = nil
    }

    private static func timestamp() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private static func title(fromFileName name: String) -> String {
        let base = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "My resume" : String(base.prefix(80))
    }

    // MARK: Device Storage (signed-in users only)

    private struct Meta: Codable {
        var fileName: String?
        var uploadedAt: Date?
        var contentResumeId: UUID?
        var activeResumeId: UUID?
        var savedResumes: [SavedResume]?
        var limits: ResumeLimits?
    }

    /// Application Support/Resume, excluded from backups.
    static func rootFolder() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return base.appendingPathComponent("Resume", isDirectory: true)
    }

    private static func folder(for userId: UUID) -> URL? {
        guard let root = rootFolder() else { return nil }
        if !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableRoot = root
            try? mutableRoot.setResourceValues(values)
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
        guard let ownerId, let folder = Self.folder(for: ownerId) else { return }
        let protection: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        let pdfURL = folder.appendingPathComponent("resume.pdf")
        let textURL = folder.appendingPathComponent("resume.txt")

        // Only saved content is kept on the device
        if contentResumeId != nil, let pdfData {
            try? pdfData.write(to: pdfURL, options: protection)
        } else {
            try? FileManager.default.removeItem(at: pdfURL)
        }
        if contentResumeId != nil, let resumeText {
            try? Data(resumeText.utf8).write(to: textURL, options: protection)
        } else {
            try? FileManager.default.removeItem(at: textURL)
        }

        let meta = Meta(
            fileName: fileName,
            uploadedAt: uploadedAt,
            contentResumeId: contentResumeId,
            activeResumeId: activeResumeId,
            savedResumes: savedResumes,
            limits: limits
        )
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: folder.appendingPathComponent("meta.json"), options: protection)
        }
    }

    private func restore(for userId: UUID) {
        guard let folder = Self.folder(for: userId),
              let metaData = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData) else { return }

        savedResumes = meta.savedResumes ?? []
        activeResumeId = meta.activeResumeId
        limits = meta.limits ?? .standard

        // The cached content only counts if it's the active resume's
        guard let contentId = meta.contentResumeId, contentId == meta.activeResumeId else { return }
        pdfData = try? Data(contentsOf: folder.appendingPathComponent("resume.pdf"))
        resumeText = try? String(contentsOf: folder.appendingPathComponent("resume.txt"), encoding: .utf8)
        fileName = meta.fileName
        uploadedAt = meta.uploadedAt
        contentResumeId = contentId
    }
}

// MARK: - Saved Resume

/// A resume saved to the user's account, as the app shows it.
struct SavedResume: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ResumeKind
    let parentResumeId: UUID?
    var title: String?
    let filePath: String?
    let readinessScore: Int?
    let createdAt: Date

    init(record: SavedResumeRecord) {
        id = record.id
        kind = record.kind
        parentResumeId = record.parentResumeId
        title = record.title
        filePath = record.filePath
        readinessScore = record.readinessScore
        createdAt = record.createdAt
    }

    init(record: ResumeRecord) {
        id = record.id
        kind = record.kind
        parentResumeId = record.parentResumeId
        title = record.title
        filePath = record.filePath
        readinessScore = record.readinessScore
        createdAt = record.createdAt
    }

    var isVersion: Bool { kind != .original }
    var hasFile: Bool { filePath != nil }

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty { return trimmed }
        switch kind {
        case .original:  return "My resume"
        case .optimized: return "Optimized resume"
        case .tailored:  return "Tailored resume"
        }
    }

    /// Original / Optimized / Tailored for [Company]
    var typeLabel: String {
        switch kind {
        case .original:  return "Original"
        case .optimized: return "Optimized"
        case .tailored:
            let prefix = "Tailored for "
            if let title, title.hasPrefix(prefix) { return title }
            return "Tailored version"
        }
    }
}

struct SavedResumeGroup: Identifiable {
    let original: SavedResume?
    let versions: [SavedResume]

    var id: UUID { original?.id ?? versions.first?.id ?? UUID() }
    var all: [SavedResume] { (original.map { [$0] } ?? []) + versions }
}
