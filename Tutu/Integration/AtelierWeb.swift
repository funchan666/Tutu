import SwiftUI
import WebKit
import AVFoundation

@MainActor final class AtelierWeb: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    let view: WKWebView
    private let trustedOrigin: String
    private var url: URL
    private var current: WKNavigation?
    private var retiredNavigations = Set<ObjectIdentifier>()
    private var pageID = UUID()
    private var timeout: DispatchWorkItem?
    private var validResponse = false
    private var finished = false
    private var mounted = false
    private var stopped = false
    private var permissionTask: Task<Void, Never>?
    private var permissions: [(WKMediaCaptureType, (WKPermissionDecision) -> Void)] = []
    var onReady: (() -> Void)?
    var onFailure: (() -> Void)?
    init(url: URL) {
        self.url = url; trustedOrigin = Self.origin(url)
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false; view.backgroundColor = .white
    }
    static func origin(_ url: URL) -> String { "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme == "https" ? 443 : 80))" }
    func attach() { mounted = true; deliver() }
    func load(_ url: URL? = nil) {
        guard !stopped else { return }
        if let url { self.url = url }
        if let current { retiredNavigations.insert(ObjectIdentifier(current)) }
        self.current = nil; view.stopLoading()
        beginNavigation(); current = view.load(URLRequest(url: self.url))
        if current == nil { fail() }
    }
    private func beginNavigation() {
        pageID = UUID(); validResponse = false; finished = false; loading = true; error = nil
        timeout?.cancel()
        let id = pageID
        let timer = DispatchWorkItem { [weak self] in guard let self, self.pageID == id else { return }; self.fail() }
        timeout = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timer)
    }
    func stop() {
        stopped = true; pageID = UUID(); timeout?.cancel(); permissionTask?.cancel(); permissionTask = nil
        let pending = permissions; permissions = []; pending.forEach { $0.1(.deny) }
        onReady = nil; onFailure = nil; view.navigationDelegate = nil; view.uiDelegate = nil; view.stopLoading()
        view.pauseAllMediaPlayback(completionHandler: nil)
    }
    private func deliver() { if !stopped && mounted && finished && validResponse { onReady?() } }
    private func fail() { guard !stopped else { return }; timeout?.cancel(); pageID = UUID(); loading = false; finished = false; validResponse = false
        if let current { retiredNavigations.insert(ObjectIdentifier(current)) }
        current = nil; view.stopLoading(); error = "This page could not be opened. Please try again."; onFailure?() }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !stopped, let navigation, !retiredNavigations.contains(ObjectIdentifier(navigation)) else { return }
        if current !== navigation {
            if let current { retiredNavigations.insert(ObjectIdentifier(current)) }
            beginNavigation(); current = navigation
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard !stopped else { decisionHandler(.cancel); return }
        if navigationResponse.isForMainFrame {
            let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
            validResponse = (200..<400).contains(status) && navigationResponse.canShowMIMEType
            if !validResponse { decisionHandler(.cancel); fail(); return }
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !stopped, current === navigation, validResponse else { return }
        timeout?.cancel(); loading = false; finished = true; deliver()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if current === navigation { fail() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if current === navigation { fail() } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !stopped, let url = navigationAction.request.url, ConfiguredCoreEvent.webURL(url.absoluteString) != nil else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame == nil { load(url); decisionHandler(.cancel) } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let port = origin.port == 0 ? (origin.protocol == "https" ? 443 : 80) : origin.port
        let requested = "\(origin.protocol.lowercased())://\(origin.host.lowercased()):\(port)"
        guard !stopped, frame.isMainFrame, requested == trustedOrigin else { decisionHandler(.deny); return }
        permissions.append((type, decisionHandler)); processPermissions()
    }
    private func processPermissions() {
        guard permissionTask == nil, !permissions.isEmpty else { return }
        permissionTask = Task { @MainActor in
            while !permissions.isEmpty && !Task.isCancelled {
                let type = permissions[0].0
                var allowed = true
                if type == .camera || type == .cameraAndMicrophone { allowed = await authorize(.video) }
                if type == .microphone || type == .cameraAndMicrophone { let mic = await authorize(.audio); allowed = allowed && mic }
                guard !Task.isCancelled, !stopped, !permissions.isEmpty else { return }
                permissions.removeFirst().1(allowed ? .grant : .deny)
            }
            permissionTask = nil
        }
    }
    private func authorize(_ kind: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: kind) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: kind)
        default: return false
        }
    }
}
struct AtelierWebHost: UIViewRepresentable {
    let owner: AtelierWeb
    func makeUIView(context: Context) -> UIView {
        let holder = AtelierWebHolder(owner: owner)
        let web = owner.view; web.translatesAutoresizingMaskIntoConstraints = false; holder.addSubview(web)
        NSLayoutConstraint.activate([web.topAnchor.constraint(equalTo: holder.topAnchor), web.bottomAnchor.constraint(equalTo: holder.bottomAnchor), web.leadingAnchor.constraint(equalTo: holder.leadingAnchor), web.trailingAnchor.constraint(equalTo: holder.trailingAnchor)])
        return holder
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
final class AtelierWebHolder: UIView {
    weak var owner: AtelierWeb?
    init(owner: AtelierWeb) { self.owner = owner; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { owner?.attach() } }
}
struct AtelierWebFeedback: View {
    @ObservedObject var owner: AtelierWeb
    var body: some View {
        VStack {
            if let error = owner.error {
                VStack(spacing: 16) { Text(error).font(.tutuSubheadline); PinkButton(title: "Try again") { owner.load() } }
                    .padding(24).background(Palette.blush, in: RoundedRectangle(cornerRadius: 24)).padding(24)
            } else if owner.loading { Text("Loading…").font(.tutuCaption).padding(12).background(.white.opacity(0.95)) }
            Spacer()
        }.allowsHitTesting(owner.error != nil)
    }
}
