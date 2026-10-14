import SwiftUI
import MessageUI

struct MailDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String
}
struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    let completion: (MFMailComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient]); controller.setSubject(draft.subject); controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (MFMailComposeResult) -> Void
        init(_ completion: @escaping (MFMailComposeResult) -> Void) { self.completion = completion }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { completion(result) }
    }
}
