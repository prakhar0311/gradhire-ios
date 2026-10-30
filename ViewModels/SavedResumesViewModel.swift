import Foundation
import Combine

// MARK: - Saved Resumes View Model

/// Actions on the user's saved resumes (view, share, set active, rename,
/// delete). The list itself, and the active resume, live in ResumeManager,
/// which talks to ResumeRepository.
final class SavedResumesViewModel: ObservableObject {

    /// A saved resume's text, for versions saved before they had a PDF.
    struct TextPreview: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    @Published var previewURL: URL?
    @Published var shareURL: URL?
    @Published var textPreview: TextPreview?
    @Published var renaming: SavedResume?
    @Published var renameText = ""
    @Published var deleting: SavedResume?
    @Published var errorMessage: String?
    /// The resume an action is running for (shows a spinner on its row)
    @Published private(set) var busyId: UUID?

    private var temporaryFiles: [URL] = []

    // MARK: View / Share

    func view(_ resume: SavedResume, using manager: ResumeManager) {
        guard busyId == nil else { return }
        if !resume.hasFile {
            showText(of: resume, using: manager)
            return
        }
        run(resume) { [weak self] in
            self?.previewURL = try await self?.temporaryPDF(of: resume, using: manager)
        }
    }

    func share(_ resume: SavedResume, using manager: ResumeManager) {
        guard busyId == nil, resume.hasFile else { return }
        run(resume) { [weak self] in
            self?.shareURL = try await self?.temporaryPDF(of: resume, using: manager)
        }
    }

    private func showText(of resume: SavedResume, using manager: ResumeManager) {
        run(resume) { [weak self] in
            let text = try await manager.savedText(of: resume) ?? ""
            self?.textPreview = TextPreview(
                title: resume.displayTitle,
                text: text.isEmpty ? "This version has no saved text." : text
            )
        }
    }

    /// Downloaded through a short-lived signed URL into a temporary file,
    /// removed when the preview or share sheet closes.
    private func temporaryPDF(of resume: SavedResume, using manager: ResumeManager) async throws -> URL {
        let data = try await manager.downloadPDF(of: resume)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SavedResumes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let name = resume.displayTitle
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
        let url = folder.appendingPathComponent("\(name.isEmpty ? "Resume" : name).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        temporaryFiles.append(url)
        return url
    }

    func removeTemporaryFiles() {
        for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
        temporaryFiles = []
    }

    // MARK: Set Active / Rename / Delete

    func setActive(_ resume: SavedResume, using manager: ResumeManager) {
        guard busyId == nil else { return }
        run(resume) {
            try await manager.setActive(resume)
        }
    }

    func startRename(_ resume: SavedResume) {
        renameText = resume.displayTitle
        renaming = resume
    }

    func commitRename(using manager: ResumeManager) {
        guard let resume = renaming else { return }
        let title = renameText
        renaming = nil
        run(resume) {
            try await manager.rename(resume, to: title)
        }
    }

    func confirmDelete(using manager: ResumeManager) {
        guard let resume = deleting else { return }
        deleting = nil
        run(resume) {
            try await manager.delete(resume)
        }
    }

    /// "This also deletes 2 tailored versions." and the active-resume note.
    func deleteMessage(for resume: SavedResume, in manager: ResumeManager) -> String {
        var parts: [String] = []
        if resume.kind == .original {
            let count = manager.savedResumes.filter { $0.parentResumeId == resume.id }.count
            if count > 0 {
                parts.append("This also deletes \(count) tailored version\(count == 1 ? "" : "s").")
            }
        }
        if resume.id == manager.activeResumeId {
            parts.append("It's your active resume, so your newest other resume will be used for matching.")
        }
        parts.append("This can't be undone.")
        return parts.joined(separator: " ")
    }

    // MARK: Helpers

    private func run(_ resume: SavedResume, _ work: @escaping () async throws -> Void) {
        busyId = resume.id
        errorMessage = nil
        Task {
            defer { busyId = nil }
            do {
                try await work()
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private static func message(for error: Error) -> String {
        if error is URLError { return JobAPIError.from(error).localizedDescription }
        return "Something went wrong. Check your connection and try again."
    }
}
