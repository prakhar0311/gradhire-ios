import SwiftUI
import UniformTypeIdentifiers

struct UploadResumeView: View {

    @EnvironmentObject var resumeManager: ResumeManager
    @EnvironmentObject var matchedJobs: MatchedJobsViewModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showPicker = false
    @State private var selectedFileName: String?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @StateObject private var network = NetworkMonitor.shared
    @State private var showRetry = false
    @State private var animate = false
    @State private var showSlowServerHint = false
    @State private var showAIConsent = false
    @State private var offerAccountSave = false

    // Asked once, before the first resume is sent to GradHire's server and OpenAI
    @AppStorage("ai_data_consent_v1") private var hasAIConsent = false

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
        ZStack(alignment: .top) {

            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            // Scrolls so nothing ends up under the tab bar on smaller screens
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // HERO
                    ZStack(alignment: .bottom) {

                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.02, blue: 0.22),
                                Color(red: 0.18, green: 0.06, blue: 0.38),
                                Color(red: 0.04, green: 0.04, blue: 0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        ZStack {
                            RadialGradient(
                                colors: [
                                    Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.45),
                                    Color.clear
                                ],
                                center: .init(x: 0.3, y: 0.3),
                                startRadius: 0,
                                endRadius: 220
                            )
                            RadialGradient(
                                colors: [
                                    Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.18),
                                    Color.clear
                                ],
                                center: .init(x: 0.82, y: 0.65),
                                startRadius: 0,
                                endRadius: 160
                            )
                        }

