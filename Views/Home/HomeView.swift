import SwiftUI

// MARK: - Home (Dashboard)

struct HomeView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var matchedJobs: MatchedJobsViewModel
    @EnvironmentObject private var dashboard: DashboardViewModel

    @State private var showSignIn = false
    @State private var showGoalEditor = false
    @State private var goalError = false
    @State private var since: Date?

    private var isSignedIn: Bool { tracker.isSignedIn }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.25), Color.clear],
                        center: .init(x: 0.2, y: 0.1),
                        startRadius: 0,
                        endRadius: 300
                    )
                    RadialGradient(
                        colors: [Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.15), Color.clear],
                        center: .init(x: 0.85, y: 0.4),
                        startRadius: 0,
                        endRadius: 260
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.55)
                .ignoresSafeArea()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    greeting

                    ResumeCardSection(
                        readiness: readiness,
                        readinessLoading: readinessLoading,
                        isSignedIn: isSignedIn
                    )

                    if isSignedIn {
                        PipelineSection()
                        ThisWeekSection(showGoalEditor: $showGoalEditor)
                        FollowUpsSection()
                    }

                    NewMatchesSection(matches: newMatches, totalMatches: matches.count, phase: matchesPhase)

                    if isSignedIn {
                        SkillGapSection(matches: matches, phase: matchesPhase)
                        RecentActivitySection()
                    } else {
                        guestCard
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isSignedIn)
            }
            .refreshable { await refreshAll() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.04, green: 0.04, blue: 0.06), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("HOME")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                AccountButton()
            }
        }
        .onAppear {
            if since == nil { since = dashboard.sinceLastVisit(for: auth.user?.id.uuidString ?? "guest") }
            dashboard.scheduleRefresh(accountResumeId: resumeManager.accountResumeId(for: auth.user?.id))
        }
        .onChange(of: auth.user?.id) { _, id in
            since = dashboard.sinceLastVisit(for: id?.uuidString ?? "guest")
            dashboard.scheduleRefresh(accountResumeId: resumeManager.accountResumeId(for: id))
        }
        .sheet(isPresented: $showSignIn) {
            AccountView(reason: "Sign in to track your applications", dismissOnSignIn: true)
                .environmentObject(auth)
                .environmentObject(resumeManager)
                .environmentObject(tracker)
        }
        .sheet(isPresented: $showGoalEditor) {
            WeeklyGoalEditor(current: dashboard.data.weeklyGoal) { goal in
                Task { goalError = !(await dashboard.setWeeklyGoal(goal)) }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .alert("Couldn't save your goal", isPresented: $goalError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }

    private func refreshAll() async {
        async let trackerSync: Void = tracker.sync()
        async let serverData: Void = dashboard.refresh(
            accountResumeId: resumeManager.accountResumeId(for: auth.user?.id)
        )
        if matchedJobs.hasResume {
            await matchedJobs.refresh()
        }
        _ = await (trackerSync, serverData)
    }

    // MARK: Matches (this device first, then the account)

    /// Matches loaded on this device win; otherwise the account's stored ones.
    private var matches: [DashboardMatch] {
        if matchedJobs.hasLoaded {
            return matchedJobs.jobs.map { DashboardMatch(job: $0) }.sorted { $0.score > $1.score }
        }
        return isSignedIn ? dashboard.data.matches : []
    }

    private var matchesPhase: MatchesPhase {
        if matchedJobs.hasLoaded { return .loaded }
        if isSignedIn && !dashboard.data.matches.isEmpty { return .loaded }

        switch matchedJobs.state {
        case .loading:
            return .loading
        case .failed:
            if isSignedIn && dashboard.matchesStatus == .loading { return .loading }
            return .failed { matchedJobs.retry() }
        default:
            if matchedJobs.hasResume { return .loading }
            if isSignedIn && dashboard.matchesStatus == .loading && !dashboard.hasData { return .loading }
            if isSignedIn && dashboard.matchesStatus == .failed && dashboard.data.resume != nil {
                return .failed {
                    dashboard.scheduleRefresh(accountResumeId: resumeManager.accountResumeId(for: auth.user?.id))
                }
            }
            return .noResume
        }
    }

    private var newMatches: [DashboardMatch] {
        let cutoff = since ?? .distantPast
        return Array(
            matches
                .filter { ($0.postedAt ?? .distantPast) > cutoff }
                .sorted { $0.score > $1.score }
                .prefix(3)
        )
    }

    /// The average of the top 10 match scores (same as the backend).
    private var readiness: Int? {
        if matchedJobs.hasLoaded {
            let top = matchedJobs.jobs.compactMap(\.matchScore).sorted(by: >).prefix(10)
            guard !top.isEmpty else { return nil }
            return Int((Double(top.reduce(0, +)) / Double(top.count)).rounded())
        }
        return isSignedIn ? dashboard.data.resume?.readinessScore : nil
    }

    private var readinessLoading: Bool {
        readiness == nil && matchedJobs.hasResume && !matchedJobs.hasLoaded && !isFailed(matchedJobs.state)
    }

    private func isFailed(_ state: JobsLoadState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Hi \(firstName) 👋")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(isSignedIn ? "Here's where your job search stands" : "Find and land your first role")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private var firstName: String {
        guard let name = auth.user?.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return "there"
        }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: Guest

    private var guestCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.39, green: 0.22, blue: 1.0), Color(red: 0.0, green: 0.83, blue: 0.67)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Track your progress")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Sign in to track applications, set a weekly goal and get follow-up reminders.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                DashboardButton(title: "Sign In", prominent: true) { showSignIn = true }
            }
        }
    }
}

