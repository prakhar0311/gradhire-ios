import SwiftUI

// MARK: - Status Colors

extension ApplicationStatus {

    var color: Color {
        switch self {
        case .saved:        return Color(red: 0.65, green: 0.55, blue: 0.98)
        case .applied:      return Color(red: 0.0, green: 0.83, blue: 0.67)
        case .interviewing: return Color(red: 0.35, green: 0.68, blue: 1.0)
        case .offer:        return Color(red: 0.98, green: 0.75, blue: 0.18)
        case .rejected:     return Color(red: 1.0, green: 0.48, blue: 0.45)
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
    @State private var confirmRemove: Job?

    var body: some View {
        let status = tracker.status(for: job.id)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if tracker.needsRemoveConfirmation(job.id) {
                confirmRemove = job
            } else {
                tracker.toggleSave(job)
            }
        } label: {
            Image(systemName: status == nil ? "bookmark" : "bookmark.fill")
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundColor(
                    status == nil
                    ? .white.opacity(0.6)
                    : Color(red: 0.0, green: 0.83, blue: 0.67)
                )
        }
        .accessibilityLabel(status == nil ? "Save to tracker" : "Remove from tracker")
        .removeTrackedJobDialog(job: $confirmRemove)
    }
}
