import SwiftUI

struct EmptyJobResultsView: View {

    var body: some View {
        VStack(spacing: 16) {

            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))

            Text("No matches found")
                .font(.headline)

            Text("Try another resume or adjust your country selection.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

#Preview {
    EmptyJobResultsView()
}

