import SwiftUI
import WebKit
import AVFoundation

@MainActor private final class AtelierCaptureAuthorization {
    static let shared = AtelierCaptureAuthorization()
    private var pending: [AVMediaType: Task<Bool, Never>] = [:]

    func authorize(_ kind: AVMediaType) async -> Bool {
        if let task = pending[kind] { return await task.value }
        switch AVCaptureDevice.authorizationStatus(for: kind) {
        case .authorized: return true
        case .notDetermined:
            let task = Task { await AVCaptureDevice.requestAccess(for: kind) }
            pending[kind] = task
            let allowed = await task.value
            pending[kind] = nil
            return allowed
        default: return false
        }
    }
}

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
    private var committedOrigin: String?
    private var cleaningMedia = false
    private var mediaCompletions: [() -> Void] = []
    private var permissionTask: Task<Void, Never>?
    private struct Permission {
        let id = UUID()
        let page: UUID
        let origin: String
        let type: WKMediaCaptureType
        let complete: (WKPermissionDecision) -> Void
    }
    private var permissions: [Permission] = []
    var onReady: (() -> Void)?
    var onFailure: (() -> Void)?
    var isReady: Bool { !stopped && mounted && finished && validResponse && error == nil }
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
    static func origin(_ url: URL) -> String { "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80))" }
    private static func origin(_ origin: WKSecurityOrigin) -> String? {
        let scheme = origin.protocol.lowercased(), host = origin.host.lowercased()
        guard scheme == "https", !host.isEmpty, host != "null" else { return nil }
        return "\(scheme)://\(host):\(origin.port == 0 ? 443 : origin.port)"
    }
    func attach() { mounted = true; deliver() }
    func load(_ url: URL? = nil) {
        guard !stopped else { return }
        if let url { self.url = url }
        if let current { retiredNavigations.insert(ObjectIdentifier(current)) }
        self.current = nil; view.stopLoading()
        beginNavigation()
        let id = pageID, destination = self.url
        stopMedia { [weak self] in
            guard let self, !self.stopped, self.pageID == id, self.url == destination else { return }
            self.current = self.view.load(URLRequest(url: destination))
            if self.current == nil { self.fail() }
        }
    }
    private func beginNavigation() {
        pageID = UUID(); validResponse = false; finished = false; loading = true; error = nil
        committedOrigin = nil; cancelPermissions()
        timeout?.cancel()
        let id = pageID
        let timer = DispatchWorkItem { [weak self] in guard let self, self.pageID == id else { return }; self.fail() }
        timeout = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timer)
    }
    func stop() {
        guard !stopped else { return }
        stopped = true; pageID = UUID(); timeout?.cancel(); committedOrigin = nil; cancelPermissions()
        loading = false; finished = false; mounted = false
        onReady = nil; onFailure = nil; view.navigationDelegate = nil; view.uiDelegate = nil; view.stopLoading()
        stopMedia()
    }
    private func stopMedia(completion: (() -> Void)? = nil) {
        if let completion { mediaCompletions.append(completion) }
        guard !cleaningMedia else { return }
        cleaningMedia = true
        view.pauseAllMediaPlayback {
            self.view.setCameraCaptureState(.none) {
                self.view.setMicrophoneCaptureState(.none) {
                    self.cleaningMedia = false
                    let completions = self.mediaCompletions; self.mediaCompletions = []
                    completions.forEach { $0() }
                }
            }
        }
    }
    private func cancelPermissions() {
        permissionTask?.cancel(); permissionTask = nil
        let pending = permissions; permissions = []
        pending.forEach { $0.complete(.deny) }
    }
    private func deliver() { if isReady { onReady?() } }
    private func fail() { guard !stopped else { return }; timeout?.cancel(); pageID = UUID(); loading = false; finished = false; validResponse = false
        if let current { retiredNavigations.insert(ObjectIdentifier(current)) }
        current = nil; committedOrigin = nil; cancelPermissions(); view.stopLoading(); stopMedia()
        error = "This page could not be opened. Please try again."; onFailure?() }
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
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard !stopped, current === navigation, let url = webView.url else { return }
        committedOrigin = Self.origin(url)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if current === navigation { fail() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if current === navigation { fail() } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !stopped, let url = navigationAction.request.url, ConfiguredCoreEvent.webURL(url.absoluteString) != nil else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame == nil { load(url); decisionHandler(.cancel) } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard webView === view, let requested = Self.origin(origin),
              Self.origin(frame.securityOrigin) == requested, acceptsCapture(from: requested),
              type == .camera || type == .microphone || type == .cameraAndMicrophone else {
            decisionHandler(.deny); return
        }
        permissions.append(Permission(page: pageID, origin: requested, type: type, complete: decisionHandler))
        processPermissions()
    }
    private func acceptsCapture(from origin: String) -> Bool {
        guard !stopped, !cleaningMedia, error == nil, let top = view.url else { return false }
        return origin == trustedOrigin && committedOrigin == origin && Self.origin(top) == origin
    }
    private func processPermissions() {
        guard permissionTask == nil, !permissions.isEmpty else { return }
        let page = pageID
        permissionTask = Task { @MainActor in
            while let request = permissions.first, !Task.isCancelled, pageID == page {
                guard request.page == page, acceptsCapture(from: request.origin) else {
                    permissions.removeFirst().complete(.deny); continue
                }
                let type = request.type
                var allowed = true
                if type == .camera || type == .cameraAndMicrophone { allowed = await AtelierCaptureAuthorization.shared.authorize(.video) }
                guard !Task.isCancelled, pageID == page, !stopped else { return }
                if type == .microphone || type == .cameraAndMicrophone { let mic = await AtelierCaptureAuthorization.shared.authorize(.audio); allowed = allowed && mic }
                guard !Task.isCancelled, pageID == page, !stopped, permissions.first?.id == request.id else { return }
                permissions.removeFirst().complete(allowed && acceptsCapture(from: request.origin) ? .grant : .deny)
            }
            if pageID == page, !Task.isCancelled { permissionTask = nil }
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
