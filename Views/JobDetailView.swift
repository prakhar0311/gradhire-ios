import SwiftUI

struct JobDetailView: View {

    let job: Job

    @EnvironmentObject var resumeManager: ResumeManager
    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var router: AppRouter

    @State private var showFullDescription = false
    @State private var showSafari = false
    @State private var navigateToOptimize = false
    @State private var showUploadAlert = false

    var cleanedDescription: String {
        job.description
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shortDescription: String {
        if cleanedDescription.count <= 350 { return cleanedDescription }
        let index = cleanedDescription.index(cleanedDescription.startIndex, offsetBy: 350)
        return String(cleanedDescription[..<index]) + "..."
    }

    var displayDescription: String {
        showFullDescription ? cleanedDescription : shortDescription
    }

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

    private var scoreColor: Color {
        switch job.matchScore {
        case (85...100)?: return Color(red: 0.0, green: 0.83, blue: 0.67)
        case (65..<85)?:  return Color(red: 0.98, green: 0.75, blue: 0.18)
        default:          return Color(red: 1.0, green: 0.48, blue: 0.45)
        }
    }

    private var scoreLabel: String {
        switch job.matchScore {
        case (85...100)?: return "Strong match — ready to apply"
        case (65..<85)?:  return "Good match — minor gaps"
        default:          return "Low match — optimize first"
        }
    }

    var body: some View {
        ZStack {

            // Dark base
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            // Mesh gradient
            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.25),
                            Color.clear
                        ],
                        center: .init(x: 0.2, y: 0.1),
                        startRadius: 0,
                        endRadius: 300
                    )
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.83, blue: 0.67).opacity(0.15),
                            Color.clear
                        ],
                        center: .init(x: 0.85, y: 0.4),
                        startRadius: 0,
                        endRadius: 260
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.55)
                .ignoresSafeArea()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    headerCard
                    if !skills.isEmpty { skillsCard }
                    descriptionCard
                    actionButtons

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            Color(red: 0.04, green: 0.04, blue: 0.06),
            for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("JOB DETAIL")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                TrackJobButton(job: job)
            }
        }
        .navigationDestination(isPresented: $navigateToOptimize) {
            OptimizeResumeView(job: job)
        }
        .alert("Upload Your Resume", isPresented: $showUploadAlert) {
            Button("Upload Resume") {
                router.tab = .resume
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Upload a resume to optimize it for this job.")
        }
    }
}

// MARK: - Sections

private extension JobDetailView {

    var headerCard: some View {
        glassCard {
            VStack(spacing: 16) {

                HStack(alignment: .top, spacing: 14) {

                    ZStack {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(
                                        Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.3),
                                        lineWidth: 0.5
                                    )
                            )
                            .frame(width: 56, height: 56)

                        Image(systemName: "building.2.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 0.55, green: 0.43, blue: 1.0))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(job.company)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.45))

                        Text(job.location)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.25))
                    }

                    Spacer()

                    if let matchScore = job.matchScore {
                        DarkMatchRing(score: matchScore)
                    }
                }

                let status = tracker.status(for: job.id)
                if status != nil || job.postedAgoText != nil {
                    HStack(spacing: 6) {
                        if let status {
                            StatusBadge(status: status)
                        }
                        if let contract = job.contractLabel {
                            DarkTag(text: contract, teal: false)
                        }
                        if let postedAgo = job.postedAgoText {
                            DarkTag(text: postedAgo, teal: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Score pill (only resume-matched jobs have a score)
                if let matchScore = job.matchScore {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(scoreColor)

                        Text("AI Match \(matchScore)% — \(scoreLabel)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(scoreColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(scoreColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(scoreColor.opacity(0.25), lineWidth: 0.5)
                    )
                    .cornerRadius(12)
                }
            }
        }
    }

    var skillsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(title: "Key Skills", icon: "star.fill", iconColor: Color(red: 0.65, green: 0.55, blue: 0.98))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(skills, id: \.self) { skill in
                        Text(skill)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(
                                        Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.28),
                                        lineWidth: 0.5
                                    )
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    var descriptionCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(
                    title: "Job Description",
                    icon: "doc.text.fill",
                    iconColor: Color(red: 0.39, green: 0.22, blue: 1.0)
                )

                Text(displayDescription)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(4)

                if cleanedDescription.count > 350 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showFullDescription.toggle()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(showFullDescription ? "Show less" : "Read more")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 0.55, green: 0.43, blue: 1.0))
                            Image(systemName: showFullDescription ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(red: 0.55, green: 0.43, blue: 1.0))
                        }
                    }
                }
            }
        }
    }

    var actionButtons: some View {
        VStack(spacing: 10) {

            // Apply button
            if let url = URL(string: job.applyURL), !job.applyURL.isEmpty {
                Button {
                    tracker.applyOpened(job, externally: false)
                    showSafari = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 15))
                        Text("Apply / View Posting")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding(.vertical, 15)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .foregroundColor(.white.opacity(0.8))
                    .cornerRadius(16)
                }
                .sheet(isPresented: $showSafari, onDismiss: {
                    tracker.checkApplyPrompt(fromForeground: false)
                }) {
                    SafariView(url: url)
                }
            }

            // Optimize button
            Button {
                if resumeManager.resumeText == nil || resumeManager.resumeText!.isEmpty {
                    showUploadAlert = true
                } else {
                    navigateToOptimize = true
                }
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Optimize Resume for this Job")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                }
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
                .shadow(
                    color: Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.4),
                    radius: 16, x: 0, y: 6
                )
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
            )
            .cornerRadius(20)
    }

    func sectionLabel(title: String, icon: String, iconColor: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.3))
            .textCase(.uppercase)
    }
}

