import SwiftUI
import UniformTypeIdentifiers

struct UploadResumeView: View {

    @EnvironmentObject var resumeManager: ResumeManager
    @EnvironmentObject var matchedJobs: MatchedJobsViewModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var session: AppSession

    @State private var showPicker = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @StateObject private var network = NetworkMonitor.shared
    @State private var showRetry = false
    @State private var showSlowServerHint = false
    @State private var showAIConsent = false
    @State private var isSaving = false

    private static let maxFileSize = 5 * 1024 * 1024

    // Asked once, before the first resume is sent to GradHire's server and OpenAI
    @AppStorage("ai_data_consent_v1") private var hasAIConsent = false

    // Text scales with Dynamic Type
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 38
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 15
    @ScaledMetric(relativeTo: .headline) private var buttonSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var noteSize: CGFloat = 12

    struct CountryOption: Identifiable {
        let id = UUID()
        let label: String
        let code: String
        let enabled: Bool
    }

    let countries: [CountryOption] = [
        CountryOption(label: "🇮🇳 India", code: "in", enabled: true),
//        CountryOption(label: "🇺🇸 USA",   code: "us", enabled: false)
    ]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    hero

                    if resumeManager.hasResume {
                        currentResumeCard
                    }

                    VStack(spacing: 16) {
                        // Shown once there's more than one country to choose
                        if countries.filter(\.enabled).count > 1 {
                            countryPicker
                        }
                        uploadButton
                        dataUseNote
                        statusSection
                    }
                    .padding(18)
                    .background(glassBackground)

