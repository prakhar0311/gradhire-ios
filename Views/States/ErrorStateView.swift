
import SwiftUI

struct ErrorStateView: View {

    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 22) {

            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56))
                .foregroundColor(.red.opacity(0.7))

            Text("Something went wrong")
                .font(.title2.bold())

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: retryAction) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}
