import Foundation
import Combine

// MARK: - Optimize Resume View Model

/// Optimizes the current resume for one job in two real steps:
///   1. analysis: the job's keywords, matched vs missing, the current score
///   2. rewrite: improved bullets, the optimized resume and its score
/// A result made before for the same resume and job is reused (stored on the
/// server for signed-in users, kept in memory for this session otherwise),
/// so reopening is instant and shows the same numbers.
final class OptimizeResumeViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case analyzing
        case rewriting
        case done
        case failed(String)
    }

    enum PreviewState: Equatable {
        case idle
        case loading
        case ready(RenderedResume)
        case failed(String)
    }

    /// One line of "What changed"
    struct ChangeLine: Identifiable, Equatable {
        enum Tone { case normal, attention }
        let id: String
        let icon: String
        let text: String
        var tone: Tone = .normal
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var analysis: ResumeAnalysis?
    @Published private(set) var outcome: OptimizationOutcome?
    /// True only for a result made just now (not reopened), so a tailored
    /// version is saved once
    @Published private(set) var outcomeIsNew = false

    /// The one-page PDF: previewed, downloaded and saved as the same bytes
    @Published private(set) var preview: PreviewState = .idle
    /// The user's "Edit what's included" choice; nil = fitted automatically
    @Published private(set) var includeChoice: IncludeChoice?

    let job: Job

    private var task: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var cacheKey: String?

    /// This session's results and PDFs (memory only; cleared on sign-out)
    private static var cache: [String: OptimizationOutcome] = [:]
    private static var renders: [String: RenderedResume] = [:]

    init(job: Job) {
        self.job = job
    }

    static func clearCache() {
        cache = [:]
        renders = [:]
    }

    var rendered: RenderedResume? {
        if case .ready(let rendered) = preview { return rendered }
        return nil
    }

    /// The "after" score shown: the chosen PDF's own score after "Edit
    /// what's included", otherwise the optimized result's.
    var scoreAfter: AnalysisScore? {
        if includeChoice != nil, let score = rendered?.score { return score }
        return outcome?.scoreAfter
    }

    /// The jobs and projects in the optimized resume (for the Edit sheet)
    var outline: ResumeOutline? {
        guard let json = outcome?.optimizedResumeJSON else { return nil }
        return try? JSONDecoder().decode(ResumeOutline.self, from: json)
    }

    var isWorking: Bool { phase == .analyzing || phase == .rewriting }

    // MARK: Lifecycle

    /// Starts work only if nothing is running or done, so reappearing never
    /// repeats requests.
    func onAppear(
        resumeText: String?,
        isConnected: Bool,
        account: @escaping () async -> APIService.AnalysisAccount?
    ) {
        switch phase {
        case .idle:
            start(resumeText: resumeText, isConnected: isConnected, account: account)
        case .analyzing, .rewriting, .done, .failed:
            return
        }
    }

    /// Leaving the screen cancels requests in flight; onAppear starts again.
    func onDisappear() {
        task?.cancel()
        task = nil
        renderTask?.cancel()
        renderTask = nil
        if isWorking { phase = .idle }
        if preview == .loading { preview = .idle }
    }

    func retry(
        resumeText: String?,
        isConnected: Bool,
        account: @escaping () async -> APIService.AnalysisAccount?
    ) {
        start(resumeText: resumeText, isConnected: isConnected, account: account)
    }

    // MARK: Work

    private func start(
        resumeText: String?,
        isConnected: Bool,
        account: @escaping () async -> APIService.AnalysisAccount?
    ) {
        guard let resumeText, !resumeText.isEmpty else {
            phase = .failed("We couldn't find your resume's text. Upload your resume again.")
            return
        }

        let key = Self.cacheKey(resumeText: resumeText, job: job)
        cacheKey = key
        if let cached = Self.cache[key] {
            show(cached, isNew: false)
            return
        }

        guard isConnected else {
            phase = .failed(JobAPIError.offline.localizedDescription)
            return
        }

        task?.cancel()
        outcomeIsNew = false
        phase = .analyzing

        let jobDescription = job.description
        task = Task {
            do {
                let accountInfo = await account()
                let started = try await APIService.shared.analyzeResume(
                    resumeText: resumeText, jobDescription: jobDescription, account: accountInfo
                )
                guard !Task.isCancelled else { return }
                analysis = started.analysis

                // Optimized before: the stored result, no second request
                if let stored = started.result {
                    Self.cache[key] = stored
                    show(stored, isNew: false)
                    return
                }

                phase = .rewriting
                let result = try await APIService.shared.optimizeResume(
                    resumeText: resumeText, jobDescription: jobDescription, account: accountInfo
                )
                guard !Task.isCancelled else { return }
                Self.cache[key] = result
                show(result, isNew: true)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(JobAPIError.from(error).localizedDescription)
            }
        }
    }

    private func show(_ result: OptimizationOutcome, isNew: Bool) {
        analysis = result.analysis
        outcome = result
        outcomeIsNew = isNew
        phase = .done
        renderPreview()
    }

    // MARK: Preview PDF

    /// Renders the one-page PDF for the current result and choice.
    func renderPreview() {
        guard let outcome, let json = outcome.optimizedResumeJSON else {
            preview = .failed("This result has no resume to preview. Try optimizing again.")
            return
        }
        let renderKey = self.renderKey(for: includeChoice)
        if let cached = Self.renders[renderKey] {
            preview = .ready(cached)
            return
        }

        renderTask?.cancel()
        preview = .loading
        let keywords = outcome.keywords.map(\.name)
        let choice = includeChoice
        renderTask = Task {
            do {
                let rendered = try await APIService.shared.renderResume(
                    resumeJSON: json, keywords: keywords, include: choice, jobDescription: job.description
                )
                guard !Task.isCancelled else { return }
                Self.renders[renderKey] = rendered
                preview = .ready(rendered)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                preview = .failed(JobAPIError.from(error).localizedDescription)
            }
        }
    }

    /// "Edit what's included": returns nil when the PDF was regenerated, or
    /// what still needs removing when the choice doesn't fit one page.
    func apply(_ choice: IncludeChoice) async -> String? {
        guard let outcome, let json = outcome.optimizedResumeJSON else { return "Nothing to regenerate." }
        let renderKey = self.renderKey(for: choice)
        if let cached = Self.renders[renderKey] {
            includeChoice = choice
            preview = .ready(cached)
            return nil
        }
        do {
            let rendered = try await APIService.shared.renderResume(
                resumeJSON: json, keywords: outcome.keywords.map(\.name), include: choice, jobDescription: job.description
            )
            Self.renders[renderKey] = rendered
            includeChoice = choice
            preview = .ready(rendered)
            return nil
        } catch let overflow as ResumeOverflowError {
            return overflow.message
        } catch {
            return JobAPIError.from(error).localizedDescription
        }
    }

    /// Back to the automatic fit.
    func resetIncludes() {
        includeChoice = nil
        renderPreview()
    }

    private func renderKey(for choice: IncludeChoice?) -> String {
        // The resume itself changes when skills are confirmed
        let base = (cacheKey ?? job.id.uuidString) + "|\(outcome?.optimizedResumeJSON?.hashValue ?? 0)"
        guard let choice else { return base + "|auto" }
        return base + "|e\(choice.experience.sorted())p\(choice.projects.sorted())"
            + "c\(choice.certifications)a\(choice.achievements)w\(choice.coursework)"
    }

    // MARK: What Changed

    /// Short lines built only from this result and this PDF.
    var changeLines: [ChangeLine] {
        guard let outcome else { return [] }
        var lines: [ChangeLine] = []

        let rewritten = outcome.bullets.count
        lines.append(ChangeLine(
            id: "bullets",
            icon: "text.badge.checkmark",
            text: rewritten > 0
                ? "Rewrote \(rewritten) bullet point\(rewritten == 1 ? "" : "s") to match this job"
                : "Your bullets were already strong for this job, so none were rewritten"
        ))

        if let changes = outcome.changes {
            let confirmed = changes.confirmedSkills ?? []
            let isConfirmed = { (name: String) in confirmed.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
            if !confirmed.isEmpty {
                lines.append(ChangeLine(id: "confirmed", icon: "checkmark.circle.fill", text: "Added the skills you confirmed: \(Self.list(confirmed))"))
            }
            // Confirmed skills have their own line above
            let worked = changes.keywordsInBullets.filter { !isConfirmed($0) }
            if !worked.isEmpty {
                lines.append(ChangeLine(
                    id: "keywords",
                    icon: "tag.fill",
                    text: "Worked in \(worked.count) keyword\(worked.count == 1 ? "" : "s") you already have: \(Self.list(worked))"
                ))
            }
            let listed = changes.skillsListed.filter { !isConfirmed($0) }
            if !listed.isEmpty {
                lines.append(ChangeLine(id: "skills", icon: "plus.circle", text: "Added to your Skills: \(Self.list(listed))"))
            }
        }

        if let layout = rendered?.layout {
            let fitted = layout.removed.filter { $0.kind != "format" && $0.chosen != true }.map { Self.describe($0) }
            let chosen = layout.removed.filter { $0.chosen == true }.map { Self.describe($0) }
            if !fitted.isEmpty {
                lines.append(ChangeLine(id: "fit", icon: "rectangle.compress.vertical", text: "To fit one page, we left out: \(Self.list(fitted, limit: 5))"))
            }
            if !chosen.isEmpty {
                lines.append(ChangeLine(id: "chosen", icon: "slider.horizontal.3", text: "You left out: \(Self.list(chosen, limit: 5))"))
            }
            if layout.removed.contains(where: { $0.kind == "format" }) {
                lines.append(ChangeLine(id: "summary", icon: "doc.plaintext", text: "Your summary isn't part of this one-page format"))
            }
        }

        if let placeholders = outcome.changes?.placeholders, placeholders > 0 {
            lines.append(ChangeLine(
                id: "placeholders",
                icon: "pencil",
                text: "Fill in \(placeholders) [X] placeholder\(placeholders == 1 ? "" : "s") with your real numbers"
            ))
        }

        if let potential = outcome.potential, potential.score > (scoreAfter?.total ?? 0) {
            lines.append(ChangeLine(
                id: "path",
                icon: "arrow.up.right.circle.fill",
                text: "Add \(Self.list(potential.skills, limit: 3)) to reach about \(potential.score), only if you really have \(potential.skills.count == 1 ? "it" : "them")",
                tone: .attention
            ))
        }
        return lines
    }

    /// The job's keywords this optimization added or strengthened (named in
    /// a bullet, added to Skills, or confirmed by the user), and the ones the
    /// resume already had. Nothing about what's missing.
    var keywordProgress: (added: [String], had: [String]) {
        guard let outcome else { return ([], []) }
        let changes = outcome.changes
        let improved = Set(((changes?.keywordsInBullets ?? []) + (changes?.skillsListed ?? []) + (changes?.confirmedSkills ?? []))
            .map { $0.lowercased() })
        let added = outcome.keywords.map(\.name).filter { improved.contains($0.lowercased()) }
        let had = outcome.keywords.filter { $0.matched && !improved.contains($0.name.lowercased()) }.map(\.name)
        return (added, had)
    }

    /// "QuizBuzz (project)", "Teaching Assistant, Example College (job)"
    private static func describe(_ item: RemovedItem) -> String {
        switch item.kind {
        case "project":    return "\(item.label) (project)"
        case "experience": return "\(item.label) (job)"
        default:           return item.label
        }
    }

    private static func list(_ items: [String], limit: Int = 4) -> String {
        let shown = items.prefix(limit).joined(separator: ", ")
        return items.count > limit ? "\(shown) and \(items.count - limit) more" : shown
    }

    private static func cacheKey(resumeText: String, job: Job) -> String {
        "\(job.id.uuidString)|\(resumeText.count)|\(resumeText.hashValue)|\(job.description.hashValue)"
    }
}
