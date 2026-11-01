import SwiftUI

// MARK: - Status Colors

extension ApplicationStatus {

    var color: Color {
        switch self {
        case .saved:        return AppTheme.lavender
        case .applied:      return AppTheme.teal
        case .interviewing: return Color(red: 0.35, green: 0.68, blue: 1.0)
        case .offer:        return AppTheme.amber
        case .rejected:     return AppTheme.coral
        }
    }
}

// MARK: - Status Badge

/// "Saved" / "Applied" / … pill shown on job cards and in the tracker.
struct StatusBadge: View {

    let status: ApplicationStatus
    var showsIcon = true

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(systemName: status.icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(status.title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.12))
        .overlay(Capsule().stroke(status.color.opacity(0.3), lineWidth: 0.5))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(status.title)")
    }
}

// MARK: - Bookmark Confirmation

extension View {

    /// Tapping a filled bookmark: Applied or later only clears the bookmark;
    /// a Saved job with notes is removed (with its notes) after asking.
    func bookmarkConfirmationDialog(_ confirmation: Binding<TrackerStore.BookmarkConfirmation?>) -> some View {
        modifier(BookmarkConfirmationDialog(confirmation: confirmation))
    }
}

private struct BookmarkConfirmationDialog: ViewModifier {

    @Binding var confirmation: TrackerStore.BookmarkConfirmation?
    @EnvironmentObject private var tracker: TrackerStore

    private var title: String {
        if case .removeWithNotes = confirmation { return "Remove from tracker?" }
        return "Remove from saved jobs?"
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { confirmation in
            switch confirmation {
            case .removeWithNotes(let job):
                Button("Remove", role: .destructive) { tracker.remove(job.id) }
            case .unbookmark(let job, _):
                Button("Remove from saved", role: .destructive) { tracker.setBookmarked(false, for: job.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            switch confirmation {
            case .removeWithNotes(let job):
                Text("\(job.title) at \(job.company) and your notes will be removed from your tracker.")
            case .unbookmark(_, let status):
                Text("Your application status (\(status.title)) stays in your tracker.")
            }
        }
    }
}

// MARK: - Remove Confirmation

extension View {

    /// Asks before removing a job that's past Saved (its history is deleted).
    func removeTrackedJobDialog(job: Binding<Job?>) -> some View {
        modifier(RemoveTrackedJobDialog(job: job))
    }
}

private struct RemoveTrackedJobDialog: ViewModifier {

    @Binding var job: Job?
    @EnvironmentObject private var tracker: TrackerStore

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Remove from tracker?",
            isPresented: Binding(get: { job != nil }, set: { if !$0 { job = nil } }),
            titleVisibility: .visible,
            presenting: job
        ) { job in
            Button("Remove", role: .destructive) {
                tracker.remove(job.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { job in
            Text("\(job.title) at \(job.company) and its status history will be removed from your tracker.")
        }
    }
}

// MARK: - Bookmark Toolbar Button (job detail)

struct TrackJobButton: View {

    let job: Job

    @EnvironmentObject private var tracker: TrackerStore
    @State private var confirmation: TrackerStore.BookmarkConfirmation?

    var body: some View {
        let isBookmarked = tracker.isBookmarked(job.id)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            confirmation = tracker.bookmarkTapped(job)
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundColor(isBookmarked ? AppTheme.teal : .white.opacity(0.6))
        }
        .accessibilityLabel(isBookmarked ? "Remove from saved jobs" : "Save job")
        .bookmarkConfirmationDialog($confirmation)
    }
}
