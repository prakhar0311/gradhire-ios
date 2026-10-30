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

    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var matchedJobs: MatchedJobsViewModel
    @EnvironmentObject private var allJobs: AllJobsViewModel
    @EnvironmentObject private var search: JobSearchViewModel
    @EnvironmentObject private var resumeManager: ResumeManager

    @State private var confirmRemove: Job?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {

            AppBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {

                    header

                    JobsTabPicker(selection: $selectedTab)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    switch selectedTab {
                    case .forYou:  forYouContent
                    case .allJobs: allJobsSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                switch selectedTab {
                case .forYou:  await matchedJobs.refresh()
                case .allJobs where search.isSearching: await search.refresh()
                case .allJobs: await allJobs.refresh()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            AppTheme.base,
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
                AccountButton()
            }
        }
        .removeTrackedJobDialog(job: $confirmRemove)
        .onAppear {
            search.setCountry(country)
            if selectedTab == .allJobs {
                allJobs.loadIfNeeded(country: country)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            searchFocused = false
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
        switch resumeManager.availability {
        case .loading:
            // Signed in, still finding the active resume: never "Upload" here
            skeletonList

        case .failed:
            DarkErrorView(message: "We couldn't load your saved resume. Check your connection and try again.", retryAction: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                resumeManager.refreshAccount()
            })
            .padding(.horizontal, 16)

        case .none:
            DarkEmptyView(
                icon: "doc.text.magnifyingglass",
                title: "Get matched to jobs",
                message: "Upload your resume to see roles matched to your skills.",
                actionTitle: "Upload Resume",
                action: { router.show(.resume) }
            )
            .padding(.horizontal, 16)

        case .available:
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

    private var showsSuggestions: Bool {
        searchFocused && search.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var allJobsSection: some View {
        JobSearchField(text: $search.text, isFocused: $searchFocused, onSubmit: search.submit)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

        if showsSuggestions {
            JobSearchSuggestions(
                recentSearches: search.recentSearches,
                onSelect: { term in
                    search.select(term)
                    searchFocused = false
                },
                onRemoveRecent: search.removeRecentSearch
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        } else if search.isSearching {
            searchContent
        } else {
            allJobsContent
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchContent: some View {
        let query = search.activeQuery ?? ""

        switch search.state {
        case .idle, .loading:
            skeletonList

        case .failed(let message):
            DarkErrorView(message: message, retryAction: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                search.retry()
            })
            .padding(.horizontal, 16)

        case .empty:
            VStack(spacing: 18) {
                DarkEmptyView(
                    icon: "magnifyingglass",
                    title: "No jobs found for \u{201C}\(query)\u{201D}",
                    message: "Try a broader term, like a role or a skill."
                )
                SearchChips(
                    terms: JobSearchViewModel.suggestions.filter { $0.lowercased() != query.lowercased() },
                    onSelect: { term in
                        search.select(term)
                        searchFocused = false
                    }
                )
            }
            .padding(.horizontal, 16)

        case .loaded:
            Text(searchCountText(query))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.updatesFrequently)

            if let refreshError = search.refreshError {
                DarkInlineBanner(message: refreshError, onDismiss: search.dismissRefreshError)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            jobRows(search.jobs, onOpen: search.resultOpened)

            searchPaginationFooter
        }
    }

    private func searchCountText(_ query: String) -> String {
        let count = search.total
        let number = search.totalIsExact ? "\(count)" : "\(count)+"
        let noun = count == 1 && search.totalIsExact ? "job" : "jobs"
        return "\(number) \(noun) for \u{201C}\(query)\u{201D}"
    }

    @ViewBuilder
    private var searchPaginationFooter: some View {
        if let loadMoreError = search.loadMoreError {
            DarkInlineBanner(
                message: loadMoreError,
                actionTitle: "Retry",
                action: search.retryLoadMore
            )
            .padding(.horizontal, 16)

        } else if search.hasMore {
            ProgressView()
                .tint(AppTheme.violet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .onAppear { search.loadMoreIfNeeded() }

        } else {
            Text("That's every match")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.22))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    // MARK: - Feed

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
                .tint(AppTheme.violet)
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

    private func bookmarkTapped(_ job: Job) {
        if tracker.needsRemoveConfirmation(job.id) {
            confirmRemove = job
        } else {
            tracker.toggleSave(job)
        }
    }

    private var skeletonList: some View {
        ForEach(0..<5, id: \.self) { _ in
            DarkSkeletonCard()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private func jobRows(_ jobs: [Job], onOpen: (() -> Void)? = nil) -> some View {
        // Both tabs share one LazyVStack and a job has the same stable ID in
        // both lists, so scope row identity by tab; otherwise the lazy stack
        // can reuse a "For You" card (with its score) on the "All Jobs" tab.
        ForEach(jobs.map { TabScopedJob(tab: selectedTab, job: $0) }) { item in
            NavigationLink(destination: JobDetailView(job: item.job)) {
                DarkJobCard(
                    job: item.job,
                    status: tracker.status(for: item.job.id),
                    onBookmarkTap: { bookmarkTapped(item.job) }
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { onOpen?() })
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
                                                AppTheme.purple.opacity(0.5),
                                                AppTheme.teal.opacity(0.3)
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
    let status: ApplicationStatus?
    let onBookmarkTap: () -> Void

    @State private var pulse = false

    private var isSaved: Bool { status != nil }

    private var iconColor: Color {
        switch job.matchScore {
        case (85...100)?: return AppTheme.purple
        case (65..<85)?:  return AppTheme.teal
        case nil:         return AppTheme.purple
        default:          return AppTheme.amber
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
                                        AppTheme.amber,
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
                if status != nil || job.contractLabel != nil || job.postedAgoText != nil {
                    HStack(spacing: 6) {
                        if let status {
                            StatusBadge(status: status)
                        }
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
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundColor(
                            isSaved
                            ? AppTheme.teal
                            : .white.opacity(0.3)
                        )
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(isSaved ? "Remove from tracker" : "Save to tracker")

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
        ? AppTheme.teal
        : AppTheme.purple
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
            AppTheme.teal,
            AppTheme.purple
        ]
        case 65..<85: return [
            AppTheme.purple,
            AppTheme.teal
        ]
        default: return [
            AppTheme.amber,
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
                        AppTheme.violet,
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
                            AppTheme.violet.opacity(0.08),
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
                .foregroundColor(AppTheme.purple.opacity(0.7))

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
                    .background(AppTheme.purple.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                AppTheme.purple.opacity(0.4),
                                lineWidth: 0.5
                            )
                    )
                    .foregroundColor(AppTheme.lavender)
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
                        .background(AppTheme.purple.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    AppTheme.purple.opacity(0.4),
                                    lineWidth: 0.5
                                )
                        )
                        .foregroundColor(AppTheme.lavender)
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
                .foregroundColor(AppTheme.coral)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.lavender)
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
        .background(AppTheme.coral.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.coral.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(14)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        JobListView(country: "in", selectedTab: .constant(.allJobs))
    }
    .environmentObject(AppRouter())
    .environmentObject(MatchedJobsViewModel())
    .environmentObject(AllJobsViewModel())
}
