import SwiftUI
import UniformTypeIdentifiers

struct UploadResumeView: View {

@EnvironmentObject var resumeManager: ResumeManager

@State private var showPicker = false
@State private var selectedFileName: String?
@State private var goToJobs = false
@State private var isUploading = false
@State private var errorMessage: String?
@State private var jobs: [Job] = []
@StateObject private var network = NetworkMonitor.shared
@State private var showRetry = false

@State private var selectedCountry = "in"
@State private var animate = false

// ✅ UPDATED COUNTRY MODEL
struct CountryOption {
    let label: String
    let code: String
    let enabled: Bool
}

// ✅ India enabled, US coming soon
let countries = [
    CountryOption(label: "🇮🇳 India", code: "in", enabled: true),
    CountryOption(label: "🇺🇸 USA Coming Soon", code: "us", enabled: false)
]

var body: some View {
    NavigationStack {
        ZStack {

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.2),
                    Color.purple.opacity(0.15),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 90)
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    headerImage

                    VStack(spacing: 22) {

                        titleSection
                        countryPicker
                        uploadButton
                        statusSection

                        Spacer(minLength: 40)

                        NavigationLink(
                            destination: JobListView(jobs: jobs),
                            isActive: $goToJobs
                        ) { EmptyView() }
                    }
                    .padding(24)
                    .background(Color.white)
                    .cornerRadius(30)
                    .offset(y: -30)
                }
            }
            .scrollDisabled(true)
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                animate = true
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
    }
}

// MARK: UI Components

private var headerImage: some View {
    GeometryReader { geo in
        let offset = geo.frame(in: .global).minY

        ZStack(alignment: .bottom) {
            Image("uploadresume")
                .resizable()
                .scaledToFill()
                .frame(height: 420 + (offset > 0 ? offset : 0))
                .offset(y: (offset > 0 ? -offset : 0))
                .clipped()
                .ignoresSafeArea(.all, edges: .top)

            LinearGradient(
                colors: [.clear, .white],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
    .frame(height: 420)
    .ignoresSafeArea(edges: .top)
}

private var titleSection: some View {
    VStack(spacing: 8) {
        Text("GradHire")
            .font(.system(size: 40, weight: .bold))

        Text("AI-powered job matching for new grads")
            .foregroundColor(.gray)

        Text("Secure • Private • Smart Matching")
            .font(.caption)
            .foregroundColor(.gray.opacity(0.7))
    }
    .opacity(animate ? 1 : 0)
    .offset(y: animate ? 0 : 20)
}

private var countryPicker: some View {
    VStack(alignment: .leading, spacing: 6) {

        Text("Select Country")
            .font(.caption)
            .foregroundColor(.gray)

        Picker("Country", selection: $selectedCountry) {
            ForEach(countries, id: \.code) { country in
                Text(country.label)
                    .tag(country.code)
            }
        }
        .pickerStyle(.segmented)

        // ✅ Prevent selecting disabled country
        .onChange(of: selectedCountry) { newValue in
            if let selected = countries.first(where: { $0.code == newValue }),
               !selected.enabled {
                selectedCountry = "in"
            }
        }

        // ✅ Extra polish badge
        //Text("🇺🇸 USA support launching soon 🚀")
            //.font(.caption2)
          //  .foregroundColor(.gray.opacity(0.8))
    }
    .padding()
    .background(.ultraThinMaterial)
    .cornerRadius(22)
}

private var uploadButton: some View {
    Button {
        errorMessage = nil
        showRetry = false
        showPicker = true
    } label: {
        Label("Upload Resume (PDF)", systemImage: "arrow.up.doc.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
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
    .disabled(isUploading)
}

private var statusSection: some View {
    Group {
        if isUploading {
            ProgressView("Analyzing resume...")
        }
        else if let errorMessage {
            VStack(spacing: 8) {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)

                if showRetry {
                    Button {
                        showRetry = false
                        showPicker = true
                    } label: {
                        Text("Retry")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(12)
                    }
                }
            }
        }
        else if let fileName = selectedFileName {
            Label(fileName, systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
        else {
            Text("PDF only • Max 1 file")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: File Handling

private func handleFileImport(_ result: Result<[URL], Error>) {

    switch result {

    case .failure(let error):
        errorMessage = error.localizedDescription
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if isUploading {
                isUploading = false
                errorMessage = "Server timeout — please retry"
                showRetry = true
            }
        }

        do {
            let data = try Data(contentsOf: url)

            let localURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".pdf")

            try data.write(to: localURL)

            selectedFileName = url.lastPathComponent

            APIService.shared.uploadResume(fileURL: localURL) { uploadResult in

                switch uploadResult {

                case .failure(let error):
                    isUploading = false
                    errorMessage = error.localizedDescription
                    showRetry = true

                case .success(let resumeText):

                    resumeManager.resumeURL = localURL
                    resumeManager.resumeText = resumeText

                    JobAPIService.shared.fetchJobsFromResume(
                        fileURL: localURL,
                        country: selectedCountry
                    ) { result in

                        isUploading = false

                        switch result {

                        case .success(let fetchedJobs):

                            if fetchedJobs.isEmpty {
                                errorMessage = "No jobs found for this resume"
                                showRetry = true
                            } else {
                                jobs = fetchedJobs
                                goToJobs = true
                            }

                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            showRetry = true
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
}

#Preview {
    UploadResumeView()
}



