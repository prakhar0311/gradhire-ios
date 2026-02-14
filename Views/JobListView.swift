import SwiftUI
import UIKit

// MARK: - JOB LIST VIEW

struct JobListView: View {

    let jobs: [Job]
    @StateObject private var bookmarks = BookmarkManager()

    // UI State
    @State private var isLoading = true
    @State private var didTriggerHaptic = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {

            // MARK: Background Glow
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.18),
                    Color.purple.opacity(0.14),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 80)
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Best Matches")
                            .font(.system(size: 34, weight: .bold))

                        Text("AI matched roles for your resume")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    // MARK: Loading → Error → Empty → Jobs

                    if isLoading {

                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonJobCard()
                                .padding(.horizontal)
                        }

                    } else if let errorMessage {

                        ErrorStateView(
                            message: errorMessage,
                            retryAction: {
                                self.errorMessage = nil
                                UIImpactFeedbackGenerator(style: .light)
                                    .impactOccurred()
                            }
                        )
                        .padding(.horizontal)

                    } else if jobs.isEmpty {

                        EmptyJobResultsView()
                            .padding(.horizontal)

                    } else {

                        ForEach(jobs) { job in
                            NavigationLink(
                                destination: JobDetailView(job: job)
                            ) {
                                PremiumJobCard(
                                    job: job,
                                    isSaved: bookmarks.isSaved(job),
                                    onBookmarkTap: {
                                        bookmarks.toggle(job)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationBarTitleDisplayMode(.inline)

        // MARK: Toolbar
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(
                    destination: SavedJobsView(allJobs: jobs)
                        .environmentObject(bookmarks)
                ) {
                    Image(systemName: "bookmark.fill")
                }
            }
        }

        // MARK: Simulated Loading
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isLoading = false

                if !didTriggerHaptic {
                    UIImpactFeedbackGenerator(style: .soft)
                        .impactOccurred()
                    didTriggerHaptic = true
                }
            }
        }
    }
}

/////////////////////////////////////////////////////////////
// MARK: - MATCH SCORE RING
/////////////////////////////////////////////////////////////

struct MatchScoreRing: View {

    let score: Int
    @State private var progress: CGFloat = 0

    private var gradient: [Color] {
        if score >= 80 { return [.green, .mint] }
        if score >= 60 { return [.blue, .cyan] }
        return [.orange, .red]
    }

    var body: some View {
        ZStack {

            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(score)%")
                .font(.caption2.bold())
        }
        .frame(width: 40, height: 40)
        .onAppear {
            withAnimation(.easeOut(duration: 1)) {
                progress = CGFloat(score) / 100
            }
        }
    }
}

/////////////////////////////////////////////////////////////
// MARK: - PREMIUM JOB CARD
/////////////////////////////////////////////////////////////

struct PremiumJobCard: View {

let job: Job
let isSaved: Bool
let onBookmarkTap: () -> Void

@State private var pulse = false

var body: some View {
    HStack(alignment: .top, spacing: 16) {

        // MARK: Company Icon
        Image(systemName: "building.2.fill")
            .font(.system(size: 26))
            .foregroundColor(.blue)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.12))
            )

        // MARK: Text Column
        VStack(alignment: .leading, spacing: 8) {

            // Title + Inline Badge
            HStack(alignment: .firstTextBaseline, spacing: 8) {

                Text(job.title)
                    .font(.headline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if job.matchScore >= 85 {
                    Text("TOP MATCH")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .scaleEffect(pulse ? 1.05 : 1)
                        .shadow(
                            color: .orange.opacity(0.4),
                            radius: pulse ? 6 : 2
                        )
                        .fixedSize()
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.8)
                                    .repeatForever(autoreverses: true)
                            ) {
                                pulse = true
                            }
                        }
                }
            }

            Text(job.company)
                .font(.subheadline)
                .foregroundColor(.gray)

            Text(job.location)
                .font(.caption)
                .foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // MARK: Right Controls
        VStack(spacing: 10) {

            Button(action: onBookmarkTap) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSaved ? .green : .gray)
            }

            MatchScoreRing(score: job.matchScore)

            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.4))
        }
    }
    .padding(18)
    .background(.ultraThinMaterial)
    .cornerRadius(24)
    .overlay(
        RoundedRectangle(cornerRadius: 24)
            .stroke(Color.white.opacity(0.4))
    )
    .shadow(color: .black.opacity(0.08), radius: 16, y: 10)
    .padding(.horizontal)
}

}



/////////////////////////////////////////////////////////////
// MARK: - PREVIEW
/////////////////////////////////////////////////////////////

#Preview {
    NavigationStack {
        JobListView(jobs: [
            Job(
                id: UUID(),
                title: "Junior Software Engineer",
                company: "Amazon",
                location: "Bangalore, India",
                description: "Build scalable backend services.",
                matchScore: 92,
                applyURL: "https://amazon.jobs"
            ),
            Job(
                id: UUID(),
                title: "iOS Developer Intern",
                company: "Apple",
                location: "Hyderabad, India",
                description: "Work on SwiftUI apps.",
                matchScore: 88,
                applyURL: "https://jobs.apple.com"
            )
        ])
    }
}


