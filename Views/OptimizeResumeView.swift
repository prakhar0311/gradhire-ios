import SwiftUI
import UIKit

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct OptimizeResumeView: View {

    let job: Job
    @EnvironmentObject var resumeManager: ResumeManager
    @EnvironmentObject var matchedJobs: MatchedJobsViewModel
    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.openURL) private var openURL
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var viewModel: OptimizeResumeViewModel

    @State private var isDownloading = false
    @State private var downloadErrorMessage: String?
    @State private var downloadedFileURL: URL?

    init(job: Job) {
        self.job = job
        _viewModel = StateObject(wrappedValue: OptimizeResumeViewModel(job: job))
    }

    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            // Mesh gradient
            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.28),
                            Color.clear
                        ],
                        center: .init(x: 0.25, y: 0.1),
                        startRadius: 0,
                        endRadius: 280
                    )
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.18),
                            Color.clear
                        ],
                        center: .init(x: 0.85, y: 0.35),
                        startRadius: 0,
                        endRadius: 240
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.6)
                .ignoresSafeArea()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {

                    topBar
                    heroSection
                    targetRoleCard

                    if viewModel.phase == .optimizing {
                        loadingCard
                    }

                    if case .failed(let message) = viewModel.phase {
                        errorCard(message: message)
                    }

                    if let result = viewModel.result, viewModel.phase == .done {
                        readinessCard(result: result)
                        missingSkillsCard(result: result.response)
                        bulletsCard(result: result.response)
                        keywordsCard(result: result.response)
                        actionButtons
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .onAppear {
            viewModel.onAppear(
                resumeText: resumeManager.resumeText,
                isConnected: network.isConnected
            )
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        // Once scored, keep this version with the user's saved resume
        .onChange(of: viewModel.result?.score) { _, score in
            guard case .loaded(_, let after)? = score,
                  let text = viewModel.result?.response.optimizedResumeText else { return }
            let job = viewModel.job
            let userId = auth.user?.id
            Task { await resumeManager.saveTailored(job: job, text: text, score: after, userId: userId) }
        }
        .sheet(item: $downloadedFileURL) { url in
            ShareSheet(items: [url])
        }
    }
}

// MARK: - Sub-views

private extension OptimizeResumeView {

    var topBar: some View {
        HStack {
            // Back button handled by NavigationView,
            // but keep a label for context
            Spacer()
            Text("AI OPTIMIZATION")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
        }
        .padding(.bottom, 4)
    }

    var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.39, green: 0.22, blue: 1.0),
                                Color(red: 0.0, green: 0.83, blue: 0.67)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(
                        color: Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.5),
                        radius: 20, x: 0, y: 8
                    )

                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("Resume Optimized")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Tailored for \(job.company)")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.bottom, 6)
    }

    var targetRoleCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Target Role", systemImage: "briefcase.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.35))
                    .textCase(.uppercase)

                Text(job.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(job.company)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))

                Text(job.location)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
    }

    func readinessCard(result: OptimizationResult) -> some View {
        let display = scoreDisplay(for: result)

        return glassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Resume Readiness", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.35))
                        .textCase(.uppercase)

                    Spacer()

                    versionToggle
                }

                HStack(spacing: 18) {
                    if let ringScore = display.ringScore {
                        DarkMatchRing(
                            score: ringScore,
                            size: 84,
                            lineWidth: 7,
                            isLoading: display.isLoading
                        )
                    } else {
                        // No trustworthy number to show
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.07), lineWidth: 7)
                            Text("—")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(width: 84, height: 84)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        display.headline
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())

                        Text(display.caption)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)

                        if result.score == .failed {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))
                                Text("Couldn't update score")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                Button("Retry") {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    viewModel.retryScore()
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                            }
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: result.score)
            .animation(.easeInOut(duration: 0.35), value: viewModel.selectedVersion)
        }
    }

    var versionToggle: some View {
        HStack(spacing: 2) {
            ForEach(ResumeVersion.allCases) { version in
                Button {
                    viewModel.selectedVersion = version
                } label: {
                    Text(version.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(viewModel.selectedVersion == version ? .white : .white.opacity(0.45))
                        .background {
                            if viewModel.selectedVersion == version {
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.6),
                                            Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.35)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.05))
        .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 0.5))
        .clipShape(Capsule())
    }

    func missingSkillsCard(result: ResumeOptimizationResponse) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Missing Skills",
                    icon: "exclamationmark.triangle.fill",
                    color: Color(red: 1.0, green: 0.48, blue: 0.21)
                )
                FlowChips(
                    items: result.missingSkills,
                    bgColor: Color(red: 1.0, green: 0.48, blue: 0.21).opacity(0.12),
                    borderColor: Color(red: 1.0, green: 0.48, blue: 0.21).opacity(0.3),
                    textColor: Color(red: 1.0, green: 0.68, blue: 0.45)
                )
            }
        }
    }

    func bulletsCard(result: ResumeOptimizationResponse) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Improved Bullets",
                    icon: "doc.text.fill",
                    color: Color(red: 0.39, green: 0.22, blue: 1.0)
                )
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(result.improvedBullets.prefix(5)), id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color(red: 0.39, green: 0.22, blue: 1.0))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(bullet)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.55))
                                .lineSpacing(3)
                        }
                    }
                }
            }
        }
    }

    func keywordsCard(result: ResumeOptimizationResponse) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "ATS Keywords",
                    icon: "tag.fill",
                    color: Color(red: 0.65, green: 0.55, blue: 0.98)
                )
                FlowChips(
                    items: result.atsKeywords,
                    bgColor: Color(red: 0.65, green: 0.55, blue: 0.98).opacity(0.12),
                    borderColor: Color(red: 0.65, green: 0.55, blue: 0.98).opacity(0.3),
                    textColor: Color(red: 0.77, green: 0.69, blue: 0.99)
                )
            }
        }
    }

    var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: downloadResume) {
                HStack {
                    Spacer()
                    if isDownloading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Download Optimized Resume")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.39, green: 0.22, blue: 1.0),
                            Color(red: 0.0, green: 0.83, blue: 0.67)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(16)
            }
            .disabled(isDownloading || viewModel.phase == .optimizing)

            if let downloadErrorMessage {
                Text(downloadErrorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))
                    .multilineTextAlignment(.center)
            }

            if let url = URL(string: job.applyURL) {
                // Opens Safari; "Did you apply?" is asked when the app is back
                Button {
                    tracker.applyOpened(job, externally: true)
                    openURL(url)
                } label: {
                    HStack {
                        Spacer()
                        Text("Apply Now")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.vertical, 15)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .foregroundColor(.white.opacity(0.8))
                    .cornerRadius(16)
                }
            }
        }
    }

    var loadingCard: some View {
        glassCard {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Color(red: 0.39, green: 0.22, blue: 1.0))
                    .scaleEffect(1.2)
                Text("Analyzing with AI...")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("Matching skills • Optimizing bullets • ATS tuning")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    func errorCard(message: String) -> some View {
        glassCard {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                Button("Retry Optimization") {
                    viewModel.optimize(
                        resumeText: resumeManager.resumeText,
                        isConnected: network.isConnected
                    )
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.4), lineWidth: 0.5)
                )
                .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                .cornerRadius(12)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
            )
            .cornerRadius(20)
    }

    func sectionHeader(title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.35))
            .textCase(.uppercase)
    }

    func scoreColor(_ score: Int) -> Color {
        switch score {
        case 85...100: return Color(red: 0.0, green: 0.83, blue: 0.67)
        case 65..<85:  return Color(red: 0.98, green: 0.75, blue: 0.18)
        default:       return Color(red: 1.0, green: 0.48, blue: 0.45)
        }
    }

    func scoreLabel(_ score: Int) -> String {
        switch score {
        case 85...100: return "Strong match"
        case 65..<85:  return "Good match"
        default:       return "Low match"
        }
    }

    /// The original resume's score for this job, only if it was computed for the
    /// resume currently loaded (a job bookmarked under an older resume doesn't count).
    var currentResumeOriginalScore: Int? {
        matchedJobs.jobs.first { $0.id == job.id }?.matchScore
    }

    struct ScoreDisplay {
        let ringScore: Int?
        let isLoading: Bool
        let headline: Text
        let caption: String
    }

    func scoreDisplay(for result: OptimizationResult) -> ScoreDisplay {
        let neutral = Color.white.opacity(0.85)

        switch (result.score, viewModel.selectedVersion) {

        case let (.loaded(before, after), version):
            let delta = after - before
            let deltaText: Text
            // Smaller than the "62 → 81" part so the line fits on one row
            let deltaFont = Font.system(size: 15, weight: .semibold, design: .rounded)
            if delta > 0 {
                deltaText = Text(" (+\(delta))").font(deltaFont).foregroundColor(Color(red: 0.0, green: 0.83, blue: 0.67))
            } else if delta < 0 {
                deltaText = Text(" (\(delta))").font(deltaFont).foregroundColor(Color(red: 0.98, green: 0.75, blue: 0.18))
            } else {
                deltaText = Text(" (no change)").font(deltaFont).foregroundColor(.white.opacity(0.4))
            }

            let shown = version == .original ? before : after
            let caption: String
            switch (version, delta) {
            case (.original, _):
                caption = "Original resume · \(scoreLabel(before))"
            case (.optimized, let d) where d > 0:
                caption = "Optimized resume · \(scoreLabel(after))"
            case (.optimized, 0):
                caption = "The optimized resume scores the same for this job."
            default:
                caption = "The optimized resume scores lower for this job."
            }

            return ScoreDisplay(
                ringScore: shown,
                isLoading: false,
                headline: Text("\(Text("\(before) → \(after)").foregroundColor(neutral))\(deltaText)"),
                caption: caption
            )

        case (.loading, .original) where currentResumeOriginalScore != nil:
            let original = currentResumeOriginalScore ?? 0
            return ScoreDisplay(
                ringScore: original,
                isLoading: false,
                headline: Text("\(original)%").foregroundColor(scoreColor(original)),
                caption: "Original resume · \(scoreLabel(original))"
            )

        case (.loading, _):
            return ScoreDisplay(
                ringScore: currentResumeOriginalScore ?? 0,
                isLoading: true,
                headline: Text("Scoring…").foregroundColor(neutral),
                caption: "Re-scoring with the same matching logic as your job matches."
            )

        case (.failed, _):
            if let original = currentResumeOriginalScore {
                return ScoreDisplay(
                    ringScore: original,
                    isLoading: false,
                    headline: Text("\(original)%").foregroundColor(scoreColor(original)),
                    caption: "Original resume score"
                )
            }
            return ScoreDisplay(
                ringScore: nil,
                isLoading: false,
                headline: Text("—").foregroundColor(.white.opacity(0.4)),
                caption: "Score unavailable"
            )
        }
    }
}

