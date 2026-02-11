import SwiftUI
import UniformTypeIdentifiers

struct UploadResumeView: View {

    @EnvironmentObject var resumeManager: ResumeManager

    @State private var showPicker = false
    @State private var selectedFileName: String? = nil
    @State private var goToJobs = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var jobs: [Job] = []
    @StateObject private var network = NetworkMonitor.shared
    @State private var showRetry = false

    @State private var selectedCountry = "in"
    @State private var animate = false

    let countries = [
        ("🇮🇳 India", "in"),
        ("🇺🇸 USA (Visa Friendly)", "us")
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

                        VStack(spacing: 22) {

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

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select Country")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                Picker("Country", selection: $selectedCountry) {
                                    ForEach(countries, id: \.1) {
                                        Text($0.0).tag($0.1)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(22)

                            Button {
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

                            Group {
                                if isUploading {
                                    ProgressView("Analyzing resume...")
                                } else if let fileName = selectedFileName {
                                    Label(fileName, systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                } else {
                                    Text("PDF only • Max 1 file")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                if let errorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }

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

            // MARK: FILE IMPORTER

            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in

                switch result {

                case .success(let urls):
                    guard let url = urls.first else { return }

                    guard network.isConnected else {
                        errorMessage = "No internet connection"
                        return
                    }

                    guard url.startAccessingSecurityScopedResource() else {
                        errorMessage = "Permission denied"
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

                        // STEP 1: Upload resume → get text
                        APIService.shared.uploadResume(fileURL: localURL) { uploadResult in

                            DispatchQueue.main.async {

                                switch uploadResult {

                                case .failure(let error):
                                    isUploading = false
                                    errorMessage = error.localizedDescription

                                case .success(let resumeText):

                                    // STEP 2: Save globally
                                    resumeManager.resumeURL = localURL
                                    resumeManager.resumeText = resumeText

                                    // STEP 3: Fetch jobs
                                    JobAPIService.shared.fetchJobsFromResume(
                                        fileURL: localURL,
                                        country: selectedCountry
                                    ) { result in

                                        DispatchQueue.main.async {

                                            isUploading = false

                                            switch result {
                                            case .success(let fetchedJobs):
                                                jobs = fetchedJobs
                                                goToJobs = true

                                            case .failure(let error):
                                                errorMessage = error.localizedDescription
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    } catch {
                        isUploading = false
                        errorMessage = "Failed to read file"
                    }

                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showRetry = true
                }
            }
        }
    }
}

#Preview {
    UploadResumeView()
}

