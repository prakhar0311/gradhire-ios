import SwiftUI

// MARK: - Tracker Detail View

struct TrackerDetailView: View {

    let jobId: UUID

    @EnvironmentObject private var tracker: TrackerStore
    @Environment(\.dismiss) private var dismiss

    @State private var notes = ""
    @State private var didLoadNotes = false
    @State private var events: [ApplicationEventRecord]?
    @State private var confirmRemove: Job?
    @FocusState private var notesFocused: Bool

    private var item: TrackedApplication? { tracker.item(for: jobId) }

    var body: some View {
        ZStack {
            AppBackground()

            if let item {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        headerCard(item)
                        statusCard(item)
                        notesCard
                        actions(item)
                        historyCard(item)
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                // Removed (here or on another device)
                DarkEmptyView(
                    icon: "tray",
                    title: "Not in your tracker",
                    message: "This job was removed from your tracker.",
                    actionTitle: "Back",
                    action: { dismiss() }
                )
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.base, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("APPLICATION")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { notesFocused = false }
            }
        }
        .removeTrackedJobDialog(job: $confirmRemove)
        .onAppear {
            guard !didLoadNotes, let item else { return }
            notes = item.notes
            didLoadNotes = true
        }
        .onChange(of: notes) { _, newValue in
            guard didLoadNotes else { return }
            tracker.setNotes(newValue, for: jobId)
        }
        // Refetch once a status change has reached the server
        .task(id: "\(item?.status.rawValue ?? "")-\(item?.isPendingSync ?? true)") {
            guard item?.isPendingSync == false else { return }
            events = await tracker.events(for: jobId)
        }
    }

    // MARK: Header

    private func headerCard(_ item: TrackedApplication) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(item.snapshot.title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let score = item.snapshot.matchScore {
                    DarkMatchRing(score: score)
                }
            }

            Text(item.snapshot.company)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))

            if !item.snapshot.location.isEmpty {
                Text(item.snapshot.location)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }

            HStack(spacing: 8) {
                StatusBadge(status: item.status)
                Text(datesText(item))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.top, 6)
        }
        .glassCard()
    }

    private func datesText(_ item: TrackedApplication) -> String {
        var parts = ["Saved \(item.savedAt.formatted(.dateTime.day().month(.abbreviated)))"]
        if let appliedAt = item.appliedAt {
            parts.append("Applied \(appliedAt.formatted(.dateTime.day().month(.abbreviated)))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Status

    private func statusCard(_ item: TrackedApplication) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("STATUS")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(ApplicationStatus.allCases, id: \.self) { status in
                    let isSelected = status == item.status
                    Button {
                        guard !isSelected else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            tracker.setStatus(status, for: jobId)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: status.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(status.title)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(isSelected ? .white : status.color.opacity(0.85))
                        .background(isSelected ? status.color.opacity(0.35) : status.color.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(status.color.opacity(isSelected ? 0.7 : 0.25), lineWidth: isSelected ? 1 : 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .glassCard()
    }

    // MARK: Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("NOTES")

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Recruiter name, interview dates, follow-ups…")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .focused($notesFocused)
                    .accessibilityLabel("Notes")
            }

            Text("Saved automatically")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
        }
        .glassCard()
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ item: TrackedApplication) -> some View {
        VStack(spacing: 10) {
            ApplyLinkButton(job: item.job) {
                actionLabel("Apply / View Posting", icon: "arrow.up.right.square.fill", prominent: true)
            }

            NavigationLink(destination: JobDetailView(job: item.job)) {
                actionLabel("View Job Details", icon: "doc.text.magnifyingglass", prominent: false)
            }

            Button {
                if item.status == .saved {
                    tracker.remove(jobId)
                    dismiss()
                } else {
                    confirmRemove = item.job
                }
            } label: {
                Text("Remove from Tracker")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundColor(AppTheme.coral)
                    .background(AppTheme.coral.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppTheme.coral.opacity(0.25), lineWidth: 0.5)
                    )
                    .cornerRadius(14)
            }
        }
    }

    private func actionLabel(_ title: String, icon: String, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.vertical, 15)
        .foregroundColor(.white.opacity(prominent ? 1 : 0.8))
        .background {
            if prominent {
                LinearGradient(
                    colors: [AppTheme.purple, AppTheme.teal],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color.white.opacity(0.06)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .cornerRadius(16)
    }

    // MARK: History

    @ViewBuilder
    private func historyCard(_ item: TrackedApplication) -> some View {
        if let events, !events.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("HISTORY")

                ForEach(events) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(event.toStatus.color)
                            .frame(width: 8, height: 8)
                        Text(historyText(event))
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(event.changedAt.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .glassCard()
        }
    }

    private func historyText(_ event: ApplicationEventRecord) -> String {
        guard let from = event.fromStatus else { return "Added as \(event.toStatus.title)" }
        return "\(from.title) → \(event.toStatus.title)"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.3))
    }
}

// MARK: - Glass Card

private extension View {
    func glassCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
