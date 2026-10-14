import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import WebKit

struct LegalPage: Identifiable {
    let id: String
    let title: String
    let url: URL
    static let terms = LegalPage(id: "terms", title: "User Agreement", url: LegalLinks.terms)
    static let privacy = LegalPage(id: "privacy", title: "Privacy Policy", url: LegalLinks.privacy)
}
struct LegalWebView: View {
    let page: LegalPage
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    @State private var reload = UUID()
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(page.title).font(.tutuHeadline); Spacer(); ArtButton(label: "Close", asset: "nav-close") { dismiss() } }.padding(16)
            if !error.isEmpty { VStack(spacing: 18) { Text(error); PinkButton(title: "Try again") { error = ""; reload = UUID() }; Link("Open in browser", destination: page.url) }.padding(24) }
            PolicyWebSurface(url: page.url, error: $error).id(reload)
        }.background(Palette.blush)
    }
}
struct PolicyWebSurface: UIViewRepresentable {
    let url: URL
    @Binding var error: String
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(); view.navigationDelegate = context.coordinator; view.load(URLRequest(url: url)); return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PolicyWebSurface
        init(parent: PolicyWebSurface) { self.parent = parent }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.error = "This page couldn't be loaded. Check your connection and try again." }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.error = "This page couldn't be loaded." }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame == nil { webView.load(URLRequest(url: url)); decisionHandler(.cancel) } else { decisionHandler(.allow) }
        }
    }
}
enum MediaSelection { case image(UIImage), movie(URL) }
struct MediaSourceView: View {
    var allowVideo = false
    var completion: (MediaSelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var source: CaptureSource?
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("Add your media").font(.tutuTitle3.bold()); Spacer(); ArtButton(label: "Close", asset: "nav-close") { dismiss() } }
            MenuRow(title: "Take a photo") { open(camera: true, video: false) }
            if allowVideo { MenuRow(title: "Record a video") { open(camera: true, video: true) } }
            MenuRow(title: "Choose from library") { source = CaptureSource(camera: false, video: allowVideo) }
            Text("Your selection stays on this device until a sharing service is available.").font(.tutuCaption).foregroundStyle(Palette.secondary)
        }.padding(24).background(Palette.blush).presentationDetents([.medium]).overlay { NoticeOverlay() }
            .sheet(item: $source) { s in NativeMediaPicker(source: s) { result in
                source = nil
                if let result { completion(result); dismiss() }
            } }
    }
    func open(camera: Bool, video: Bool) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { store.show("Camera unavailable", "Choose a photo from your library instead."); return }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { store.show("Camera access needed", "Enable Camera for Tutu in the Settings app, or choose from your library."); return }
            if video {
                let audio = await AVCaptureDevice.requestAccess(for: .audio)
                guard audio else { store.show("Microphone access needed", "Enable Microphone for Tutu in the Settings app."); return }
            }
            source = CaptureSource(camera: camera, video: video)
        }
    }
}
struct CaptureSource: Identifiable { let id = UUID(); let camera: Bool; let video: Bool }
struct NativeMediaPicker: UIViewControllerRepresentable {
    let source: CaptureSource
    let completion: (MediaSelection?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let view = UIImagePickerController(); view.delegate = context.coordinator
        view.sourceType = source.camera ? .camera : .photoLibrary
        view.mediaTypes = source.video ? (source.camera ? [UTType.movie.identifier] : [UTType.image.identifier, UTType.movie.identifier]) : [UTType.image.identifier]
        view.videoMaximumDuration = 60; view.videoQuality = .typeMedium
        if source.camera && source.video { view.cameraCaptureMode = .video }
        return view
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (MediaSelection?) -> Void
        init(_ completion: @escaping (MediaSelection?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { completion(.movie(url)) }
            else if let image = info[.originalImage] as? UIImage { completion(.image(image)) }
            else { completion(nil) }
        }
    }
}
@MainActor extension AppStore {
    func importMedia(_ media: MediaSelection) throws -> (reference: String, video: Bool) {
        switch media {
        case .image(let image):
            guard let data = image.jpegData(compressionQuality: 0.88), data.count < 20_000_000 else { throw TutuFailure.message("Choose a smaller photo, under 20 MB.") }
            return (try saveMedia(data, extension: "jpg"), false)
        case .movie(let url):
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? Int.max) <= 40_000_000 else { throw TutuFailure.message("Choose a video under 40 MB.") }
            return (try saveMedia(Data(contentsOf: url), extension: url.pathExtension.isEmpty ? "mov" : url.pathExtension), true)
        }
    }
}