                    browseAllJobsButton
                    trustBadges
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AccountButton()
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .sheet(isPresented: $showAIConsent) {
            AIConsentSheet(
                onAgree: {
                    hasAIConsent = true
                    showAIConsent = false
                    // Let the sheet finish dismissing before presenting the picker
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showPicker = true
                    }
                },
                onCancel: { showAIConsent = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            AppLogo(size: 60)
            Text("GradHire")
                .font(.system(size: titleSize, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)
            Text(resumeManager.hasResume
                 ? "Upload a new resume any time to refresh your matches"
                 : "Upload your resume to find fresher jobs that match it")
                .font(.system(size: bodySize))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Current Resume

    private var currentResumeCard: some View {
        let status: String = session.isGuest
            ? "For this session only"
            : "Active · saved to your account"

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.teal.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.teal)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(resumeManager.fileName ?? "Your resume")
                    .font(.system(size: bodySize, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.system(size: noteSize))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 8)

            Button("See matches") { showMatches() }
                .font(.system(size: noteSize + 1, weight: .semibold))
                .foregroundColor(AppTheme.lavender)
        }
        .padding(16)
        .background(glassBackground)
        .accessibilityElement(children: .combine)
    }

    // MARK: - After Upload

    /// Matching loads on the jobs screen (skeletons, error, empty states).
    private func showMatches() {
        router.jobsTab = .forYou
        router.show(.jobs)
    }

    /// Signed in: every upload is saved to the account and becomes the
    /// active resume; For You then matches it.
    private func saveToAccount(pdfData data: Data, text: String, fileName: String) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await resumeManager.saveNewOriginal(pdfData: data, text: text, fileName: fileName)
                showMatches()
            } catch ResumeSaveError.originalLimit {
                session.resumeLimitPrompt = .originals
            } catch {
                errorMessage = "Your resume couldn't be saved to your account. \(JobAPIError.from(error).localizedDescription)"
                showRetry = true
            }
        }
    }

    // MARK: - Country Picker

    private var countryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text("SELECT COUNTRY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.45))

            HStack(spacing: 12) {
                ForEach(countries) { country in
                    CountryButton(
                        country: country,
                        isSelected: router.country == country.code,
                        onTap: {
                            if country.enabled { router.country = country.code }
                        }
                    )
                    .disabled(!country.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Upload Button

    private var uploadButton: some View {
        Button {
            errorMessage = nil
            showRetry = false
            // Signed in and full: say so before they pick a file
            if session.isSignedIn, resumeManager.isAtOriginalLimit {
                session.resumeLimitPrompt = .originals
            } else if hasAIConsent {
                showPicker = true
            } else {
                showAIConsent = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: buttonSize, weight: .semibold))
                Text(resumeManager.hasResume ? "Upload a New Resume (PDF)" : "Upload Resume (PDF)")
                    .font(.system(size: buttonSize, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(AppTheme.brandGradient))
            .foregroundColor(.white)
            .shadow(color: AppTheme.purple.opacity(0.4), radius: 16, x: 0, y: 6)
        }
        .disabled(isUploading || isSaving)
    }

    // MARK: - Browse All Jobs

    private var browseAllJobsButton: some View {
        Button {
            router.jobsTab = .allJobs
            router.show(.jobs)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: noteSize + 1, weight: .semibold))
                Text("Browse all new grad jobs")
                    .font(.system(size: bodySize - 1, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: noteSize - 1, weight: .semibold))
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(glassBackground)
            .foregroundColor(.white.opacity(0.75))
        }
        .disabled(isUploading || isSaving)
    }

    // MARK: - Data Use Note

    private var dataUseNote: some View {
        Text("Your resume is sent to our server and OpenAI to match jobs and suggest improvements.")
            .font(.system(size: noteSize - 1))
            .foregroundColor(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        if isUploading || isSaving {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppTheme.violet)
                Text(
                    isSaving
                    ? "Saving to your account…"
                    : showSlowServerHint
                    ? "Waking up the server. This can take up to a minute the first time."
                    : "Analyzing resume..."
                )
                .font(.system(size: noteSize + 1))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            }
            // A free-tier backend can take ~a minute to wake from idle
            .task {
                showSlowServerHint = false
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if !Task.isCancelled { showSlowServerHint = true }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06))
            .cornerRadius(14)

        } else if let errorMessage {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(AppTheme.coral)
                    Text(errorMessage)
                        .font(.system(size: noteSize + 1))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if showRetry {
                    Button {
                        showRetry = false
                        showPicker = true
                    } label: {
                        Text("Try Again")
                            .font(.system(size: noteSize + 1, weight: .semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(AppTheme.purple.opacity(0.2))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.purple.opacity(0.4), lineWidth: 0.5))
                            .foregroundColor(AppTheme.lavender)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.coral.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.coral.opacity(0.25), lineWidth: 0.5))
            .cornerRadius(14)
        }
    }

    private var trustBadges: some View {
        HStack(spacing: 0) {
            ForEach(
                [
                    ("lock.shield.fill", "Secure upload"),
                    ("iphone", session.isGuest ? "Not kept after you quit" : "Kept on this device"),
                    ("doc.fill", "PDF only")
                ],
                id: \.0
            ) { icon, label in
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: noteSize))
                    Text(label)
                        .font(.system(size: noteSize - 2))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Upload

    private func handleFileImport(_ result: Result<[URL], Error>) {

        switch result {

        case .failure:
            errorMessage = "Couldn't open that file. Please choose a PDF and try again."
            showRetry = true

        case .success(let urls):

            guard let url = urls.first else { return }

            guard network.isConnected else {
                errorMessage = JobAPIError.offline.localizedDescription
                showRetry = true
                return
            }

            // Read it now, into memory; a guest's resume is never written to disk
            let canAccess = url.startAccessingSecurityScopedResource()
            // Same limit as the server and storage; checked before reading it
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= Self.maxFileSize else {
                if canAccess { url.stopAccessingSecurityScopedResource() }
                errorMessage = "This PDF is larger than 5 MB. Upload a smaller file."
                showRetry = true
                return
            }
            let data = try? Data(contentsOf: url)
            if canAccess { url.stopAccessingSecurityScopedResource() }

            guard let data, !data.isEmpty else {
                errorMessage = "GradHire couldn't read that file. Save it to the Files app first, then try again."
                showRetry = true
                return
            }

            let fileName = url.lastPathComponent
            isUploading = true
            errorMessage = nil

            APIService.shared.uploadResume(pdfData: data) { uploadResult in

                DispatchQueue.main.async {
                    isUploading = false

                    switch uploadResult {

                    case .failure(let error):
                        // URL errors get a friendly message; backend validation
                        // errors ("not a resume", etc.) are shown as-is.
                        errorMessage = error is URLError
                            ? JobAPIError.from(error).localizedDescription
                            : error.localizedDescription
                        showRetry = true

                    case .success(let resumeText):
                        if session.isSignedIn {
                            saveToAccount(pdfData: data, text: resumeText, fileName: fileName)
                        } else {
                            resumeManager.replace(pdfData: data, text: resumeText, fileName: fileName)
                            matchedJobs.load(resumeData: data, country: router.country)
                            showMatches()
                        }
                    }
                }
            }
        }
    }

    private struct CountryButton: View {
        let country: CountryOption
        let isSelected: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                Text(country.label)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(backgroundView)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .foregroundColor(foregroundColor)
                    .cornerRadius(12)
            }
        }

        private var backgroundView: some View {
            Group {
                if isSelected {
                    LinearGradient(
                        colors: [
                            AppTheme.purple.opacity(0.5),
                            AppTheme.teal.opacity(0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Color.white.opacity(0.05)
                }
            }
        }

        private var foregroundColor: Color {
            if !country.enabled {
                return .white.opacity(0.2)
            }
            return isSelected ? .white : .white.opacity(0.45)
        }
    }
}

// MARK: - AI Consent Sheet

private struct AIConsentSheet: View {

    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            AppTheme.surface
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppTheme.purple,
                                        AppTheme.teal
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("Before you upload")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 10) {
                    consentPoint(
                        icon: "server.rack",
                        text: "Your resume is sent to GradHire's server to read it and find matching jobs."
                    )
                    consentPoint(
                        icon: "brain",
                        text: "When you optimize your resume for a job, its contents and the job description are sent to OpenAI to generate suggestions."
                    )
                    consentPoint(
                        icon: "trash",
                        text: "As a guest, your resume is forgotten when you close the app. When you're signed in it stays on this device, and it's only saved to your account if you choose."
                    )
                }

                Spacer(minLength: 0)

                Button(action: onAgree) {
                    Text("Agree & Continue")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(
                                colors: [
                                    AppTheme.purple,
                                    AppTheme.teal
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private func consentPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.lavender)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        UploadResumeView()
    }
    .environmentObject(ResumeManager())
    .environmentObject(MatchedJobsViewModel())
    .environmentObject(AppRouter())
}

