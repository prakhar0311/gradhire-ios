import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {


let url: URL

func makeUIViewController(context: Context) -> SFSafariViewController {

    let config = SFSafariViewController.Configuration()
    config.entersReaderIfAvailable = false
    config.barCollapsingEnabled = true

    let controller = SFSafariViewController(
        url: url,
        configuration: config
    )

    controller.preferredControlTintColor = .systemBlue
    controller.dismissButtonStyle = .close

    return controller
}

func updateUIViewController(
    _ uiViewController: SFSafariViewController,
    context: Context
) {}

}


