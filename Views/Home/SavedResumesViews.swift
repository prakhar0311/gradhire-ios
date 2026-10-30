import SwiftUI
import QuickLook

// MARK: - Saved Resumes (Home section)

/// "Your saved resumes" on the dashboard: the newest three resumes with
/// their tailored versions, which one is active, and usage against the limit.
struct SavedResumesSection: View {

    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = SavedResumesViewModel()
    @State private var showsAll = false

    private static let shownGroups = 3

    var body: some View {
        let groups = resumeManager.resumeGroups

        DashboardCard(
            title: "YOUR SAVED RESUMES",
            actionTitle: groups.count > Self.shownGroups ? "See all" : nil,
            onAction: { showsAll = true }
        ) {
            if resumeManager.savedResumes.isEmpty {
                emptyContent
            } else {
                SavedResumesUsage()

                VStack(spacing: 4) {
                    ForEach(Array(groups.prefix(Self.shownGroups))) { group in
                        SavedResumeGroupRows(group: group, viewModel: viewModel)
                    }
                }

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.coral)
                }
            }
        }
        .savedResumeActions(viewModel)
        .navigationDestination(isPresented: $showsAll) {
            SavedResumesListView()
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch resumeManager.accountStatus {
        case .idle, .loading:
            SkeletonLines(count: 2)
        case .failed:
            RetryLine(text: "Couldn't load your resumes.") { resumeManager.refreshAccount() }
        case .loaded:
            VStack(alignment: .leading, spacing: 10) {
                EmptyLine(icon: "tray", text: "No saved resumes yet")
                DashboardButton(title: "Upload resume", icon: "arrow.up.doc.fill", prominent: true) {
                    router.show(.resume)
                }
            }
        }
    }
}

// MARK: - Full List

struct SavedResumesListView: View {

    /// Shown in a sheet (from the limit message) rather than pushed.
    var isSheet = false

    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SavedResumesViewModel()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if resumeManager.savedResumes.isEmpty {
                        DashboardCard {
                            VStack(alignment: .leading, spacing: 10) {
                                EmptyLine(icon: "tray", text: "No saved resumes yet")
                                uploadButton
                            }
                        }
                    } else {
                        SavedResumesUsage()
                            .padding(.horizontal, 4)

                        ForEach(resumeManager.resumeGroups) { group in
                            DashboardCard {
                                SavedResumeGroupRows(group: group, viewModel: viewModel)
                            }
                        }

                        if let message = viewModel.errorMessage {
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.coral)
                                .padding(.horizontal, 4)
                        }

                        if !resumeManager.isAtOriginalLimit {
                            uploadButton
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .refreshable { await resumeManager.reloadAccount() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.base, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SAVED RESUMES")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.lavender)
                }
            }
        }
        .savedResumeActions(viewModel)
    }

    private var uploadButton: some View {
        DashboardButton(title: "Upload a resume", icon: "arrow.up.doc.fill", prominent: true) {
            if isSheet { dismiss() }
            router.show(.resume)
        }
    }
}

// MARK: - Usage

/// "2 of 3 resumes saved · 4 of 10 tailored versions"
struct SavedResumesUsage: View {

    @EnvironmentObject private var resumeManager: ResumeManager

