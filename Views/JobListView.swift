import SwiftUI
import UIKit

// MARK: - Jobs Tab

enum JobsTab: String, CaseIterable, Identifiable {
    case forYou = "For You"
    case allJobs = "All Jobs"

    var id: String { rawValue }
}

// MARK: - Job List View

struct JobListView: View {

    let country: String
    @Binding var selectedTab: JobsTab

    @EnvironmentObject private var bookmarks: BookmarkManager
    @EnvironmentObject private var matchedJobs: MatchedJobsViewModel
    @EnvironmentObject private var allJobs: AllJobsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {

            // Dark base
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            // Mesh gradient background
            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.25),
                            Color.clear
                        ],
                        center: .init(x: 0.2, y: 0.1),
                        startRadius: 0,
                        endRadius: 300
                    )
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.15),
                            Color.clear
                        ],
                        center: .init(x: 0.85, y: 0.4),
                        startRadius: 0,
                        endRadius: 260
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.55)
                .ignoresSafeArea()
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {

                    header

                    JobsTabPicker(selection: $selectedTab)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    switch selectedTab {
                    case .forYou:  forYouContent
                    case .allJobs: allJobsContent
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
            .refreshable {
                switch selectedTab {
                case .forYou:  await matchedJobs.refresh()
                case .allJobs: await allJobs.refresh()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            Color(red: 0.04, green: 0.04, blue: 0.06),
            for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(selectedTab == .forYou ? "JOB MATCHES" : "NEW GRAD JOBS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    NavigationLink(destination: SavedJobsView()) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.07))
                                .frame(width: 34, height: 34)
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .accessibilityLabel("Saved jobs")

                    AccountButton()
                }
            }
        }
        .onAppear {
            if selectedTab == .allJobs {
                allJobs.loadIfNeeded(country: country)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if tab == .allJobs {
                allJobs.loadIfNeeded(country: country)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedTab == .forYou ? "Best Matches" : "New Grad Jobs")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text(
                selectedTab == .forYou
                ? "AI matched roles for your resume"
                : "Fresh entry-level openings, newest first"
            )
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - For You

    @ViewBuilder
    private var forYouContent: some View {
        if !matchedJobs.hasResume {
            DarkEmptyView(
                icon: "doc.text.magnifyingglass",
                title: "Get matched to jobs",
                message: "Upload your resume to see roles matched to your skills.",
                actionTitle: "Upload Resume",
                action: { dismiss() }
            )
            .padding(.horizontal, 16)

        } else {
            switch matchedJobs.state {
            case .idle, .loading:
                skeletonList

            case .failed(let message):
                DarkErrorView(message: message, retryAction: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    matchedJobs.retry()
                })
                .padding(.horizontal, 16)

            case .empty:
                DarkEmptyView(
                    title: "No matches found",
                    message: "We couldn't find entry-level roles for this resume right now. Check All Jobs or try again later.",
                    actionTitle: "Browse All Jobs",
                    action: { selectedTab = .allJobs }
                )
                .padding(.horizontal, 16)

            case .loaded:
                let visibleJobs = matchedJobs.visibleJobs

                JobsFilterBar(
                    sort: $matchedJobs.sort,
                    resultCount: visibleJobs.count
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                jobRows(visibleJobs)
            }
        }
    }

    // MARK: - All Jobs

    @ViewBuilder
    private var allJobsContent: some View {
        switch allJobs.state {
        case .idle, .loading:
            skeletonList

        case .failed(let message):
            DarkErrorView(message: message, retryAction: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                allJobs.retry()
            })
            .padding(.horizontal, 16)

        case .empty:
            DarkEmptyView(
                title: "No new grad jobs right now",
                message: "New openings are posted daily. Pull down to refresh or check back soon."
            )
            .padding(.horizontal, 16)

        case .loaded:
            JobsFilterBar(resultCount: allJobs.total ?? allJobs.jobs.count)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if let refreshError = allJobs.refreshError {
                DarkInlineBanner(message: refreshError, onDismiss: allJobs.dismissRefreshError)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            jobRows(allJobs.jobs)

            paginationFooter
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let loadMoreError = allJobs.loadMoreError {
            DarkInlineBanner(
                message: loadMoreError,
                actionTitle: "Retry",
                action: allJobs.retryLoadMore
            )
            .padding(.horizontal, 16)

        } else if allJobs.hasMore {
            ProgressView()
                .tint(Color(red: 0.55, green: 0.43, blue: 1.0))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .onAppear { allJobs.loadMoreIfNeeded() }

        } else {
            Text("You're all caught up")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.22))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    // MARK: - Shared Rows

    private var skeletonList: some View {
        ForEach(0..<5, id: \.self) { _ in
            DarkSkeletonCard()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private func jobRows(_ jobs: [Job]) -> some View {
        // Both tabs share one LazyVStack and a job has the same stable ID in
        // both lists, so scope row identity by tab; otherwise the lazy stack
        // can reuse a "For You" card (with its score) on the "All Jobs" tab.
        ForEach(jobs.map { TabScopedJob(tab: selectedTab, job: $0) }) { item in
            NavigationLink(destination: JobDetailView(job: item.job)) {
                DarkJobCard(
                    job: item.job,
                    isSaved: bookmarks.isSaved(item.job),
                    onBookmarkTap: { bookmarks.toggle(item.job) }
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

private struct TabScopedJob: Identifiable {
    let tab: JobsTab
    let job: Job

    var id: String { "\(tab.rawValue)-\(job.id.uuidString)" }
}

// MARK: - Tab Picker

struct JobsTabPicker: View {

    @Binding var selection: JobsTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(JobsTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundColor(selection == tab ? .white : .white.opacity(0.45))
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.5),
                                                Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.3)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "selectedTab", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .cornerRadius(16)
    }
}

// MARK: - Dark Job Card

struct DarkJobCard: View {

    let job: Job
    let isSaved: Bool
    let onBookmarkTap: () -> Void

    @State private var pulse = false

    private var iconColor: Color {
        switch job.matchScore {
        case (85...100)?: return Color(red: 0.39, green: 0.22, blue: 1.0)
        case (65..<85)?:  return Color(red: 0.0, green: 0.83, blue: 0.67)
        case nil:         return Color(red: 0.39, green: 0.22, blue: 1.0)
        default:          return Color(red: 0.98, green: 0.75, blue: 0.18)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {

            // Company icon
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(iconColor.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: "building.2.fill")
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
            }

            // Text column
            VStack(alignment: .leading, spacing: 5) {

                HStack(alignment: .top, spacing: 7) {
                    Text(job.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let matchScore = job.matchScore, matchScore >= 85 {
                        Text("TOP MATCH")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.5)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.75, blue: 0.18),
                                        Color(red: 0.98, green: 0.45, blue: 0.08)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .scaleEffect(pulse ? 1.04 : 1.0)
                            .fixedSize()
                            .onAppear {
                                withAnimation(
                                    .easeInOut(duration: 1.8)
                                    .repeatForever(autoreverses: true)
                                ) { pulse = true }
                            }
                    }
                }

                Text(job.company)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))

                Text(job.location)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.bottom, 6)

                // Real metadata from the posting (shown only when Adzuna provides it)
                if job.contractLabel != nil || job.postedAgoText != nil {
                    HStack(spacing: 6) {
                        if let contract = job.contractLabel {
                            DarkTag(text: contract, teal: false)
                        }
                        if let postedAgo = job.postedAgoText {
                            DarkTag(text: postedAgo, teal: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right controls
            VStack(spacing: 10) {

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onBookmarkTap()
                }) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(
                            isSaved
                            ? Color(red: 0.0, green: 0.83, blue: 0.67)
                            : .white.opacity(0.3)
                        )
                }

                if let matchScore = job.matchScore {
                    DarkMatchRing(score: matchScore)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .cornerRadius(20)
    }
}

// MARK: - Dark Tag

struct DarkTag: View {
    let text: String
    let teal: Bool

    var color: Color {
        teal
        ? Color(red: 0.0, green: 0.83, blue: 0.67)
        : Color(red: 0.39, green: 0.22, blue: 1.0)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.25), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Dark Match Ring

struct DarkMatchRing: View {

    let score: Int
    var size: CGFloat = 42
    var lineWidth: CGFloat = 4
    var isLoading = false

    @State private var progress: CGFloat = 0
    @State private var spin = false

    private var ringColors: [Color] {
        switch score {
        case 85...100: return [
            Color(red: 0.0, green: 0.83, blue: 0.67),
            Color(red: 0.39, green: 0.22, blue: 1.0)
        ]
        case 65..<85: return [
            Color(red: 0.39, green: 0.22, blue: 1.0),
            Color(red: 0.0, green: 0.83, blue: 0.67)
        ]
        default: return [
            Color(red: 0.98, green: 0.75, blue: 0.18),
            Color(red: 0.98, green: 0.45, blue: 0.08)
        ]
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)

            if isLoading {
                // Spinner instead of a (possibly stale) number
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(
                        Color(red: 0.55, green: 0.43, blue: 1.0),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(spin ? 270 : -90))
                    .onAppear {
                        spin = false
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            spin = true
                        }
                    }
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: ringColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(score)%")
                    .font(.system(size: max(9, size * 0.22), weight: .bold))
                    .foregroundColor(.white)
                    .contentTransition(.numericText(value: Double(score)))
                    .animation(.easeInOut(duration: 1.0), value: score)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "Calculating score" : "Match score \(score) percent")
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                progress = CGFloat(score) / 100
            }
        }
        // Animate from the previous value to the new one (not from zero)
        .onChange(of: score) { _, newScore in
            withAnimation(.easeInOut(duration: 1.0)) {
                progress = CGFloat(newScore) / 100
            }
        }
    }
}

// MARK: - Skeleton Card

struct DarkSkeletonCard: View {

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white.opacity(0.06))
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 9) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 10)
                    .frame(maxWidth: 160)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 9)
                    .frame(maxWidth: 100)

                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 58, height: 18)
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 84, height: 18)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .shimmering()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("Loading job")
    }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.07),
                            Color(red: 0.55, green: 0.43, blue: 1.0).opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: -geo.size.width * 0.6 + phase * geo.size.width * 1.6)
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Error View

struct DarkErrorView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundColor(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.7))

            Text("Couldn't load jobs")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            Button(action: retryAction) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.4),
                                lineWidth: 0.5
                            )
                    )
                    .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                    .cornerRadius(14)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .cornerRadius(20)
    }
}

// MARK: - Empty View

struct DarkEmptyView: View {
    var icon: String = "briefcase.fill"
    var title: String = "No matches found"
    var message: String = "Try uploading a different resume or check back later."
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.12))

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.28))
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.4),
                                    lineWidth: 0.5
                                )
                        )
                        .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                        .cornerRadius(14)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .cornerRadius(20)
    }
}

// MARK: - Inline Banner

struct DarkInlineBanner: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .background(Color(red: 1.0, green: 0.48, blue: 0.45).opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 1.0, green: 0.48, blue: 0.45).opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(14)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        JobListView(country: "in", selectedTab: .constant(.allJobs))
    }
    .environmentObject(BookmarkManager())
    .environmentObject(MatchedJobsViewModel())
    .environmentObject(AllJobsViewModel())
}
