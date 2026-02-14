
import SwiftUI

struct OptimizeResumeView: View {

    let job: Job
    @EnvironmentObject var resumeManager: ResumeManager
    @StateObject private var network = NetworkMonitor.shared

    @State private var result: ResumeOptimizationResponse?
    @State private var isLoading = false
    @State private var isDownloading = false
    @State private var errorMessage: String?

    @State private var showResults = false
    @State private var showShareSheet = false
    @State private var downloadedFileURL: URL?

    var body: some View {
        ZStack {

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.18),
                    Color.purple.opacity(0.14),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 90)
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {

                    headerSection
                    targetRoleCard

                    if isLoading {
                        loadingSection
                    }

                    if let errorMessage {
                        errorSection(message: errorMessage)
                    }

                    if let result = result, showResults {
                        resultsSection(result: result)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .onAppear {
            if result == nil {
                optimize()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = downloadedFileURL {
                ShareSheet(items: [url])
            }
        }
    }
}

//////////////////////////////////////////////////////////
// MARK: API Logic
//////////////////////////////////////////////////////////

private extension OptimizeResumeView {

    func optimize() {

        guard network.isConnected else {
            errorMessage = "No internet connection"
            return
        }

        guard let resumeText = resumeManager.resumeText,
              !resumeText.isEmpty else {
            errorMessage = "Resume not found"
            return
        }

        isLoading = true
        errorMessage = nil
        showResults = false

        // Timeout protection
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if isLoading {
                isLoading = false
                errorMessage = "Optimization timed out — please retry"
            }
        }

        APIService.shared.optimizeResume(
            resumeText: resumeText,
            jobTitle: job.title,
            jobDescription: job.description
        ) { result in

            isLoading = false

            switch result {
            case .success(let data):

                if data.improvedBullets.isEmpty &&
                    data.missingSkills.isEmpty {
                    errorMessage = "AI returned empty results"
                    return
                }

                self.result = data
                self.showResults = true

            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func downloadResume() {

        guard network.isConnected else {
            errorMessage = "No internet connection"
            return
        }

        guard let resumeURL = resumeManager.resumeURL else {
            errorMessage = "No resume uploaded"
            return
        }

        isDownloading = true
        errorMessage = nil

        APIService.shared.downloadOptimizedResume(
            resumeURL: resumeURL,
            jobDescription: job.description
        ) { result in

            isDownloading = false

            switch result {

            case .success(let url):
                downloadedFileURL = url
                showShareSheet = true

            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

//////////////////////////////////////////////////////////
// MARK: UI Sections
//////////////////////////////////////////////////////////

private extension OptimizeResumeView {

    var headerSection: some View {
        VStack(spacing: 14) {

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            Text("AI Resume Optimization")
                .font(.title2.bold())

            Text("Tailored for \(job.company)")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.top)
    }

    var targetRoleCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            Label("Target Role", systemImage: "briefcase.fill")
                .font(.headline)
                .foregroundColor(.blue)

            Text(job.title)
                .font(.title3.bold())

            Text(job.company)
                .foregroundColor(.gray)

            Text(job.location)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }

    var loadingSection: some View {
        VStack(spacing: 18) {

            ProgressView()
                .scaleEffect(1.4)

            Text("Analyzing with AI...")
                .foregroundColor(.gray)

            Text("Matching skills • Optimizing bullets • ATS tuning")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }

    func errorSection(message: String) -> some View {
        VStack(spacing: 12) {

            Text(message)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)

            Button("Retry Optimization") {
                optimize()
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(16)
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }

    func resultsSection(result: ResumeOptimizationResponse) -> some View {
        VStack(spacing: 20) {

            ResumeReadinessCard(matchScore: job.matchScore)

            PremiumSection(
                title: "Missing Skills",
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                items: result.missingSkills
            )

            ImprovedBulletsSection(
                //bullets: result.improvedBullets
                bullets: Array(result.improvedBullets.prefix(5))
            )

            PremiumSection(
                title: "ATS Keywords",
                icon: "tag.fill",
                color: .purple,
                items: result.atsKeywords
            )

            downloadButton
            applyButton
        }
    }

    var downloadButton: some View {
        Button(action: downloadResume) {

            HStack {
                Spacer()

                if isDownloading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label(
                        "Download Optimized Resume",
                        systemImage: "arrow.down.doc.fill"
                    )
                    .font(.headline)
                }

                Spacer()
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.green, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(22)
            .shadow(radius: 8)
        }
        .disabled(isDownloading || isLoading)
    }

    var applyButton: some View {
        Group {
            if let url = URL(string: job.applyURL) {
                Link(destination: url) {
                    HStack {
                        Spacer()
                        Label(
                            "Apply Now",
                            systemImage: "arrow.up.right.square.fill"
                        )
                        Spacer()
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
            }
        }
    }
}

//////////////////////////////////////////////////////////
// MARK: Resume Readiness Card
//////////////////////////////////////////////////////////

struct ResumeReadinessCard: View {

    let matchScore: Int

    var message: String {
        switch matchScore {
        case 85...100:
            return "Strong match — you’re ready to apply"
        case 65..<85:
            return "Good match — minor improvements recommended"
        default:
            return "Low match — optimize before applying"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Label("Resume Readiness", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundColor(.green)

            ProgressView(value: Double(matchScore), total: 100)
                .tint(.green)

            Text("\(matchScore)% • \(message)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }
}

//////////////////////////////////////////////////////////
// MARK: Improved Bullets Section
//////////////////////////////////////////////////////////

struct ImprovedBulletsSection: View {

    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Label("Improved Resume Bullets", systemImage: "doc.text.fill")
                .font(.headline)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)

                        Text(bullet)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }
}

//////////////////////////////////////////////////////////
// MARK: Premium Section
//////////////////////////////////////////////////////////

struct PremiumSection: View {

    let title: String
    let icon: String
    let color: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(color)

            FlowLayout(items: items) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(color.opacity(0.15))
                    .cornerRadius(14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }
}

//////////////////////////////////////////////////////////
// MARK: Flow Layout
//////////////////////////////////////////////////////////

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Hashable {

    let items: Data
    let content: (Data.Element) -> Content

    init(
        items: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.content = content
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90), spacing: 10)],
            spacing: 10
        ) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}