                        Image("uploadresume")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .opacity(0.40)
                            .clipped()

                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(red: 0.04, green: 0.04, blue: 0.06)
                            ],
                            startPoint: .init(x: 0.5, y: 0.4),
                            endPoint: .bottom
                        )

                        VStack(spacing: 8) {
                            Text("GradHire")
                                .font(.system(size: 42, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .opacity(animate ? 1 : 0)
                                .offset(y: animate ? 0 : 16)

                            Text("AI-powered job matching for new grads")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.45))
                                .opacity(animate ? 1 : 0)

                            Text("SECURE  •  PRIVATE  •  SMART MATCHING")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.4)
                                .foregroundColor(.white.opacity(0.22))
                                .opacity(animate ? 1 : 0)
                        }
                        .padding(.bottom, 100) //28
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 480) //420
                    .clipped()

                    // CONTENT
                    VStack(spacing: 16) {

                        countryPicker
                        uploadButton
                        dataUseNote
                        statusSection
                        browseAllJobsButton
                        trustBadges

                        Spacer()
                    }
                    .frame(maxWidth: 380) // 👈 LIMIT WIDTH (KEY FIX)
                    .frame(maxWidth: .infinity) // 👈 center it
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.04, green: 0.04, blue: 0.06))
                }
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AccountButton()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { animate = true }
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
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Save this resume to your account?", isPresented: $offerAccountSave) {
            Button("Save") {
                saveToAccount()
                showMatches()
            }
            Button("Not now", role: .cancel) { showMatches() }
        } message: {
            Text("It's stored privately in your GradHire account, so your readiness score, skill insights and tailored versions are kept. If you choose Not now, it stays on this device only.")
        }
    }

    // MARK: - After Upload

    /// Matching loads on the jobs screen (skeletons, error, empty states).
    private func showMatches() {
        router.jobsTab = .forYou
        router.tab = .jobs
    }

    private func saveToAccount() {
        guard let url = resumeManager.resumeURL, let userId = auth.user?.id else { return }
        let text = resumeManager.resumeText
        let title = resumeManager.fileName
        Task {
            if let id = await auth.saveGuestResume(fileURL: url, text: text, title: title) {
                resumeManager.linkToAccount(resumeId: id, userId: userId)
                // Match again with the account copy, so the matches are stored
                await matchedJobs.refresh()
            }
        }
    }

    // MARK: - Country Picker

    private var countryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text("SELECT COUNTRY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.3))

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
        .padding(16)
        .padding(.horizontal, 4) // FIX overflow
        .frame(maxWidth: .infinity)
        .layoutPriority(1) // 👈 prevents weird stretching
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .cornerRadius(18)
    }

    // MARK: - Upload Button

    private var uploadButton: some View {
        Button {
            errorMessage = nil
            showRetry = false
            if hasAIConsent {
                showPicker = true
            } else {
                showAIConsent = true
            }
        } label: {
            HStack(spacing: 10) {
                Spacer()

                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 17, weight: .semibold))

                Text("Upload Resume (PDF)")
                    .font(.system(size: 16, weight: .black, design: .rounded))

                Spacer()
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.39, green: 0.22, blue: 1.0),
                                Color(red: 0.0, green: 0.83, blue: 0.67)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundColor(.white)
            .shadow(
                color: Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.4),
                radius: 16, x: 0, y: 6
            )
        }
        .padding(.horizontal, 4)
        .disabled(isUploading) // ✅ keeps it unclickable during upload
    }

    // MARK: - Browse All Jobs

    private var browseAllJobsButton: some View {
        Button {
            router.jobsTab = .allJobs
            router.tab = .jobs
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Browse all new grad jobs")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .foregroundColor(.white.opacity(0.6))
            .cornerRadius(16)
        }
        .padding(.horizontal, 4)
        .disabled(isUploading)
    }

    // MARK: - Data Use Note

    private var dataUseNote: some View {
        Text("Your resume is sent to our server and OpenAI to match jobs and suggest improvements.")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.3))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Group {
            if isUploading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color(red: 0.55, green: 0.43, blue: 1.0))
                    Text(
                        showSlowServerHint
                        ? "Waking up the server — this can take up to a minute the first time."
                        : "Analyzing resume..."
                    )
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.leading)
                }
                // A free-tier backend can take ~a minute to wake from idle
                .task {
                    showSlowServerHint = false
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if !Task.isCancelled { showSlowServerHint = true }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .cornerRadius(14)

            } else if let errorMessage {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.45))
                            .multilineTextAlignment(.leading)
                    }
                    if showRetry {
                        Button {
                            showRetry = false
                            showPicker = true
                        } label: {
                            Text("Try Again")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(
                                    Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.4),
                                            lineWidth: 0.5
                                        )
                                )
                                .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1.0, green: 0.48, blue: 0.45).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            Color(red: 1.0, green: 0.48, blue: 0.45).opacity(0.2),
                            lineWidth: 0.5
                        )
                )
                .cornerRadius(14)

            } else if let fileName = selectedFileName {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.0, green: 0.83, blue: 0.67))
                    Text(fileName)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.2),
                            lineWidth: 0.5
                        )
                )
                .cornerRadius(14)
            }
        }
    }

    private var trustBadges: some View {
        HStack(spacing: 0) {
            ForEach(
                [
                    ("lock.shield.fill", "Secure Upload"),
                    ("iphone",           "Kept on this device"),
                    ("doc.fill",         "PDF only")
                ],
                id: \.0
            ) { icon, label in
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.22))
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.22))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {

        switch result {

        case .failure:
            errorMessage = "Couldn't open that file. Please try again."
            showRetry = true

        case .success(let urls):

            guard let url = urls.first else { return }

            guard network.isConnected else {
                errorMessage = "No internet connection"
                showRetry = true
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Permission denied"
                showRetry = true
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            isUploading = true
            errorMessage = nil

            do {
                let data = try Data(contentsOf: url)

                let localURL = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".pdf")

                try data.write(to: localURL)

                selectedFileName = url.lastPathComponent

                // 🔥 IMPORTANT: UI updates must be on main thread
                DispatchQueue.main.async {
                    isUploading = true
                }

                APIService.shared.uploadResume(fileURL: localURL) { uploadResult in

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

                            // Keep it on this device (only); fall back to the temp copy
                            let fileName = url.lastPathComponent
                            if let storedURL = try? resumeManager.store(pdfData: data, text: resumeText, fileName: fileName) {
                                try? FileManager.default.removeItem(at: localURL)
                                matchedJobs.load(resumeURL: storedURL, country: router.country)
                            } else {
                                resumeManager.resumeURL = localURL
                                resumeManager.resumeText = resumeText
                                matchedJobs.load(resumeURL: localURL, country: router.country)
                            }

                            if auth.user != nil {
                                // Signed in: saving to the account is still a choice
                                offerAccountSave = true
                            } else {
                                showMatches()
                            }
                        }
                    }
                }

            } catch {
                isUploading = false
                errorMessage = "Failed to read file"
                showRetry = true
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
                            Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.5),
                            Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.3)
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
            Color(red: 0.06, green: 0.06, blue: 0.09)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.39, green: 0.22, blue: 1.0),
                                        Color(red: 0.0, green: 0.83, blue: 0.67)
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
                        text: "Your resume stays on this device. It's only saved to your account if you choose."
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
                                    Color(red: 0.39, green: 0.22, blue: 1.0),
                                    Color(red: 0.0, green: 0.83, blue: 0.67)
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
                .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
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

