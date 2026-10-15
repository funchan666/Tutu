import SwiftUI
import Alamofire

@MainActor final class AtelierGateway: ObservableObject {
    enum RouteState { case undecided, preparingWeb, native, web, webFailure }
    enum Identity { case email(String, String), apple(String, String?, String?), guest, restore }
    @Published private(set) var busy = false
    @Published private(set) var checking = true
    @Published private(set) var mode = ConfiguredLoginEntryMode.standard
    @Published private(set) var error = ""
    @Published private(set) var route = RouteState.undecided
    @Published private(set) var web: AtelierWeb?
    @Published private(set) var contentLoading = false
    @Published private(set) var contentError = ""
    private var attempt = UUID()
    private var entryGeneration = UUID()
    private var contentGeneration = UUID()
    private var authTask: Task<Void, Never>?
    private var entryTask: Task<Void, Never>?
    private var contentTask: Task<Void, Never>?
    private var connectionDeadline: DispatchWorkItem?
    private var routeDeadline: DispatchWorkItem?
    private var transport: ConfiguredRealtimeTransport?
    private let social = AtelierSocial()
    private var channelName = ""
    private var pendingSocial: [(String?, Any?)] = []
    private var reachability: NetworkReachabilityManager?
    private var identity: Identity?
    private var connected = false
    private var committing = false
    private var commitTask: Task<Void, Never>?
    private var entryResolved = false
    private var readyWeb = false
    private var seen = Set<String>()
    private var queued: [ConfiguredCoreEvent] = []
    private weak var store: AppStore?
    private weak var wallet: WalletService?
    private var started = false
    private var active = true