// MARK: - Matches Phase

enum MatchesPhase {
    case loading
    case loaded
    case failed(retry: () -> Void)
    case noResume
}

// MARK: - Resume Card

private struct ResumeCardSection: View {

    let readiness: Int?
    let readinessLoading: Bool
    let isSignedIn: Bool

    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var dashboard: DashboardViewModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthViewModel

    private var serverResume: ResumeCardData? { isSignedIn ? dashboard.data.resume : nil }

    private var title: String? {
        if resumeManager.hasResume { return resumeManager.fileName ?? "Your resume" }
        return serverResume?.title
    }

    private var isLinked: Bool { resumeManager.accountResumeId(for: auth.user?.id) != nil }

    var body: some View {
        DashboardCard(title: "YOUR RESUME") {
            if let title {
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 4) {
                        DarkMatchRing(score: readiness ?? 0, size: 64, lineWidth: 6, isLoading: readinessLoading)
                            .opacity(readiness == nil && !readinessLoading ? 0.35 : 1)
                        Text("Readiness")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(readiness.map { "Readiness \($0) out of 100" } ?? "Readiness not available yet")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                        if isSignedIn {
                            Text(tailoredText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.83, blue: 0.67))
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    DashboardButton(title: "Improve", icon: "wand.and.stars", prominent: true) {
                        router.jobsTab = .forYou
                        router.tab = .jobs
                    }
                    DashboardButton(title: "Upload new", icon: "arrow.up.doc", prominent: false) {
                        router.tab = .resume
                    }
                }
                .padding(.top, 4)

                Text("Readiness is the average match score of your top 10 matches. Improve a resume for a job to raise it.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.28))
                    .fixedSize(horizontal: false, vertical: true)

            } else if isSignedIn && dashboard.resumeStatus == .loading && !dashboard.hasData {
                SkeletonLines(count: 3)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Upload your resume to get matched to jobs and see your readiness score.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    DashboardButton(title: "Upload resume", icon: "arrow.up.doc.fill", prominent: true) {
                        router.tab = .resume
                    }
                }
            }
        }
    }

    private var subtitle: String {
        if resumeManager.hasResume {
            let date = resumeManager.uploadedAt.map { " · added \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? ""
            return (isLinked ? "Saved to your account" : "On this device only") + date
        }
        return "Saved to your account"
    }

    private var tailoredText: String {
        if resumeManager.hasResume && !isLinked {
            return "Save it to your account to keep tailored versions"
        }
        let count = dashboard.data.tailoredCount
        return count == 0 ? "No tailored versions yet" : "\(count) tailored version\(count == 1 ? "" : "s")"
    }
}

// MARK: - Pipeline

