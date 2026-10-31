import SwiftUI

// MARK: - Apply Link Button

/// Opens a job's apply link: in the in-app browser sheet (job and tracker
/// detail) or in the user's default browser (the optimized resume screen).
/// "Did you apply?" shows when the sheet closes, or when the app comes back
/// from Safari. A missing or broken link shows a short message instead.
struct ApplyLinkButton<Label: View>: View {

    enum Destination {
        case inAppSheet
        case browser
    }

    let job: Job
    var opensIn: Destination = .inAppSheet
    @ViewBuilder let label: () -> Label

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var session: AppSession
    @State private var sheetURL: URL?
    /// A quick second tap while Safari is opening is ignored
    @State private var isOpening = false

    static var unavailableMessage: String { "This job's apply link isn't available." }

    var body: some View {
        Button(action: open, label: label)
            .accessibilityHint(opensIn == .browser ? "Opens the job posting in your browser" : "Opens the job posting")
            .sheet(item: $sheetURL, onDismiss: {
                tracker.checkApplyPrompt(fromForeground: false)
            }) { url in
                SafariView(url: url)
            }
    }

    private func open() {
        guard let url = Self.applyURL(job.applyURL) else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            session.notice = Self.unavailableMessage
            return
        }

        switch opensIn {
        case .inAppSheet:
            tracker.applyOpened(job, externally: false)
            sheetURL = url
        case .browser:
            guard !isOpening else { return }
            isOpening = true
            tracker.applyOpened(job, externally: true)
            openURL(url) { accepted in
                isOpening = false
                guard !accepted else { return }
                tracker.applyOpenFailed()
                session.notice = Self.unavailableMessage
            }
        }
    }

    /// Only complete web links: http(s) with a host.
    static func applyURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