    func start(store: AppStore, wallet: WalletService) {
        guard !started else { return }; started = true; self.store = store; self.wallet = wallet
        wallet.start(store: store)
        reachability = NetworkReachabilityManager()
        reachability?.startListening(onUpdatePerforming: { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if state != .notReachable {
                    self.transport?.resume()
                    if !self.busy && store.state == nil { self.detectEntry() }
                    await wallet.recover(store: store)
                }
            }
        })
        if UserDefaults.standard.string(forKey: "activeProfile") != nil {
            if reserve() { identity = .restore; authenticate(extras: [:]) }
        } else { detectEntry() }
    }
    func foreground(_ active: Bool) {
        self.active = active
        social.foreground(active)
        if active {
            AtelierPush.shared.foreground()
            transport?.resume()
            if readyWeb { finish(as: .web) }
            if !busy, store?.state == nil { detectEntry() }
            if let store, let wallet { Task { await wallet.recover(store: store) } }
            drainEvents()
        } else { entryTask?.cancel(); entryTask = nil }
    }
    func wake(_ url: URL) {
        guard url.scheme == Bundle.main.bundleIdentifier else { return }
        foreground(true)
    }
    func detectEntry() {
        guard !busy, active, store?.state == nil, entryTask == nil, !entryResolved else { return }
        let ticket = entryGeneration
        entryTask = Task { [weak self] in
            guard let self else { return }
            var backoff = 2
            while !Task.isCancelled, self.entryGeneration == ticket, !self.busy {
                do {
                    async let fields = AtelierHTTP.arrivalFields()
                    try await AtelierHTTP.head()
                    let (bytes, http) = try await AtelierHTTP.response(path: IntegrationContract.optionsPath, body: fields)
                    let object = try AtelierHTTP.object(bytes)
                    guard self.entryGeneration == ticket, !Task.isCancelled, !self.busy else { return }
                    if (200..<300).contains(http.statusCode), AtelierHTTP.zero(object["code"]), let mode = ConfiguredLoginEntryMode.parse(data: object["data"]) {
                        self.mode = mode
                    } else {
                        self.mode = .standard
                        #if DEBUG
                        print("[Tutu entrance] invalid configuration; standard fallback")
                        #endif
                    }
                    self.checking = false; self.entryResolved = true; self.entryTask = nil; return
                } catch {
                    guard self.entryGeneration == ticket, !Task.isCancelled, !self.busy else { return }
                    self.checking = false; self.mode = .standard
                    if !(error is URLError) { self.entryResolved = true; self.entryTask = nil; return }
                    do { try await Task.sleep(for: .seconds(backoff)) } catch { return }
                    backoff = min(30, backoff * 2)
                }
            }
        }
    }
    @discardableResult func reserve() -> Bool {
        guard !busy else { return false }
        busy = true; error = ""; route = .undecided; identity = nil; connected = false; committing = false; readyWeb = false
        attempt = UUID(); entryGeneration = UUID(); entryTask?.cancel(); entryTask = nil
        connectionDeadline?.cancel(); routeDeadline?.cancel(); authTask?.cancel(); commitTask?.cancel()
        checking = false; seen = []; queued = []
        social.stop(); pendingSocial = []
        web?.stop(); web = nil; transport?.stop(); transport = nil
        reloadContent()
        return true
    }
    func email(_ email: String, password: String, creating: Bool, name: String) {
        guard mode == .standard, reserve() else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.contains("@"), !password.isEmpty, !creating || (!name.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 8) else { fail("Enter a valid email, password and name."); return }
        identity = .email(address, creating ? name : "Style Friend")
        authenticate(extras: [ConfiguredWireFields.arrival_kind: "email", ConfiguredWireFields.arrival_scene: creating ? "register" : "login", ConfiguredWireFields.style_mailbox: address, ConfiguredWireFields.style_secret: password])
    }
    func guest() {
        guard mode == .guestOnly, reserve() else { return }; identity = .guest
        authenticate(extras: [ConfiguredWireFields.arrival_kind: "guest", ConfiguredWireFields.arrival_scene: "login"])
    }
    func apple(user: String, token: Data?, code: Data?, name: String?, email: String?) {
        guard busy, mode == .standard, let token, let code, let assertion = String(data: token, encoding: .utf8), let exchange = String(data: code, encoding: .utf8), !assertion.isEmpty, !exchange.isEmpty else { fail("Apple sign-in couldn't be completed. Please try again."); return }
        identity = .apple(user, name, email)
        authenticate(extras: [ConfiguredWireFields.arrival_kind: "apple", ConfiguredWireFields.arrival_scene: "login", ConfiguredWireFields.apple_member: user, ConfiguredWireFields.apple_identity: assertion, ConfiguredWireFields.apple_exchange: exchange])
    }
    func appleCancelled() { fail("") }
    private func authenticate(extras: [String: Any]) {
        let id = attempt
        authTask = Task {
            do {
                let fields = try await AtelierHTTP.arrivalFields(extras: extras)
                let (bytes, http) = try await AtelierHTTP.response(path: IntegrationContract.entryPath, body: fields)
                guard id == attempt, !Task.isCancelled else { return }
                let object = try AtelierHTTP.object(bytes)
                guard (200..<300).contains(http.statusCode) || http.statusCode == 401 else { throw AtelierHTTP.Failure.authentication }
                if let data = object["data"], !(data is NSNull) {
                    guard let data = data as? [String: Any] else { throw AtelierHTTP.Failure.invalidResponse }
                    if !data.isEmpty { connect(try configuration(data), attempt: id); return }
                }
                guard (200..<300).contains(http.statusCode), AtelierHTTP.zero(object["code"]) else { throw AtelierHTTP.Failure.authentication }
                finish(as: .native)
            } catch { if id == attempt, !Task.isCancelled { fail(error.localizedDescription) } }
        }
    }
    private func configuration(_ data: [String: Any]) throws -> ConfiguredRealtimeConfiguration {
        guard let value = data["token"] else { throw AtelierHTTP.Failure.invalidResponse }
        return try ConfiguredRealtimeConfiguration(connectionValue: value)
    }
    private func connect(_ config: ConfiguredRealtimeConfiguration, attempt id: UUID) {
        let client = ConfiguredRealtimeTransport(); transport = client; channelName = config.channelName
        client.onState = { [weak self] state in
            guard let self, self.attempt == id else { return }
            switch state {
            case .subscribed:
                self.social.attached()
                guard !self.connected else { return }
                self.connected = true; self.connectionDeadline?.cancel()
                if self.route == .undecided {
                    let timer = DispatchWorkItem { [weak self] in
                        guard let self, self.attempt == id, self.route == .undecided else { return }
                        self.finish(as: .native)
                    }
                    self.routeDeadline = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timer)
                }
            case .failed, .closed:
                if self.busy { self.fail("Connection unavailable. Please try again.") }
            default: break
            }
        }
        client.onMessage = { [weak self] message in
            guard let self, self.attempt == id else { return }
            let sender = message.clientId ?? ""
            guard sender != IntegrationContract.ablyClientID,
                  sender.isEmpty ? IntegrationContract.allowsMissingSender : IntegrationContract.serverClientIDs.contains(sender) else { return }
            if self.social.receive(name: message.name, data: message.data) { return }
            do {
                let event = try ConfiguredCoreEvent.parse(requestID: id, transportID: message.id,
                    name: message.name, clientID: message.clientId, data: message.data)
                guard self.seen.insert(event.messageID).inserted else { return }
                self.receive(event)
            } catch {
                if self.store?.state == nil, self.pendingSocial.count < 64 { self.pendingSocial.append((message.name, message.data)) }
                #if DEBUG
                print("[Tutu event] ignored: invalid or unrecognized event")
                #endif
            }
        }
        let timer = DispatchWorkItem { [weak self] in guard let self, self.attempt == id, !self.connected else { return }; self.fail("Connection timed out. Please try again.") }
        connectionDeadline = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timer)
        client.start(configuration: config) { [weak self] in
            guard let self, self.attempt == id else { throw CancellationError() }
            let fields = try await AtelierHTTP.arrivalFields()
            try Task.checkCancellation()
            guard self.attempt == id else { throw CancellationError() }
            let (bytes, http) = try await AtelierHTTP.response(path: IntegrationContract.entryPath, body: fields)
            try Task.checkCancellation()
            guard self.attempt == id else { throw CancellationError() }
            guard (200..<300).contains(http.statusCode) || http.statusCode == 401,
                  let data = try AtelierHTTP.object(bytes)["data"] as? [String: Any] else { throw AtelierHTTP.Failure.authentication }
            return try self.configuration(data)
        }
    }
    private func receive(_ event: ConfiguredCoreEvent) {
        guard event.requestID == attempt else { return }
        if event.kind == .expire { reset(); store?.signOut(); detectEntry(); return }
        if event.kind == .page {
            guard !committing else { return }
            if route == .native { return }
            switch event.pageDestination {
            case .absent: if route == .undecided { routeDeadline?.cancel(); finish(as: .native) }
            case .url(let url):
                routeDeadline?.cancel()
                if route == .web { web?.load(url) }
                else if route == .undecided { prepareWeb(url) }
            case .invalid: routeDeadline?.cancel(); route = .webFailure; busy = false; error = "This page address is unavailable. Please sign in again."; connectionDeadline?.cancel()
            case .notPage: break
            }
            return
        }
        if !active || store?.state == nil { if queued.count < 64 { queued.append(event) }; return }
        switch event.kind {
        case .purchase: if let store, let wallet { Task { await wallet.purchase(event: event, store: store) } }
        case .externalOpen:
            if let url = event.externalURL { UIApplication.shared.open(url, options: [:]) { success in
                #if DEBUG
                print("[Tutu destination] opened=\(success)")
                #endif
            } }
        default: break
        }
    }
    private func drainEvents() { guard active, store?.state != nil else { return }; let events = queued; queued = []; events.forEach(receive) }
    private func prepareWeb(_ url: URL) {
        route = .preparingWeb; let id = attempt
        let owner = AtelierWeb(url: url)
        owner.onReady = { [weak self] in guard let self, self.attempt == id else { return }; self.readyWeb = true; if self.active { self.finish(as: .web) } }
        owner.onFailure = { [weak self] in guard let self, self.attempt == id else { return }; if self.route != .web { self.route = .webFailure; self.busy = false; self.error = "This page could not be opened. Please try again." } }
        web = owner; owner.load()
    }
    func retryWeb() { guard let web else { return }; busy = true; error = ""; route = .preparingWeb; web.load() }
    private func finish(as destination: RouteState) {
        guard route != .native, route != .web, !committing, let store, let identity else { return }
        committing = true; routeDeadline?.cancel(); connectionDeadline?.cancel()
        let id = attempt
        commitTask = Task {
            do {
                guard id == attempt, !Task.isCancelled else { return }
                switch identity {
                case .restore: await store.restoreSession { [weak self] in self?.attempt == id }; guard store.state != nil else { throw AtelierHTTP.Failure.authentication }
                case .email(let email, let name): try store.installAuthenticatedProfile(email: email, name: name, appleID: nil)
                case .apple(let apple, let name, let email): try store.installAuthenticatedProfile(email: email ?? "", name: name ?? "Style Friend", appleID: apple)
                case .guest: try store.installAuthenticatedProfile(email: "guest-" + AtelierKeychain.deviceID() + "@local.tutu", name: "Style Friend", appleID: nil)
                }
                guard id == attempt else { return }
                route = destination; busy = false; committing = false; error = ""
                if let transport {
                    social.start(store: store, transport: transport, channel: channelName)
                    social.foreground(active)
                    let pending = pendingSocial; pendingSocial = []
                    pending.forEach { _ = social.receive(name: $0.0, data: $0.1) }
                }
                drainEvents()
            } catch { if id == attempt { fail(error.localizedDescription) } }
        }
    }
    func reloadContent() {
        contentTask?.cancel(); contentGeneration = UUID(); let id = contentGeneration
        contentLoading = true; contentError = ""
        contentTask = Task {
            do {
                async let editorial = AtelierHTTP.content([EditorialItem].self, path: ConfiguredContentPaths.editorial)
                async let rooms = AtelierHTTP.content([StyleRoom].self, path: ConfiguredContentPaths.rooms)
                async let settings = AtelierHTTP.content(AtelierSettings.self, path: ConfiguredContentPaths.atelier)
                let snapshot = try await AtelierSnapshot(editorial: editorial, rooms: rooms, settings: settings)
                try Task.checkCancellation(); try snapshot.validate()
                guard id == contentGeneration else { return }
                Catalog.snapshot = snapshot; contentLoading = false; store?.contentDidChange(); social.contentReady()
            } catch { if id == contentGeneration, !Task.isCancelled { contentLoading = false; contentError = "Your style collection couldn't be loaded. Please try again." } }
        }
    }
    func readNotice(_ id: String) { social.markRead(id) }
    private func fail(_ message: String) {
        social.stop(); pendingSocial = []
        attempt = UUID(); authTask?.cancel(); commitTask?.cancel(); connectionDeadline?.cancel(); routeDeadline?.cancel(); transport?.stop(); transport = nil
        web?.stop(); web = nil; route = .undecided
        busy = false; committing = false; error = message; identity = nil; queued = []; readyWeb = false
    }
    func sessionEnded() { reset(); detectEntry() }
    private func reset() {
        social.stop(); pendingSocial = []
        attempt = UUID(); entryGeneration = UUID(); contentGeneration = UUID()
        authTask?.cancel(); commitTask?.cancel(); entryTask?.cancel(); entryTask = nil; contentTask?.cancel()
        connectionDeadline?.cancel(); routeDeadline?.cancel(); transport?.stop(); transport = nil
        web?.stop(); web = nil; identity = nil; queued = []; seen = []
        busy = false; checking = true; entryResolved = false; mode = .standard; error = ""; route = .undecided; committing = false; readyWeb = false
    }
}
