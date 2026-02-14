import SwiftUI

struct JobDetailView: View {

    let job: Job

    @State private var showFullDescription = false
    @State private var showSafari = false

    // MARK: - Clean paragraph description

    var cleanedDescription: String {
        job.description
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shortDescription: String {
        if cleanedDescription.count <= 350 {
            return cleanedDescription
        }

        let index = cleanedDescription.index(
            cleanedDescription.startIndex,
            offsetBy: 350
        )

        return String(cleanedDescription[..<index]) + "..."
    }

    var displayDescription: String {
        showFullDescription ? cleanedDescription : shortDescription
    }

    // MARK: - Skills extraction (stable order)

    var skills: [String] {

        let techKeywords = [
            "AWS","Azure","Backend","Cloud","CSS","Django",
            "Docker","Frontend","Git","GraphQL","HTML",
            "Java","JavaScript","Kotlin","Kubernetes",
            "MongoDB","Node.js","Python","React",
            "REST","SQL","Swift","TypeScript","React.js","Next.js"
        ]

        let lowerDesc = job.description.lowercased()

        return techKeywords
            .filter { lowerDesc.contains($0.lowercased()) }
            .sorted()
            .prefix(8)
            .map { $0 }
    }

    var body: some View {

        ZStack {

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.18),
                    Color.purple.opacity(0.12),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 80)
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {

                VStack(spacing: 24) {

                    // MARK: HEADER

                    VStack(spacing: 18) {

                        HStack(spacing: 14) {

                            Image(systemName: "building.2.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                                .frame(width: 54, height: 54)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.blue.opacity(0.12))
                                )

                            VStack(alignment: .leading, spacing: 6) {

                                Text(job.title)
                                    .font(.title3.bold())

                                Text(job.company)
                                    .foregroundColor(.gray)

                                Text(job.location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            MatchScoreRing(score: job.matchScore)
                        }

                        Text("AI Match Score \(job.matchScore)%")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [.green.opacity(0.25), .mint.opacity(0.15)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.green)
                            .cornerRadius(20)
                    }
                    .padding(22)
                    .background(.ultraThinMaterial)
                    .cornerRadius(26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.white.opacity(0.35))
                    )

                    // MARK: SKILLS

                    if !skills.isEmpty {

                        VStack(alignment: .leading, spacing: 14) {

                            Label("Key Skills", systemImage: "star.fill")
                                .font(.headline)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 90))],
                                spacing: 12
                            ) {

                                ForEach(skills, id: \.self) { skill in
                                    Text(skill)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(22)
                        .background(.ultraThinMaterial)
                        .cornerRadius(26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.35))
                        )
                    }

                    // MARK: DESCRIPTION (Paragraph mode)

                    VStack(alignment: .leading, spacing: 16) {

                        Label("Job Description", systemImage: "doc.text.fill")
                            .font(.headline)

                        Text(displayDescription)
                            .foregroundColor(.secondary)
                            .animation(.easeInOut, value: showFullDescription)

                        if cleanedDescription.count > 350 {

                            Button {
                                withAnimation(.easeInOut) {
                                    showFullDescription.toggle()
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(showFullDescription ? "Show less" : "Read more")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .padding(22)
                    .background(.ultraThinMaterial)
                    .cornerRadius(26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.white.opacity(0.35))
                    )

                    // MARK: APPLY BUTTON (NEW)

                    if let url = URL(string: job.applyURL),
                       !job.applyURL.isEmpty {

                        Button {
                            showSafari = true
                        } label: {

                            Label("Apply / View Posting", systemImage: "arrow.up.right.square")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
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
                        }
                        .sheet(isPresented: $showSafari) {
                            SafariView(url: url)
                        }
                    }

                    // MARK: OPTIMIZE BUTTON

                    NavigationLink(destination: OptimizeResumeView(job: job)) {

                        Label("Optimize Resume for this Job", systemImage: "sparkles")
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

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}