// MARK: - API Logic

private extension OptimizeResumeView {

    func downloadResume() {
        guard network.isConnected else { downloadErrorMessage = "No internet connection"; return }
        guard let resumeURL = resumeManager.resumeURL else {
            downloadErrorMessage = "No resume uploaded"; return
        }
        isDownloading = true; downloadErrorMessage = nil

        APIService.shared.downloadOptimizedResume(
            resumeURL: resumeURL,
            jobDescription: job.description,
            optimizedResumeJSON: viewModel.result?.response.optimizedResumeJSON
        ) { result in
            DispatchQueue.main.async {
                self.isDownloading = false
                switch result {
                case .success(let url):
                    self.downloadErrorMessage = nil
                    self.downloadedFileURL = url
                case .failure:
                    self.downloadErrorMessage = "Could not download the updated resume. Tap download to try again."
                }
            }
        }
    }
}

// MARK: - Flow Chips

struct FlowChips: View {
    let items: [String]
    let bgColor: Color
    let borderColor: Color
    let textColor: Color

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(bgColor)
                    .overlay(
                        Capsule()
                            .stroke(borderColor, lineWidth: 0.5)
                    )
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Resume Readiness (kept for compatibility)

struct ResumeReadinessCard: View {
    let matchScore: Int
    var body: some View { EmptyView() }
}

// MARK: - Legacy stubs (no longer used but kept to avoid breaking other files)

struct ImprovedBulletsSection: View {
    let bullets: [String]
    var body: some View { EmptyView() }
}

struct PremiumSection: View {
    let title: String; let icon: String; let color: Color; let items: [String]
    var body: some View { EmptyView() }
}

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data; let content: (Data.Element) -> Content
    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items; self.content = content
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.self) { item in content(item) }
        }
    }
}

