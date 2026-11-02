import Foundation
import Combine
import SwiftUI

// MARK: - Backend Status

/// Whether GradHire's backend seems to be waking up. It runs on Render's
/// free tier, which sleeps after 15 idle minutes and can take about a minute
/// to wake. Loading screens show "Getting things ready…" while this is true
/// instead of a bare spinner.
final class BackendStatus: ObservableObject {

    static let shared = BackendStatus()
    // Internal so tests can use their own
    init() {}

    /// A request has been waiting a few seconds and the server hasn't
    /// answered recently, so it's most likely waking from sleep.
    @Published private(set) var isWaking = false

    // Render sleeps after 15 idle minutes; a little less to be safe
    private static let maySleepAfter: TimeInterval = 14 * 60
    // A warm server answers well before this
    private static let slowAfter: Duration = .seconds(3)

    private var lastResponse: Date?
    private var pending = 0

    private var mayBeAsleep: Bool {
        guard let lastResponse else { return true }
        return Date().timeIntervalSince(lastResponse) > Self.maySleepAfter
    }

    func requestStarted() {
        pending += 1
        guard mayBeAsleep, !isWaking else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.slowAfter)
            guard let self, self.pending > 0, self.mayBeAsleep else { return }
            self.isWaking = true
        }
    }

    /// `response` is nil when the request failed without reaching the server.
    func requestFinished(_ response: URLResponse?) {
        pending = max(0, pending - 1)
        if response is HTTPURLResponse { lastResponse = Date() }
        if pending == 0 || !mayBeAsleep { isWaking = false }
    }
}

// MARK: - Backend Requests

nonisolated extension URLSession {

    /// A request to GradHire's backend, reported to BackendStatus.
    func backendData(for request: URLRequest) async throws -> (Data, URLResponse) {
        await BackendStatus.shared.requestStarted()
        do {
            let result = try await data(for: request)
            await BackendStatus.shared.requestFinished(result.1)
            return result
        } catch {
            await BackendStatus.shared.requestFinished(nil)
            throw error
        }
    }
}

// MARK: - Waking Notice

/// Shown on loading screens while the backend wakes up.
struct WakingNotice: View {

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView()
                .tint(AppTheme.violet)
            VStack(alignment: .leading, spacing: 2) {
                Text("Getting things ready…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text("This can take up to a minute the first time.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
    }
}
