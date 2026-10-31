import SwiftUI
import PDFKit

// MARK: - Optimize Screen Components

// MARK: Glass Card

/// Frosted card with a soft gradient border, used for every section.
struct OptimizeCard<Content: View>: View {

    var title: String? = nil
    var icon: String? = nil
    var tint: Color = AppTheme.lavender
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 7) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(tint)
                    }
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .tracking(1.3)
                        .foregroundColor(.white.opacity(0.45))
                }
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), AppTheme.purple.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 6)
    }
}

// MARK: Staggered Entrance

private struct Entrance: ViewModifier {
    let index: Int
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 18)
                .animation(.spring(response: 0.55, dampingFraction: 0.86).delay(Double(index) * 0.07), value: isVisible)
        }
    }
}

extension View {
    func entrance(_ index: Int, visible: Bool) -> some View {
        modifier(Entrance(index: index, isVisible: visible))
    }
}

// MARK: Progress Steps

/// The real steps: step 1 is the analysis request, step 2 the rewrite.
struct OptimizeProgressCard: View {

    let phase: OptimizeResumeViewModel.Phase

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private let steps = [
        Step(id: 0, title: "Analyzing the job description", detail: "Finding the skills and tools it asks for"),
        Step(id: 1, title: "Matching keywords to your resume", detail: "Checking your resume for each one"),
        Step(id: 2, title: "Rewriting your bullets", detail: "Using only what's in your resume"),
        Step(id: 3, title: "Re-scoring", detail: "Same scoring for before and after"),
    ]

    private func state(of step: Step) -> StepState {
        switch phase {
        case .analyzing: return step.id <= 1 ? .active : .pending
        case .rewriting: return step.id <= 1 ? .done : .active
        case .done:      return .done
        default:         return .pending
        }
    }

    var body: some View {
        OptimizeCard(title: "OPTIMIZING", icon: "sparkles", tint: AppTheme.violet) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(steps) { step in
                    StepRow(title: step.title, detail: step.detail, state: state(of: step))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum StepState { case pending, active, done }

private struct StepRow: View {
    let title: String
    let detail: String
    let state: StepState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(state == .done ? AppTheme.teal.opacity(0.2) : Color.white.opacity(0.06))
                    .frame(width: 26, height: 26)
                switch state {
                case .done:
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppTheme.teal)
                case .active:
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.violet)
                case .pending:
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title + (state == .active ? "…" : ""))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.white.opacity(state == .pending ? 0.35 : 0.9))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(state == .pending ? 0.2 : 0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel("\(title), \(state == .done ? "done" : state == .active ? "in progress" : "waiting")")
    }
}

/// "Keywords 50% → 62%", "Required skills 6/10", "Bullets Medium → Strong"
struct ScoreBreakdownView: View {

