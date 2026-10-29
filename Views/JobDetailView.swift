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
        case (85...100)?: return AppTheme.teal
        case (65..<85)?:  return AppTheme.amber
        default:          return AppTheme.coral
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

            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    headerCard
                    if hasMatchSkills {
                        matchSkillsCard
                    } else if !skills.isEmpty {
                        skillsCard
                    }
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
            AppTheme.base,
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
                router.show(.resume)
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
                            .fill(AppTheme.purple.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(
                                        AppTheme.purple.opacity(0.3),
                                        lineWidth: 0.5
                                    )
                            )
                            .frame(width: 56, height: 56)

                        Image(systemName: "building.2.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.violet)
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
                sectionLabel(title: "Key Skills", icon: "star.fill", iconColor: AppTheme.lavender)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(skills, id: \.self) { skill in
                        Text(skill)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.lavender)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.purple.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(
                                        AppTheme.purple.opacity(0.28),
                                        lineWidth: 0.5
                                    )
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    /// Resume-matched jobs carry the skills the job asks for that the resume
    /// has / lacks (from matching); other jobs fall back to keyword chips.
    private var hasMatchSkills: Bool {
        !(job.matchedSkills ?? []).isEmpty || !(job.missingSkills ?? []).isEmpty
    }

    var matchSkillsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel(title: "Skills", icon: "star.fill", iconColor: AppTheme.lavender)

                if let matched = job.matchedSkills, !matched.isEmpty {
                    skillGroup(title: "On your resume", skills: matched, color: AppTheme.teal, icon: "checkmark")
                }
                if let missing = job.missingSkills, !missing.isEmpty {
                    skillGroup(title: "Missing from your resume", skills: missing, color: AppTheme.amber, icon: "plus")
                    Text("Add the ones you have, or use Optimize to work them in.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private func skillGroup(title: String, skills: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(skills, id: \.self) { skill in
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 8, weight: .bold))
                        Text(skill)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(color.opacity(0.12))
                    .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
                    .clipShape(Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(skills.joined(separator: ", "))")
    }

    var descriptionCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(
                    title: "Job Description",
                    icon: "doc.text.fill",
                    iconColor: AppTheme.purple
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
                                .foregroundColor(AppTheme.violet)
                            Image(systemName: showFullDescription ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.violet)
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
                            AppTheme.purple,
                            AppTheme.teal
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(16)
                .shadow(
                    color: AppTheme.purple.opacity(0.4),
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

