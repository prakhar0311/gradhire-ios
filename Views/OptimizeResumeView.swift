import SwiftUI
import UIKit

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Optimize Resume

/// Preview first: the tailored one-page resume as the PDF the user will
/// download, a short "what changed", and the full analysis tucked into
/// "See details".
struct OptimizeResumeView: View {

    let job: Job
    @EnvironmentObject var resumeManager: ResumeManager
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var supabase: SupabaseManager
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var viewModel: OptimizeResumeViewModel

    @State private var downloadErrorMessage: String?
    @State private var downloadedFileURL: URL?
    @State private var sharedFileURL: URL?
    /// Tailoring at the version limit: waiting for "Replace oldest?"
    @State private var pendingTailored: PendingTailored?
    @State private var didSaveTailored = false
    @State private var showsDetails = false
    @State private var showsFullScreen = false
    @State private var showsEditSheet = false
    /// Drives the staggered entrance once content is ready
    @State private var revealed = false

    init(job: Job) {
        self.job = job
        _viewModel = StateObject(wrappedValue: OptimizeResumeViewModel(job: job))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    content
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.outcome != nil {
                actionBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.base, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("OPTIMIZE RESUME")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .onAppear {
            viewModel.onAppear(resumeText: resumeManager.resumeText, isConnected: network.isConnected, account: accountInfo)
            if viewModel.analysis != nil { revealed = true }
            if viewModel.outcome != nil, viewModel.preview == .idle { viewModel.renderPreview() }
        }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: viewModel.analysis) { _, analysis in
            if analysis != nil { revealed = true }
        }
        // A new result is kept with the user's saved resume, with the same
        // PDF they preview and download (once)
        .onChange(of: viewModel.rendered) { _, rendered in
            guard let rendered, let outcome = viewModel.outcome, viewModel.outcomeIsNew,
                  viewModel.includeChoice == nil, !didSaveTailored, !outcome.bullets.isEmpty else { return }
            didSaveTailored = true
            saveTailored(PendingTailored(text: outcome.optimizedResumeText, pdf: rendered.pdf, score: outcome.scoreAfter.total))
        }
        .confirmationDialog(
            "Replace your oldest tailored version?",
            isPresented: Binding(
                get: { pendingTailored != nil },
                set: { if !$0 { pendingTailored = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingTailored
        ) { pending in
            Button("Replace oldest") { saveTailored(pending, replacingOldest: true) }
            Button("Manage saved resumes") { session.showsSavedResumes = true }
            Button("Don't save", role: .cancel) {}
        } message: { _ in
            Text(replaceMessage)
        }
        .sheet(item: $downloadedFileURL, onDismiss: removeSharedFile) { url in
            ShareSheet(items: [url])
        }
        .fullScreenCover(isPresented: $showsFullScreen) {
            if let pdf = viewModel.rendered?.pdf {
                FullScreenPDF(pdf: pdf)
            }
        }
        .sheet(isPresented: $showsEditSheet) {
            if let outline = viewModel.outline, let layout = viewModel.rendered?.layout {
                EditIncludedSheet(model: viewModel, outline: outline, layout: layout)
            }
        }
    }
}

// MARK: - Sections

private extension OptimizeResumeView {

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title)
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(job.company.isEmpty ? "Tailoring your resume to this job" : "Tailoring your resume for \(job.company)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var content: some View {
        if let analysis = viewModel.analysis {
            CompactScoreHeader(
                before: analysis.scoreBefore,
                after: viewModel.scoreAfter,
                onReveal: { [improved = viewModel.outcome?.improved ?? false] in Self.scoreRevealed(improved: improved) }
            )
                .entrance(0, visible: revealed)

            if viewModel.phase == .rewriting {
                OptimizeProgressCard(phase: viewModel.phase)
                    .entrance(1, visible: revealed)
            }

            if case .failed(let message) = viewModel.phase {
                OptimizeErrorCard(message: message, retry: retry)
            }

            if let outcome = viewModel.outcome {
                ResumePreviewCard(
                    state: viewModel.preview,
                    onOpen: { showsFullScreen = true },
                    onEdit: { showsEditSheet = true },
                    onRetry: { viewModel.renderPreview() }
                )
                .entrance(1, visible: revealed)

                ChangeSummaryCard(lines: viewModel.changeLines)
                    .entrance(2, visible: revealed)


                CollapsibleDetails(isExpanded: $showsDetails) {
                    details(outcome, analysis: analysis)
                }
                .entrance(3, visible: revealed)
            }

        } else if case .failed(let message) = viewModel.phase {
            OptimizeErrorCard(message: message, retry: retry)
        } else {
            OptimizeProgressCard(phase: viewModel.phase)
        }
    }

    @ViewBuilder
    func details(_ outcome: OptimizationOutcome, analysis: ResumeAnalysis) -> some View {
        OptimizeCard(title: "SCORE BREAKDOWN", icon: "gauge.with.dots.needle.67percent", tint: AppTheme.teal) {
            VStack(alignment: .leading, spacing: 12) {
                ScoreBreakdownView(before: outcome.scoreBefore.breakdown, after: outcome.scoreAfter.breakdown)
                if !outcome.message.isEmpty {
                    Text(outcome.message)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        let progress = viewModel.keywordProgress
        if !progress.added.isEmpty || !progress.had.isEmpty {
            KeywordsCard(added: progress.added, had: progress.had)
        }

        bulletsSection(outcome)
    }

    @ViewBuilder
    func bulletsSection(_ outcome: OptimizationOutcome) -> some View {
        OptimizeCard(title: "IMPROVED BULLETS", icon: "text.badge.checkmark", tint: AppTheme.teal) {
            if outcome.bullets.isEmpty {
                Text("Your bullets are already as strong as we can honestly make them for this job. Nothing was changed.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    if outcome.bullets.contains(where: \.hasPlaceholder) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "pencil.and.list.clipboard")
                                .foregroundColor(AppTheme.amber)
                                .font(.footnote)
                            Text("Replace each [X] with your real number, or delete that part if you don't have one. We never make up results.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(AppTheme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    ForEach(outcome.bullets) { bullet in
                        BulletComparisonCard(bullet: bullet)
                    }
                }
            }
        }
    }

    // MARK: Action Bar

    var actionBar: some View {
        VStack(spacing: 8) {
            if let downloadErrorMessage {
                Text(downloadErrorMessage)
                    .font(.caption)
                    .foregroundColor(AppTheme.coral)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: downloadResume) {
                    HStack(spacing: 8) {
                        if viewModel.preview == .loading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                        }
                        Text(viewModel.preview == .loading ? "Preparing…" : "Download")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundColor(.white)
                    .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: AppTheme.purple.opacity(0.4), radius: 10, y: 4)
                }
                .disabled(viewModel.preview == .loading)
                .accessibilityLabel("Download resume")

                // Opens the browser; "Did you apply?" when the user comes back
                ApplyLinkButton(job: job, opensIn: .browser) {
                    HStack(spacing: 6) {
                        Text("Apply")
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundColor(.white.opacity(0.9))
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(AppTheme.base.opacity(0.55))
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Actions

private extension OptimizeResumeView {

    /// Signed-in users optimizing their saved active resume: the result is
    /// stored for this (resume, job).
    func accountInfo() async -> APIService.AnalysisAccount? {
        guard session.isSignedIn, let resumeId = resumeManager.activeResumeId,
              let access = await supabase.currentAccess() else { return nil }
        return APIService.AnalysisAccount(resumeId: resumeId, jobId: job.id, accessToken: access.accessToken)
    }

    func retry() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.retry(resumeText: resumeManager.resumeText, isConnected: network.isConnected, account: accountInfo)
    }

    static func scoreRevealed(improved: Bool) {
        if improved {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    var replaceMessage: String {
        let limit = resumeManager.limits.maxVersions
        guard let oldest = resumeManager.oldestVersion else {
            return "You can keep up to \(limit) tailored versions."
        }
        let date = oldest.createdAt.formatted(.dateTime.day().month(.abbreviated))
        return "You can keep up to \(limit) tailored versions. Replace \u{201C}\(oldest.displayTitle)\u{201D} (\(date)) with this one?"
    }

    /// Signed-in users with a saved resume keep each new version. At the
    /// limit, the user is asked before the oldest version is replaced.
    func saveTailored(_ pending: PendingTailored, replacingOldest: Bool = false) {
        guard session.isSignedIn, resumeManager.activeResumeId != nil else { return }
        let job = job
        Task {
            do {
                try await resumeManager.saveTailored(
                    job: job,
                    text: pending.text,
                    pdf: pending.pdf,
                    score: pending.score,
                    replacingOldest: replacingOldest
                )
                if replacingOldest { session.notice = "Saved. Your oldest tailored version was replaced." }
            } catch ResumeSaveError.versionLimit {
                pendingTailored = pending
            } catch {
                session.notice = "This tailored version couldn't be saved to your account."
            }
        }
    }

    /// The PDF only exists for the share sheet; nothing is kept afterwards.
    func removeSharedFile() {
        if let url = sharedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        sharedFileURL = nil
    }

    /// Shares the exact PDF shown in the preview.
    func downloadResume() {
        downloadErrorMessage = nil
        guard let pdf = viewModel.rendered?.pdf else {
            // Not ready (or failed): make it, then tap again
            downloadErrorMessage = "Preparing your PDF… tap Download again in a moment."
            viewModel.renderPreview()
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GradHire_Resume_\(UUID().uuidString.prefix(8)).pdf")
        do {
            try pdf.write(to: url, options: .completeFileProtection)
            sharedFileURL = url
            downloadedFileURL = url
        } catch {
            downloadErrorMessage = "Couldn't prepare the file on this device. Try again."
        }
    }
}

// MARK: - Pending Tailored Version

struct PendingTailored {
    let text: String
    let pdf: Data?
    let score: Int?
}