    let before: ScoreBreakdown
    let after: ScoreBreakdown?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 8) {
            row("Keyword evidence", "\(before.keywordEvidence)%", after.map { "\($0.keywordEvidence)%" },
                better: (after?.keywordEvidence ?? 0) > before.keywordEvidence)
            row("Required skills", "\(before.requiredPresent)/\(before.requiredTotal)",
                after.map { "\($0.requiredPresent)/\($0.requiredTotal)" },
                better: (after?.requiredPresent ?? 0) > before.requiredPresent)
            row("Bullet strength", before.bulletStrength, after?.bulletStrength,
                better: rank(after?.bulletStrength) > rank(before.bulletStrength))
            row("Relevance", "\(before.relevance)/5", after.map { "\($0.relevance)/5" },
                better: (after?.relevance ?? 0) > before.relevance)
        }
    }

    private func rank(_ label: String?) -> Int {
        switch label {
        case "Strong": return 3
        case "Medium": return 2
        case "Weak":   return 1
        default:       return 0
        }
    }

    private func row(_ title: String, _ from: String, _ to: String?, better: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(title)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.55))
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            HStack(spacing: 8) {
                Text(from)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundColor(.white.opacity(to == nil ? 0.85 : 0.45))
                if let to {
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white.opacity(0.3))
                    Text(to)
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .foregroundColor(better ? AppTheme.teal : .white.opacity(0.85))
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Keywords

struct KeywordsCard: View {

    /// Added or strengthened by this optimization
    let added: [String]
    /// Already in the resume
    let had: [String]

    var body: some View {
        OptimizeCard(title: "ATS KEYWORDS", icon: "tag.fill", tint: AppTheme.teal) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(added.isEmpty ? had.count : added.count)")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundColor(.white)
                    Text(added.isEmpty
                         ? "of this job's keywords are already in your resume"
                         : "keyword\(added.count == 1 ? "" : "s") added or strengthened for this job")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                ChipFlowLayout(spacing: 8) {
                    ForEach(added, id: \.self) { name in
                        KeywordChip(name: name, isNew: true)
                    }
                    ForEach(had, id: \.self) { name in
                        KeywordChip(name: name, isNew: false)
                    }
                }

                HStack(spacing: 14) {
                    if !added.isEmpty { legend(filled: true, text: "Added or strengthened") }
                    if !had.isEmpty { legend(filled: false, text: "Already in your resume") }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func legend(filled: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(filled ? AppTheme.teal : .clear)
                .overlay(Circle().stroke(AppTheme.teal.opacity(filled ? 1 : 0.6), lineWidth: 1))
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
    }
}

private struct KeywordChip: View {
    let name: String
    /// Added or strengthened by this optimization
    let isNew: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isNew ? "arrow.up" : "checkmark")
                .font(.caption2.weight(.bold))
            Text(name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(isNew ? .white : .white.opacity(0.75))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            if isNew {
                Capsule().fill(AppTheme.teal.opacity(0.32))
            }
        }
        .overlay(Capsule().stroke(AppTheme.teal.opacity(isNew ? 0.85 : 0.35), lineWidth: 1))
        .shadow(color: isNew ? AppTheme.teal.opacity(0.4) : .clear, radius: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(isNew ? "added or strengthened" : "already in your resume")")
    }
}

// MARK: Bullets (before / after)

struct BulletComparisonCard: View {

    let bullet: BulletRewrite
    @State private var expanded = false

    private var isLong: Bool { bullet.improved.count > 170 || bullet.original.count > 170 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !bullet.heading.isEmpty {
                Text(bullet.heading.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.3))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                label("BEFORE", color: .white.opacity(0.35))
                Text(bullet.original)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(expanded || !isLong ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                label("AFTER", color: AppTheme.teal)
                Text(WordDiff.highlighted(original: bullet.original, improved: bullet.improved))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(expanded || !isLong ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.teal.opacity(0.25), lineWidth: 0.6)
            )

            if isLong {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.lavender)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .tracking(1.2)
            .foregroundColor(color)
    }
}

// MARK: Word Diff

/// Highlights the words the rewrite changed (longest common subsequence
/// of words), and any [placeholder] the user should fill in.
enum WordDiff {

    static func highlighted(original: String, improved: String) -> AttributedString {
        let oldWords = original.split(separator: " ").map { normalize(String($0)) }
        let newTokens = improved.split(separator: " ").map(String.init)
        let newWords = newTokens.map { normalize($0) }

        let kept = commonWords(oldWords, newWords)

        var result = AttributedString()
        for (index, token) in newTokens.enumerated() {
            var piece = AttributedString(token)
            if token.contains("[") || token.contains("]") {
                piece.foregroundColor = AppTheme.amber
                piece.font = .subheadline.weight(.bold)
            } else if !kept.contains(index) {
                piece.foregroundColor = AppTheme.teal
                piece.font = .subheadline.weight(.semibold)
            }
            result += piece
            if index < newTokens.count - 1 { result += AttributedString(" ") }
        }
        return result
    }

    private static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Indexes in `b` that are part of a longest common subsequence with `a`.
    private static func commonWords(_ a: [String], _ b: [String]) -> Set<Int> {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var kept = Set<Int>()
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                kept.insert(j); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return kept
    }
}

// MARK: Error

struct OptimizeErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        OptimizeCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundColor(AppTheme.amber)
                Text("Couldn't optimize your resume")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: retry) {
                    Text("Try again")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(AppTheme.purple.opacity(0.3), in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.purple.opacity(0.5), lineWidth: 0.6))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}


