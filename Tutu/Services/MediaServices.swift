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
            HStack { Text(ui: page.title).font(.tutuHeadline); Spacer(); ArtButton(label: "Close", asset: "nav-close") { dismiss() } }.padding(16)
            if !error.isEmpty { VStack(spacing: 18) { Text(ui: error); PinkButton(title: "Try again") { error = ""; reload = UUID() }; Link("Open in browser", destination: page.url) }.padding(24) }
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
    var title = "Add your media"
    var subtitle = "Choose a favorite or capture something new."
    var avatarPerson: Person? = nil
    var completion: (MediaSelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var source: CaptureSource?
    @State private var pendingSelection: MediaSelection?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ui: title).font(.outfit(size: 22, weight: .bold))
                    if avatarPerson == nil { Text(ui: subtitle).font(.tutuSubheadline).foregroundStyle(Palette.secondary) }
                }
                Spacer(minLength: 0)
                ArtButton(label: "Close", asset: "nav-close", size: 28) { dismiss() }
            }
            if let avatarPerson {
                HStack(spacing: 16) {
                    Avatar(person: avatarPerson, size: 68).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(avatarPerson.name).font(.tutuHeadline).lineLimit(1)
                        Text("A little photo. All your style.").font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ScrollView {
                if avatarPerson != nil {
                    HStack(spacing: 12) {
                        avatarSource("Photo library", detail: "Choose your favorite", artwork: "icon-photo") {
                            source = CaptureSource(camera: false, video: false, cropImage: true)
                        }
                        avatarSource("Take a photo", detail: "Capture a new look", artwork: "icon-camera") {
                            open(camera: true, video: false)
                        }
                    }
                } else {
                  VStack(spacing: 12) {
                    sourceRow("Photo library", detail: allowVideo ? "Photos and videos you love" : "Find the perfect photo", artwork: "icon-photo") {
                        source = CaptureSource(camera: false, video: allowVideo)
                    }
                    sourceRow("Take a photo", detail: "Capture a fresh moment", artwork: "icon-camera") {
                        open(camera: true, video: false)
                    }
                    if allowVideo {
                        sourceRow("Record a video", detail: "A moment in motion", artwork: "icon-camera") {
                            open(camera: true, video: true)
                        }
                    }
                  }
                }
            }.scrollIndicators(.hidden)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(Palette.ink).background(Palette.blush)
            .presentationBackground(Palette.blush).presentationCornerRadius(30)
            .presentationDragIndicator(.hidden).presentationDetents([.height(avatarPerson != nil ? 360 : (allowVideo ? 440 : 340)), .large])
            .overlay { NoticeOverlay() }
            .sheet(item: $source, onDismiss: finishSelection) { selectedSource in
                NativeMediaPicker(source: selectedSource) { result in
                    pendingSelection = result
                    source = nil
                }
            }
    }
    private func avatarSource(_ title: String, detail: String, artwork: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Artwork(name: artwork).frame(width: 38, height: 38).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ui: title).font(.outfit(size: 15, weight: .semibold))
                    Text(ui: detail).font(.outfit(size: 12)).foregroundStyle(Palette.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 116, alignment: .leading).padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 20)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func sourceRow(_ title: String, detail: String, artwork: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Artwork(name: artwork).frame(width: 36, height: 36).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ui: title).font(.tutuHeadline)
                    Text(ui: detail).font(.tutuCaption).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
                Artwork(name: "nav-back").rotationEffect(.degrees(180)).frame(width: 13, height: 13)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
    private func finishSelection() {
        guard let selection = pendingSelection else { return }
        pendingSelection = nil
        completion(selection)
        dismiss()
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
            source = CaptureSource(camera: camera, video: video, cropImage: avatarPerson != nil && !video)
        }
    }
}
struct CaptureSource: Identifiable { let id = UUID(); let camera: Bool; let video: Bool; var cropImage = false }
struct NativeMediaPicker: UIViewControllerRepresentable {
    let source: CaptureSource
    let completion: (MediaSelection?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let view = UIImagePickerController(); view.delegate = context.coordinator
        view.sourceType = source.camera ? .camera : .photoLibrary
        view.allowsEditing = source.cropImage && !source.video
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
            else if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage { completion(.image(image)) }
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
