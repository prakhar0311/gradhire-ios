import SwiftUI

struct EmptySavedState: View {

    var body: some View {
        VStack(spacing: 20) {

            Image(systemName: "bookmark.slash")
                .font(.system(size: 52))
                .foregroundColor(.blue.opacity(0.6))

            Text("No Saved Jobs Yet")
                .font(.title2.bold())

            Text("Bookmark jobs to review or apply later.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(40)
    }
}

