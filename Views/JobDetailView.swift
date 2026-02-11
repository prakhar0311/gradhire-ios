import SwiftUI

struct JobDetailView: View {
    let job: Job
  
    @State private var showFullDescription = false
    

    // MARK: - Smart Description Parsing (UI-only)
    var descriptionPoints: [String] {
        // Normalize line breaks
        let rawLines = job.description
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // ✅ If backend already sends bullet-like lines, use them
        if rawLines.count >= 3 {
            return rawLines
        }

        // ✅ Fallback: chunk long paragraph into readable bullets
        let words = job.description.split(separator: " ")
        var chunks: [String] = []
        var current: [Substring] = []

        for word in words {
            current.append(word)

            if current.joined(separator: " ").count >= 90 {
                chunks.append(current.joined(separator: " "))
                current.removeAll()
            }
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: " "))
        }

        return chunks
    }

    var visiblePoints: [String] {
        showFullDescription
            ? descriptionPoints
            : Array(descriptionPoints.prefix(3))
    }

    var body: some View {
        ZStack {

            // MARK: - Premium Background Glow
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

                    // MARK: - Header Card
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

                    // MARK: - Key Skills (unchanged)
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

                    // MARK: - What You'll Be Doing (Improved)
                    VStack(alignment: .leading, spacing: 16) {

                        Label("What You’ll Be Doing", systemImage: "doc.text.fill")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(visiblePoints.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)

                                    Text(visiblePoints[index])
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // MARK: - Read More / Show Less
                        if descriptionPoints.count > 3 {
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

                    // MARK: - CTA Button
                    NavigationLink(destination: OptimizeResumeView(job: job)
                    ) {
                        HStack {
                            Spacer()
                            Label("Optimize Resume for this Job", systemImage: "sparkles")
                                .font(.headline)
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
                        .shadow(color: .blue.opacity(0.4), radius: 14, y: 8)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Skills Extractor (unchanged)
    var skills: [String] {
        let keywords = [
            "Swift","React","Python","Java",
            "AWS","Docker","APIs","iOS",
            "Frontend","Backend","Cloud"
        ]

        return keywords.filter {
            job.description.localizedCaseInsensitiveContains($0)
        }
    }
}

#Preview {
    NavigationStack {
        JobDetailView(
            job: Job(
                id: UUID(),
                title: "iOS Developer",
                company: "IntraEdge",
                location: "Hyderabad, Telangana",
                description: """
                We are seeking an experienced iOS Developer to build high-quality mobile applications.
                You will collaborate with designers and backend engineers to deliver scalable solutions.
                Strong experience with Swift, iOS frameworks, and performance optimization is required.
                Familiarity with REST APIs, CI/CD pipelines, and Agile development practices is a plus.
                """,
                matchScore: 94,
                applyURL: ""
            )
        )
    }
}

