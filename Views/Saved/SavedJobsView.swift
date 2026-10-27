import SwiftUI

struct SavedJobsView: View {

    @EnvironmentObject var bookmarks: BookmarkManager

    var savedJobs: [Job] {
        bookmarks.savedJobs
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

            if savedJobs.isEmpty {
                DarkEmptySavedState()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {

                        // Header
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Saved Jobs")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.white)

                            Text("\(savedJobs.count) bookmarked opportunit\(savedJobs.count == 1 ? "y" : "ies")")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.38))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        ForEach(savedJobs) { job in
                            NavigationLink(destination: JobDetailView(job: job)) {
                                DarkSavedJobCard(job: job)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 40)
                    }
                }
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
                Text("SAVED JOBS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}

// MARK: - Saved Job Card

struct DarkSavedJobCard: View {

    let job: Job

    private var iconColor: Color {
        switch job.matchScore {
        case (85...100)?: return Color(red: 0.39, green: 0.22, blue: 1.0)
        case (65..<85)?:  return Color(red: 0.0, green: 0.83, blue: 0.67)
        case nil:         return Color(red: 0.39, green: 0.22, blue: 1.0)
        default:          return Color(red: 0.98, green: 0.75, blue: 0.18)
        }
    }

    private var scoreColor: Color {
        switch job.matchScore {
        case (85...100)?: return Color(red: 0.0, green: 0.83, blue: 0.67)
        case (65..<85)?:  return Color(red: 0.98, green: 0.75, blue: 0.18)
        default:          return Color(red: 1.0, green: 0.48, blue: 0.45)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {

            // Company icon
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(iconColor.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: "building.2.fill")
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(job.company)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))

                Text(job.location)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.bottom, 6)

                // Score pill (only resume-matched jobs have a score)
                if let matchScore = job.matchScore {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(scoreColor)
                            .frame(width: 5, height: 5)
                        Text("\(matchScore)% match")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(scoreColor)
                    }
                } else if let postedAgo = job.postedAgoText {
                    Text(postedAgo)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

            // Right side
            VStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.0, green: 0.83, blue: 0.67))

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .cornerRadius(20)
    }
}

// MARK: - Empty State

struct DarkEmptySavedState: View {

    var body: some View {
        VStack(spacing: 18) {

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "bookmark.slash.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color(red: 0.55, green: 0.43, blue: 1.0).opacity(0.7))
            }

            VStack(spacing: 6) {
                Text("No Saved Jobs")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Text("Bookmark jobs from the list\nto find them here later.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(40)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .cornerRadius(24)
        .padding(.horizontal, 40)
    }
}

