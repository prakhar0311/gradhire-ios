import SwiftUI

// MARK: - Tracker View

struct TrackerView: View {

    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: AppSession
    @StateObject private var network = NetworkMonitor.shared

    @State private var confirmRemove: Job?
    @State private var statusChoice: TrackedApplication?

    private var visibleItems: [TrackedApplication] {
        guard let filter = router.trackerFilter else { return tracker.items }
        return tracker.items.filter { $0.status == filter }
    }

    var body: some View {
        ZStack {
            AppBackground()

            if !tracker.isSignedIn {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        guestCard
                    }
                    .padding(.top, 16)
                }
            } else {
                list
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.base, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("TRACKER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                AccountButton()
            }
        }
        .removeTrackedJobDialog(job: $confirmRemove)
        .confirmationDialog(
            "Change status",
            isPresented: Binding(get: { statusChoice != nil }, set: { if !$0 { statusChoice = nil } }),
            titleVisibility: .visible,
            presenting: statusChoice
        ) { item in
            ForEach(ApplicationStatus.allCases, id: \.self) { status in
                Button(status == item.status ? "\(status.title) (current)" : status.title) {
                    changeStatus(item, to: status)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: List

    private var list: some View {
        List {
            Group {
                header
                filterChips
                    .padding(.bottom, 12)

                if let banner = syncBanner {
                    banner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if tracker.items.isEmpty && !tracker.hasSynced && tracker.isSyncing {
                    ForEach(0..<4, id: \.self) { _ in
                        DarkSkeletonCard()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                } else if tracker.items.isEmpty {
                    emptyState
                } else if visibleItems.isEmpty {
                    filteredEmptyState
                } else {
                    ForEach(visibleItems) { item in
                        row(item)
                    }
                }

                Spacer(minLength: 40)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .refreshable { await tracker.sync() }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visibleItems)
    }

    private func row(_ item: TrackedApplication) -> some View {
        TrackerRow(item: item)
            .background(
                NavigationLink("", destination: TrackerDetailView(jobId: item.jobId))
                    .opacity(0)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let next = item.status.next {
                    Button {
                        changeStatus(item, to: next)
                    } label: {
                        Label(next.title, systemImage: next.icon)
                    }
                    .tint(next.color.opacity(0.85))
                }
                Button {
                    statusChoice = item
                } label: {
                    Label("Status", systemImage: "ellipsis.circle")
                }
                .tint(AppTheme.purple)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: item.status == .saved) {
                Button(role: item.status == .saved ? .destructive : nil) {
                    remove(item)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .tint(AppTheme.coral)
            }
            .contextMenu {
                ForEach(ApplicationStatus.allCases, id: \.self) { status in
                    Button {
                        changeStatus(item, to: status)
                    } label: {
                        Label(status.title, systemImage: status.icon)
                    }
                    .disabled(status == item.status)
                }
                Divider()
                Button(role: .destructive) {
                    remove(item)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
    }

    private func changeStatus(_ item: TrackedApplication, to status: ApplicationStatus) {
        guard status != item.status else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        tracker.setStatus(status, for: item.jobId)
    }

    private func remove(_ item: TrackedApplication) {
        if item.status == .saved {
            tracker.remove(item.jobId)
        } else {
            confirmRemove = item.job
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Applications")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text(
                tracker.isSignedIn
                ? "Every job you've saved or applied to, in one place"
                : "Keep track of every job you apply to"
            )
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", count: tracker.count(for: nil), status: nil)
                ForEach(ApplicationStatus.allCases, id: \.self) { status in
                    chip(title: status.title, count: tracker.count(for: status), status: status)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, count: Int, status: ApplicationStatus?) -> some View {
        let isSelected = router.trackerFilter == status
        let tint = status?.color ?? AppTheme.lavender

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                router.trackerFilter = status
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(isSelected ? 0.2 : 0.08))
                    .clipShape(Capsule())
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : .white.opacity(0.55))
            .background(isSelected ? tint.opacity(0.3) : Color.white.opacity(0.05))
            .overlay(
                Capsule().stroke(isSelected ? tint.opacity(0.6) : Color.white.opacity(0.09), lineWidth: 0.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Banners and Empty States

    private var syncBanner: DarkInlineBanner? {
        if !network.isConnected {
            guard tracker.pendingCount > 0 else { return nil }
            let count = tracker.pendingCount
            return DarkInlineBanner(
                message: "You're offline. \(count) change\(count == 1 ? "" : "s") will sync when you're back online."
            )
        }
        if let error = tracker.syncError {
            return DarkInlineBanner(
                message: error,
                actionTitle: "Retry",
                action: { Task { await tracker.sync() } }
            )
        }
        return nil
    }

    private var emptyState: some View {
        DarkEmptyView(
            icon: "bookmark",
            title: "No applications yet",
            message: "Tap the bookmark on any job to save it here, then track it from Saved to Offer.",
            actionTitle: "Browse jobs",
            action: { router.show(.jobs) }
        )
        .padding(.horizontal, 16)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: router.trackerFilter?.icon ?? "tray")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.25))
            Text("Nothing in \(router.trackerFilter?.title ?? "this list") yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Button("Show all") {
                withAnimation { router.trackerFilter = nil }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.lavender)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var guestCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.purple, AppTheme.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                Image(systemName: "checklist")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("Sign in to track your applications")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Save jobs, mark them as applied, and follow each one through to an offer, on any device.")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.45))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                session.requireAccount(.tracker)
            } label: {
                Text("Sign In")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.purple, AppTheme.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.top, 4)

            Button("Browse jobs") { router.show(.jobs) }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(22)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
        .cornerRadius(20)
        .padding(.horizontal, 16)
    }
}

// MARK: - Tracker Row

struct TrackerRow: View {

    let item: TrackedApplication

    private var dateText: String {
        if item.status.hasApplied, let appliedAt = item.appliedAt {
            return "Applied \(Self.relative(appliedAt))"
        }
        return "Updated \(Self.relative(item.updatedAt))"
    }

    static func relative(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: date),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0

        switch days {
        case ..<1: return "today"
        case 1:    return "yesterday"
        case 2..<7: return "\(days) days ago"
        default:   return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(item.status.color.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(item.status.color.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 20))
                    .foregroundColor(item.status.color)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.snapshot.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.snapshot.company)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    StatusBadge(status: item.status)
                    Text(dateText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    if item.isPendingSync {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.3))
                            .accessibilityLabel("Waiting to sync")
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.2))
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