    var body: some View {
        let limits = resumeManager.limits
        Text("\(resumeManager.originalCount) of \(limits.maxOriginals) resumes saved · \(resumeManager.versionCount) of \(limits.maxVersions) tailored versions")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(resumeManager.isAtOriginalLimit ? AppTheme.amber : .white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Group Rows

/// An original with its versions indented under it.
struct SavedResumeGroupRows: View {

    let group: SavedResumeGroup
    @ObservedObject var viewModel: SavedResumesViewModel

    var body: some View {
        VStack(spacing: 2) {
            if let original = group.original {
                SavedResumeRow(resume: original, viewModel: viewModel)
            }
            ForEach(group.versions) { version in
                SavedResumeRow(resume: version, viewModel: viewModel)
                    .padding(.leading, group.original == nil ? 0 : 22)
            }
        }
    }
}

// MARK: - Row

struct SavedResumeRow: View {

    let resume: SavedResume
    @ObservedObject var viewModel: SavedResumesViewModel

    @EnvironmentObject private var resumeManager: ResumeManager

    private var isActive: Bool { resume.id == resumeManager.activeResumeId }
    private var isBusy: Bool { viewModel.busyId == resume.id }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.view(resume, using: resumeManager)
            } label: {
                HStack(spacing: 12) {
                    icon
                    details
                    Spacer(minLength: 4)
                    trailing
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the resume")

            actionsMenu
        }
        .padding(.vertical, 6)
    }

    private var icon: some View {
        let size: CGFloat = resume.isVersion ? 30 : 36
        let color = resume.isVersion ? AppTheme.violet : AppTheme.teal
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: resume.isVersion ? "wand.and.stars" : "doc.text.fill")
                .font(.system(size: resume.isVersion ? 12 : 15))
                .foregroundColor(color)
        }
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(resume.displayTitle)
                    .font(.system(size: resume.isVersion ? 13 : 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(AppTheme.base)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.teal, in: Capsule())
                        .accessibilityLabel("Active, used for matching")
                }
            }
            Text("\(resume.typeLabel) · \(resume.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isBusy {
            ProgressView()
                .tint(AppTheme.violet)
                .frame(width: 32, height: 32)
        } else if let score = resume.readinessScore {
            DarkMatchRing(score: score, size: 32, lineWidth: 3)
                .accessibilityLabel("Readiness \(score)")
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                viewModel.view(resume, using: resumeManager)
            } label: {
                Label("View", systemImage: "doc.text.magnifyingglass")
            }
            if !isActive {
                Button {
                    viewModel.setActive(resume, using: resumeManager)
                } label: {
                    Label("Set as active", systemImage: "checkmark.circle")
                }
            }
            Button {
                viewModel.startRename(resume)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                viewModel.share(resume, using: resumeManager)
            } label: {
                Label(resume.hasFile ? "Share / Download" : "Share (no PDF saved)", systemImage: "square.and.arrow.up")
            }
            .disabled(!resume.hasFile)
            Divider()
            Button(role: .destructive) {
                viewModel.deleting = resume
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .disabled(isBusy)
        .accessibilityLabel("Actions for \(resume.displayTitle)")
    }
}

// MARK: - Actions (preview, share, rename, delete)

private struct SavedResumeActions: ViewModifier {

    @ObservedObject var viewModel: SavedResumesViewModel
    @EnvironmentObject private var resumeManager: ResumeManager

    func body(content: Content) -> some View {
        content
            .quickLookPreview($viewModel.previewURL)
            .onChange(of: viewModel.previewURL) { _, url in
                if url == nil { viewModel.removeTemporaryFiles() }
            }
            .sheet(item: $viewModel.shareURL, onDismiss: viewModel.removeTemporaryFiles) { url in
                ShareSheet(items: [url])
            }
            .sheet(item: $viewModel.textPreview) { preview in
                ResumeTextPreview(preview: preview)
            }
            .alert(
                "Rename resume",
                isPresented: Binding(
                    get: { viewModel.renaming != nil },
                    set: { if !$0 { viewModel.renaming = nil } }
                )
            ) {
                TextField("Name", text: $viewModel.renameText)
                Button("Save") { viewModel.commitRename(using: resumeManager) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete \u{201C}\(viewModel.deleting?.displayTitle ?? "")\u{201D}?",
                isPresented: Binding(
                    get: { viewModel.deleting != nil },
                    set: { if !$0 { viewModel.deleting = nil } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.deleting
            ) { _ in
                Button("Delete", role: .destructive) { viewModel.confirmDelete(using: resumeManager) }
                Button("Cancel", role: .cancel) {}
            } message: { resume in
                Text(viewModel.deleteMessage(for: resume, in: resumeManager))
            }
    }
}

extension View {
    func savedResumeActions(_ viewModel: SavedResumesViewModel) -> some View {
        modifier(SavedResumeActions(viewModel: viewModel))
    }
}

// MARK: - Text Preview

/// For tailored versions saved before they had a PDF.
private struct ResumeTextPreview: View {

    let preview: SavedResumesViewModel.TextPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    Text(preview.text)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
            .navigationTitle(preview.title)
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

// MARK: - Limit Sheet

/// "You can save up to 3 resumes. Delete one to save a new one."
struct ResumeLimitSheet: View {

    let prompt: AppSession.ResumeLimitPrompt

    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var resumeManager: ResumeManager
    @Environment(\.dismiss) private var dismiss

    private var message: String {
        switch prompt {
        case .originals:
            return "You can save up to \(resumeManager.limits.maxOriginals) resumes. Delete one to save a new one."
        case .versions:
            return "You can save up to \(resumeManager.limits.maxVersions) tailored versions. Delete one to save a new one."
        }
    }

    var body: some View {
        ZStack {
            AppTheme.base.ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.amber.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.amber)
                }
                .accessibilityHidden(true)

                Text("Your saved resumes are full")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                DashboardButton(title: "Manage saved resumes", icon: "tray.full", prominent: true) {
                    session.manageSavedResumes()
                }
                .padding(.top, 4)

                Button("Not now") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(minHeight: 44)
            }
            .padding(24)
        }
    }
}
