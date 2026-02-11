import SwiftUI

struct SavedJobsView: View {

    let allJobs: [Job]
  
    // 🔑 Shared source of truth
    @EnvironmentObject var bookmarks: BookmarkManager

    var savedJobs: [Job] {
        allJobs.filter { bookmarks.isSaved($0) }
    }

    var body: some View {
        ZStack {

            // MARK: Premium Background
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.15),
                    Color.purple.opacity(0.12),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 80)
            .ignoresSafeArea()

            if savedJobs.isEmpty {
                EmptySavedState()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {

                        header

                        ForEach(savedJobs) { job in
                            NavigationLink(destination: JobDetailView(job: job))
                            {
                                PremiumJobCardReadOnly(job: job)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        //.navigationTitle("Saved Jobs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved Jobs")
                .font(.system(size: 34, weight: .bold))

            Text("Your bookmarked opportunities")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}
 ///////////////////////////////////////////////////////////////////////////////////////

struct PremiumJobCardReadOnly: View {

    let job: Job

    var body: some View {
        HStack(spacing: 16) {

            Image(systemName: "building.2.fill")
                .font(.system(size: 26))
                .foregroundColor(.blue)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(job.title)
                    .font(.headline)

                Text(job.company)
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text(job.location)
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.7))
            }

            Spacer()

            Image(systemName: "bookmark.fill")
                .foregroundColor(.green)

            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.4))
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