private struct PipelineSection: View {

    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        DashboardCard(title: "APPLICATION PIPELINE") {
            if tracker.items.isEmpty && !tracker.hasSynced && tracker.isSyncing {
                SkeletonLines(count: 2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(ApplicationStatus.allCases, id: \.self) { status in
                        tile(status)
                    }
                }

                if tracker.items.isEmpty {
                    DashboardButton(title: "Find your first job", icon: "magnifyingglass", prominent: false) {
                        router.jobsTab = .allJobs
                        router.tab = .jobs
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func tile(_ status: ApplicationStatus) -> some View {
        let count = tracker.count(for: status)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            router.trackerFilter = status
            router.tab = .tracker
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(count == 0 ? .white.opacity(0.35) : .white)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    Image(systemName: status.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(status.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(status.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(status.color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(status.color.opacity(0.22), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.title): \(count). Show in tracker")
    }
}

// MARK: - This Week

private struct ThisWeekSection: View {

    @Binding var showGoalEditor: Bool

    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var dashboard: DashboardViewModel

    private var appliedThisWeek: Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return tracker.items.filter { item in
            guard item.status.hasApplied, let appliedAt = item.appliedAt else { return false }
            return week.contains(appliedAt)
        }.count
    }

    var body: some View {
        DashboardCard(title: "THIS WEEK") {
            HStack(spacing: 16) {
                if let goal = dashboard.data.weeklyGoal {
                    GoalRing(value: appliedThisWeek, goal: goal)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(appliedThisWeek) application\(appliedThisWeek == 1 ? "" : "s")")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                    Text(goalText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)

                if dashboard.goalStatus == .failed && !dashboard.hasData {
                    Button("Retry") { dashboard.retryGoal() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                } else {
                    Button(dashboard.data.weeklyGoal == nil ? "Set goal" : "Edit") {
                        showGoalEditor = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                    .disabled(dashboard.goalStatus == .loading && !dashboard.hasData)
                    .accessibilityLabel(dashboard.data.weeklyGoal == nil ? "Set a weekly goal" : "Edit weekly goal")
                }
            }
        }
    }

    private var goalText: String {
        guard let goal = dashboard.data.weeklyGoal else { return "Applied since Monday. Set an optional weekly goal." }
        if appliedThisWeek >= goal { return "Goal of \(goal) reached. Nice work! 🎉" }
        let left = goal - appliedThisWeek
        return "\(left) more to reach your goal of \(goal)"
    }
}

private struct GoalRing: View {

    let value: Int
    let goal: Int

    @State private var progress: CGFloat = 0

    private var target: CGFloat { min(CGFloat(value) / CGFloat(max(goal, 1)), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [Color(red: 0.39, green: 0.22, blue: 1.0), Color(red: 0.0, green: 0.83, blue: 0.67)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(value)/\(goal)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 58, height: 58)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { progress = target } }
        .onChange(of: target) { _, newValue in withAnimation(.easeOut(duration: 0.5)) { progress = newValue } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) of \(goal) applications this week")
    }
}

private struct WeeklyGoalEditor: View {

    let current: Int?
    let onSave: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var goal = 5

    var body: some View {
        VStack(spacing: 18) {
            Text("Weekly goal")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 24)

            Text("How many jobs do you want to apply to each week?")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Stepper(value: $goal, in: 1...50) {
                Text("\(goal) application\(goal == 1 ? "" : "s") a week")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(14)

            DashboardButton(title: "Save Goal", prominent: true) {
                onSave(goal)
                dismiss()
            }

            if current != nil {
                Button("Turn off goal") {
                    onSave(nil)
                    dismiss()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.07, blue: 0.1).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { goal = current ?? 5 }
    }
}

// MARK: - Follow-ups

private struct FollowUpsSection: View {

    @EnvironmentObject private var tracker: TrackerStore

    private var due: [TrackedApplication] {
        tracker.items
            .filter { $0.isFollowUpDue() }
            .sorted { ($0.appliedAt ?? .distantPast) < ($1.appliedAt ?? .distantPast) }
    }

    var body: some View {
        let due = due
        DashboardCard(title: "FOLLOW-UPS DUE") {
            if due.isEmpty {
                EmptyLine(icon: "checkmark.circle", text: "You're all caught up. Applications waiting 7+ days show up here.")
            } else {
                ForEach(due.prefix(3)) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.snapshot.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(item.snapshot.company) · applied \(TrackerRow.relative(item.appliedAt ?? Date()))")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)

                        NavigationLink(destination: TrackerDetailView(jobId: item.jobId)) {
                            Text("Open")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.07))
                                .foregroundColor(.white.opacity(0.8))
                                .clipShape(Capsule())
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation { tracker.markFollowedUp(item.jobId) }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.18))
                                .foregroundColor(Color(red: 0.0, green: 0.83, blue: 0.67))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Mark followed up")
                    }
                    .padding(.vertical, 2)
                }
                if due.count > 3 {
                    Text("and \(due.count - 3) more in your tracker")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
    }
}

// MARK: - New Matches

private struct NewMatchesSection: View {

    let matches: [DashboardMatch]
    let totalMatches: Int
    let phase: MatchesPhase

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        DashboardCard(title: "NEW MATCHES FOR YOU", actionTitle: totalMatches > 0 ? "See all" : nil, onAction: seeAll) {
            switch phase {
            case .loading:
                SkeletonLines(count: 3)
            case .failed(let retry):
                RetryLine(text: "Couldn't load your matches.", retry: retry)
            case .noResume:
                EmptyLine(icon: "doc.text.magnifyingglass", text: "Upload your resume to see jobs matched to your skills.")
            case .loaded:
                if matches.isEmpty {
                    EmptyLine(icon: "sparkles", text: "No new matches since your last visit. Check back tomorrow.")
                } else {
                    ForEach(matches) { match in
                        NavigationLink(destination: JobDetailView(job: match.job)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(match.company)
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.45))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                DarkMatchRing(score: match.score, size: 38, lineWidth: 3.5)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func seeAll() {
        router.jobsTab = .forYou
        router.tab = .jobs
    }
}

// MARK: - Skill Gaps

private struct SkillGapSection: View {

    let matches: [DashboardMatch]
    let phase: MatchesPhase

    /// Skills most often missing across the matches (no extra requests).
    private var gaps: [(skill: String, count: Int)] {
        var counts: [String: Int] = [:]
        for match in matches {
            for skill in Set(match.missingSkills) { counts[skill, default: 0] += 1 }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5)
            .map { (skill: $0.key, count: $0.value) }
    }

    var body: some View {
        DashboardCard(title: "SKILL GAPS") {
            switch phase {
            case .loading:
                SkeletonLines(count: 3)
            case .failed(let retry):
                RetryLine(text: "Couldn't load skill insights.", retry: retry)
            case .noResume:
                EmptyLine(icon: "chart.bar", text: "Skill insights appear once your resume is matched to jobs.")
            case .loaded:
                let gaps = gaps
                if gaps.isEmpty {
                    EmptyLine(icon: "checkmark.seal", text: "Your resume covers the skills your matches ask for.")
                } else {
                    let maxCount = gaps.first?.count ?? 1
                    ForEach(gaps, id: \.skill) { gap in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(gap.skill)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("in \(gap.count) of \(matches.count) matches")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(red: 0.39, green: 0.22, blue: 1.0), Color(red: 0.0, green: 0.83, blue: 0.67)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geo.size.width * CGFloat(gap.count) / CGFloat(max(maxCount, 1)))
                                    }
                            }
                            .frame(height: 5)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(gap.skill) appears in \(gap.count) of your \(matches.count) matches")
                    }
                    if let top = gaps.first {
                        Text("\(top.skill) appears in \(top.count) of your matches. Adding it (if you have it) could raise your scores.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Recent Activity

private struct RecentActivitySection: View {

    @EnvironmentObject private var dashboard: DashboardViewModel
    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var auth: AuthViewModel

    var body: some View {
        DashboardCard(title: "RECENT ACTIVITY") {
            if dashboard.activityStatus == .loading && !dashboard.hasData {
                SkeletonLines(count: 3)
            } else if dashboard.activityStatus == .failed && dashboard.data.activity.isEmpty {
                RetryLine(text: "Couldn't load your activity.") {
                    dashboard.scheduleRefresh(accountResumeId: resumeManager.accountResumeId(for: auth.user?.id))
                }
            } else if dashboard.data.activity.isEmpty {
                EmptyLine(icon: "clock", text: "Saving, applying and tailoring resumes will show up here.")
            } else {
                ForEach(dashboard.data.activity) { item in
                    if let jobId = item.jobId, tracker.item(for: jobId) != nil {
                        NavigationLink(destination: TrackerDetailView(jobId: jobId)) {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(item)
                    }
                }
            }
        }
    }

    private func row(_ item: ActivityItem) -> some View {
        let color = item.status?.color ?? Color(red: 0.65, green: 0.55, blue: 0.98)
        return HStack(spacing: 10) {
            Image(systemName: item.status?.icon ?? "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(TrackerRow.relative(item.date))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Building Blocks

private struct DashboardCard<Content: View>: View {

    var title: String? = nil
    var actionTitle: String? = nil
    var onAction: () -> Void = {}
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || actionTitle != nil {
                HStack {
                    if let title {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.3))
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    if let actionTitle {
                        Button(actionTitle, action: onAction)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct DashboardButton: View {

    let title: String
    var icon: String? = nil
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(.white.opacity(prominent ? 1 : 0.8))
            .background {
                if prominent {
                    LinearGradient(
                        colors: [Color(red: 0.39, green: 0.22, blue: 1.0), Color(red: 0.0, green: 0.83, blue: 0.67)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

private struct SkeletonLines: View {

    let count: Int
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(shimmer ? 0.09 : 0.04))
                    .frame(height: 14)
                    .frame(maxWidth: index == count - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { shimmer = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

private struct EmptyLine: View {

    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RetryLine: View {

    let text: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button("Retry", action: retry)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
        }
    }
}