// MARK: Compact Score Header

/// Before → after ring with the delta badge, small enough to leave room
/// for the resume preview.
struct CompactScoreHeader: View {

    let before: AnalysisScore
    /// nil while the rewrite is running
    let after: AnalysisScore?
    var onReveal: () -> Void = {}

    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 84
    @Environment(\.dynamicTypeSize) private var typeSize

    private var delta: Int { (after?.total ?? before.total) - before.total }

    /// Side by side normally; stacked at accessibility text sizes
    private var outerLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    private var scoreRowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        OptimizeCard {
            outerLayout {
                DarkMatchRing(
                    score: after?.total ?? before.total,
                    size: min(ringSize, 120),
                    lineWidth: 8,
                    from: after == nil ? nil : before.total,
                    glows: true,
                    onReveal: after == nil ? nil : onReveal
                )
                .id(after == nil ? "before" : "after")

                VStack(alignment: .leading, spacing: 6) {
                    Text(after == nil ? "DETAILED SCORE" : "DETAILED SCORE FOR THIS JOB")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.45))
                    if after != nil {
                        scoreRowLayout {
                            Text("\(before.total) → \(after?.total ?? before.total)")
                                .font(.system(.title3, design: .rounded, weight: .black))
                                .foregroundColor(.white)
                                .fixedSize()
                            deltaBadge
                        }
                        if let after {
                            Text("Keyword match \(before.breakdown.keywordEvidence)% → \(after.breakdown.keywordEvidence)%")
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundColor(after.breakdown.keywordEvidence > before.breakdown.keywordEvidence ? AppTheme.teal : .white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(celebration)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.caption.weight(delta >= 5 ? .semibold : .regular))
                            .foregroundColor(delta >= 5 ? .white.opacity(0.85) : .white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Rewriting your bullets…")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Real gains are celebrated; no gain is said plainly (or positively for
    /// an already strong resume). Same scoring before and after.
    private var celebration: String {
        let afterTotal = after?.total ?? before.total
        if delta >= 5 { return "+\(delta) points, nice work! Scored the same way before and after." }
        if delta > 0 { return "+\(delta) point\(delta == 1 ? "" : "s"), scored the same way before and after." }
        if afterTotal >= 85 { return "Already a strong match for this job." }
        return "Scored the same way before and after."
    }

    private var deltaBadge: some View {
        let text = delta > 0 ? "+\(delta)" : delta == 0 ? "No change" : "\(delta)"
        return Text(text)
            .font(.system(.footnote, design: .rounded, weight: .heavy))
            .foregroundColor(delta > 0 ? AppTheme.base : .white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background((delta > 0 ? AppTheme.teal : AppTheme.lavender.opacity(0.25)), in: Capsule())
            .shadow(color: delta > 0 ? AppTheme.teal.opacity(0.6) : .clear, radius: 8)
            .fixedSize()
            .accessibilityLabel(delta > 0 ? "Up \(delta) points" : delta == 0 ? "No change" : "Down \(-delta) points")
    }
}

// MARK: Resume Preview

/// The actual one-page PDF, drawn page by page on white "paper".
struct ResumePreviewCard: View {

    let state: OptimizeResumeViewModel.PreviewState
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onRetry: () -> Void

    var body: some View {
        OptimizeCard(title: "YOUR TAILORED RESUME", icon: "doc.richtext", tint: AppTheme.lavender) {
            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .idle, .loading:
                    PaperSkeleton()
                case .failed(let message):
                    VStack(spacing: 10) {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Try again", action: onRetry)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.lavender)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                case .ready(let rendered):
                    Button(action: onOpen) {
                        PDFPagesView(pdf: rendered.pdf)
                            .overlay(alignment: .bottomTrailing) {
                                Label("Tap to enlarge", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .padding(10)
                                    .accessibilityHidden(true)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the resume full screen")

                    ViewThatFits(in: .horizontal) {
                        HStack {
                            pageInfo(rendered)
                            Spacer()
                            editButton
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            pageInfo(rendered)
                            editButton
                        }
                    }
                }
            }
        }
    }

    private func pageInfo(_ rendered: RenderedResume) -> some View {
        Text("1 page · \(Self.points(rendered.layout.fontSize)) pt text")
            .font(.caption)
            .foregroundColor(.white.opacity(0.45))
    }

    private var editButton: some View {
                        Button(action: onEdit) {
                            Label("Edit what's included", systemImage: "slider.horizontal.3")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(AppTheme.lavender)
                        }
    }

    private static func points(_ size: Double) -> String {
        size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)
    }
}

/// Every page of the PDF as an image (the real PDF, so it matches the
/// download exactly). VoiceOver reads the PDF's own text.
struct PDFPagesView: View {

    let pdf: Data
    @State private var pages: [UIImage] = []
    @State private var text = ""

    var body: some View {
        VStack(spacing: 10) {
            if pages.isEmpty {
                PaperSkeleton()
            }
            ForEach(Array(pages.enumerated()), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: AppTheme.purple.opacity(0.35), radius: 16, y: 6)
                    .overlay(alignment: .topTrailing) {
                        if pages.count > 1 {
                            Text("Page \(index + 1) of \(pages.count)")
                                .font(.caption2.weight(.semibold))
                                .padding(6)
                                .background(.black.opacity(0.5), in: Capsule())
                                .foregroundColor(.white)
                                .padding(8)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of your tailored resume, \(pages.count) page\(pages.count == 1 ? "" : "s")")
        .accessibilityValue(text)
        .task(id: pdf) {
            guard let document = PDFDocument(data: pdf) else { return }
            text = document.string ?? ""
            let scale = UIScreen.main.scale
            var images: [UIImage] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let width: CGFloat = 420 * scale
                let size = CGSize(width: width, height: width * bounds.height / max(bounds.width, 1))
                images.append(page.thumbnail(of: size, for: .mediaBox))
            }
            pages = images
        }
    }
}

private struct PaperSkeleton: View {
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(shimmer ? 0.12 : 0.07))
            .aspectRatio(595.0 / 842.0, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    ProgressView().tint(AppTheme.violet)
                    Text("Preparing your one-page PDF…")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { shimmer = true }
            }
    }
}

// MARK: Full-Screen PDF

struct FullScreenPDF: View {
    let pdf: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(pdf: pdf)
                .ignoresSafeArea(edges: .bottom)
                .background(AppTheme.base)
                .navigationTitle("Resume preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(AppTheme.base, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundColor(AppTheme.lavender)
                    }
                }
        }
    }
}

/// PDFKit's own viewer: pinch to zoom and scroll.
struct PDFKitView: UIViewRepresentable {
    let pdf: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(data: pdf)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(AppTheme.base)
        view.minScaleFactor = view.scaleFactorForSizeToFit
        view.maxScaleFactor = 5
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.minScaleFactor = view.scaleFactorForSizeToFit
    }
}

// MARK: What Changed

struct ChangeSummaryCard: View {

    let lines: [OptimizeResumeViewModel.ChangeLine]

    var body: some View {
        OptimizeCard(title: "WHAT CHANGED", icon: "sparkles", tint: AppTheme.teal) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: line.icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(line.tone == .attention ? AppTheme.amber : AppTheme.teal)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(line.text)
                            .font(.subheadline.weight(line.tone == .attention ? .semibold : .regular))
                            .foregroundColor(.white.opacity(line.tone == .attention ? 0.95 : 0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: See Details

/// Collapsed by default; opens without animation when Reduce Motion is on.
struct CollapsibleDetails<Content: View>: View {

    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 14) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { isExpanded.toggle() }
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Hide details" : "See details")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    if !typeSize.isAccessibilitySize {
                        Text("score, keywords, bullets")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide details" : "See details: score, keywords and bullets")
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: Edit What's Included

struct EditIncludedSheet: View {

    @ObservedObject var model: OptimizeResumeViewModel
    let outline: ResumeOutline
    let available: AvailableSections
    let isAutomatic: Bool

    @State private var choice: IncludeChoice
    @State private var message: String?
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    init(model: OptimizeResumeViewModel, outline: ResumeOutline, layout: ResumeLayout) {
        self.model = model
        self.outline = outline
        self.available = layout.available
        self.isAutomatic = model.includeChoice == nil
        _choice = State(initialValue: IncludeChoice(layout.included))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose what goes on your one-page PDF. Anything you leave out stays in your saved resume.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)

                        if !outline.experience.isEmpty {
                            OptimizeCard(title: "EXPERIENCE", icon: "briefcase.fill", tint: AppTheme.lavender) {
                                ForEach(Array(outline.experience.enumerated()), id: \.offset) { index, job in
                                    toggleRow(
                                        title: [job.title, job.company].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "),
                                        note: index == 0 ? "Most recent, always included" : nil,
                                        isOn: index == 0 ? .constant(true) : binding(for: index, in: \.experience)
                                    )
                                    .disabled(index == 0)
                                }
                            }
                        }

                        if !outline.projects.isEmpty {
                            OptimizeCard(title: "PROJECTS", icon: "hammer.fill", tint: AppTheme.lavender) {
                                ForEach(Array(outline.projects.enumerated()), id: \.offset) { index, project in
                                    toggleRow(title: project.title ?? "Project", note: project.tech,
                                              isOn: binding(for: index, in: \.projects))
                                }
                            }
                        }

                        if available.certifications || available.achievements || available.coursework {
                            OptimizeCard(title: "OPTIONAL SECTIONS", icon: "list.bullet.rectangle", tint: AppTheme.lavender) {
                                if available.coursework {
                                    toggleRow(title: "Relevant coursework", note: nil, isOn: $choice.coursework)
                                }
                                if available.certifications {
                                    toggleRow(title: "Certifications", note: nil, isOn: $choice.certifications)
                                }
                                if available.achievements {
                                    toggleRow(title: "Achievements", note: nil, isOn: $choice.achievements)
                                }
                            }
                        }

                        if let message {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppTheme.amber)
                                Text(message)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(AppTheme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button {
                            regenerate()
                        } label: {
                            HStack {
                                if isWorking { ProgressView().tint(.white) }
                                Text(isWorking ? "Regenerating…" : "Regenerate PDF")
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundColor(.white)
                            .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(isWorking)

                        if !isAutomatic {
                            Button("Use automatic fit") {
                                model.resetIncludes()
                                dismiss()
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(AppTheme.lavender)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Edit what's included")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.base, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.lavender)
                }
            }
        }
    }

    private func binding(for index: Int, in keyPath: WritableKeyPath<IncludeChoice, Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { choice[keyPath: keyPath].contains(index) },
            set: { on in
                if on { choice[keyPath: keyPath].insert(index) } else { choice[keyPath: keyPath].remove(index) }
                message = nil
            }
        )
    }

    private func toggleRow(title: String, note: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .tint(AppTheme.teal)
        .padding(.vertical, 2)
    }

    private func regenerate() {
        isWorking = true
        message = nil
        let choice = choice
        Task {
            let problem = await model.apply(choice)
            isWorking = false
            if let problem {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                message = problem
            } else {
                dismiss()
            }
        }
    }
}
