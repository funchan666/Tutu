import Foundation
import CoreFoundation

enum ConfiguredRealtimeError: Error {
    case invalidTicket
    case unresolvedPlaceholder
    case invalidConnectionContainer
    case invalidFrame
}

struct ConfiguredRealtimeTicket {
    let roomID: String?
    let clientID: String?
    let url: URL
    let expiresAt: Date?
    let attachJSON: String

    static func parseConnectionValue(_ value: Any, now: Date = Date()) throws -> Self {
        let fields: [String: Any]
        if let object = value as? [String: Any] {
            fields = object
        } else if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#{"), trimmed.hasSuffix("}") {
                throw ConfiguredRealtimeError.unresolvedPlaceholder
            }
            guard let bytes = text.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw ConfiguredRealtimeError.invalidConnectionContainer
            }
            fields = object
        } else {
            throw ConfiguredRealtimeError.invalidConnectionContainer
        }
        return try Self(connectionFields: fields, now: now)
    }

    init(connectionFields: [String: Any], now: Date = Date()) throws {
        guard let rawURL = connectionFields["url"] as? String,
              !rawURL.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "wss",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil,
              let url = URL(string: rawURL),
              let attach = connectionFields["attach"] as? [String: Any], !attach.isEmpty,
              JSONSerialization.isValidJSONObject(attach),
              let bytes = try? JSONSerialization.data(withJSONObject: attach),
              let json = String(data: bytes, encoding: .utf8) else {
            throw ConfiguredRealtimeError.invalidTicket
        }
        var room: String?
        if let value = connectionFields["roomId"] {
            guard let text = value as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfiguredRealtimeError.invalidTicket
            }
            room = text
        }
        var client: String?
        if let value = connectionFields["clientId"] {
            guard let text = value as? String, text == "app" else {
                throw ConfiguredRealtimeError.invalidTicket
            }
            client = text
        }
        var expiry: Date?
        if let value = connectionFields["expiresAt"] {
            guard let milliseconds = Self.number(value),
                  milliseconds / 1000 > now.timeIntervalSince1970 else {
                throw ConfiguredRealtimeError.invalidTicket
            }
            expiry = Date(timeIntervalSince1970: milliseconds / 1000)
        }
        roomID = room
        clientID = client
        self.url = url
        expiresAt = expiry
        attachJSON = json
    }

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number.rounded() == number else { return nil }
        return Int(exactly: number)
    }
}

struct ConfiguredRealtimeFrame {
    let action: Int
    let object: [String: Any]

    init(json: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let action = ConfiguredRealtimeTicket.integer(object["action"]) else {
            throw ConfiguredRealtimeError.invalidFrame
        }
        self.action = action
        self.object = object
    }

    var errorCode: Int? {
        let error = object["error"] as? [String: Any]
        return ConfiguredRealtimeTicket.integer(error?["code"])
    }

    var idleTimeoutSeconds: TimeInterval? {
        let details = object["connectionDetails"] as? [String: Any]
        guard let milliseconds = ConfiguredRealtimeTicket.number(details?["maxIdleInterval"]),
              milliseconds > 0 else { return nil }
        return milliseconds / 1000 + 5
    }

    var messageEntries: [Any]? { object["messages"] as? [Any] }
}

struct ConfiguredRealtimeConfiguration {
    let ticket: ConfiguredRealtimeTicket
    let channelName: String

    init(connectionValue: Any) throws {
        let ticket = try ConfiguredRealtimeTicket.parseConnectionValue(connectionValue)
        guard let bytes = ticket.attachJSON.data(using: .utf8),
              let attach = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              ConfiguredRealtimeTicket.integer(attach["action"]) == 10,
              let channel = attach["channel"] as? String,
              !channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfiguredRealtimeError.invalidTicket
        }
        self.ticket = ticket
        channelName = channel
    }
}

struct ConfiguredRealtimeMessage {
    let id: String?
    let name: String?
    let clientId: String?
    let data: Any?
}

private final class RealtimeRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class ConfiguredRealtimeTransport {
    enum State { case connecting, connected, subscribed, reconnecting, failed, closed, stopped }
    typealias Refresh = @MainActor () async throws -> ConfiguredRealtimeConfiguration
    var onMessage: ((ConfiguredRealtimeMessage) -> Void)?
    var onState: ((State) -> Void)?

    private struct Pending {
        let completion: (Bool) -> Void
        let send: Task<Void, Never>
        let timeout: Task<Void, Never>
    }
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var configuration: ConfiguredRealtimeConfiguration?
    private var refresh: Refresh?
    private var generation = UUID()
    private var lifecycle = UUID()
    private var receiveTask: Task<Void, Never>?
    private var attachTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var subscribeTask: Task<Void, Never>?
    private var subscriptionDeadline: Date?
    private var nextRefresh: Date?
    private var lastFrame = Date.distantPast
    private var idleInterval: TimeInterval?
    private var stopped = true
    private var attaching = false
    private var ready = false
    private var retryCount = 0
    private var serial = 0
    private var pending: [Int: Pending] = [:]
    private var earlyMessages: [ConfiguredRealtimeMessage] = []
    private var sendTail: Task<Void, Never>?

    func start(configuration: ConfiguredRealtimeConfiguration, refresh: @escaping Refresh) {
        stop()
        self.configuration = configuration
        self.refresh = refresh
        stopped = false
        retryCount = 0
        open()
    }

    func stop() {
        lifecycle = UUID()
        stopped = true
        retireSocket()
        refresh = nil
        configuration = nil
        onState?(.stopped)
    }

    private func retireSocket(cancelRefresh: Bool = true) {
        generation = UUID()
        receiveTask?.cancel(); receiveTask = nil
        attachTask?.cancel(); attachTask = nil
        if cancelRefresh { refreshTask?.cancel(); refreshTask = nil }
        retryTask?.cancel(); retryTask = nil
        expiryTask?.cancel(); expiryTask = nil
        idleTask?.cancel(); idleTask = nil
        subscribeTask?.cancel(); subscribeTask = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        sendTail?.cancel(); sendTail = nil
        earlyMessages = []
        attaching = false; ready = false; idleInterval = nil
        subscriptionDeadline = nil; nextRefresh = nil
        let callbacks = Array(pending.values)
        pending = [:]
        for item in callbacks { item.send.cancel(); item.timeout.cancel(); item.completion(false) }
    }

    private func open() {
        guard !stopped, let configuration else { return }
        retireSocket()
        if let expiry = configuration.ticket.expiresAt, expiry <= Date() {
            renew(); return
        }
        let id = generation
        let options = URLSessionConfiguration.ephemeral
        options.waitsForConnectivity = true
        options.timeoutIntervalForRequest = 15
        options.urlCache = nil
        options.httpCookieStorage = nil
        let session = URLSession(configuration: options, delegate: RealtimeRedirectPolicy(), delegateQueue: nil)
        let socket = session.webSocketTask(with: configuration.ticket.url)
        self.session = session; self.socket = socket
        serial = 0
        lastFrame = Date()
        let deadline = Date().addingTimeInterval(15)
        subscriptionDeadline = deadline
        subscribeTask = Task { [weak self] in
            do { try await Self.wait(until: deadline) } catch { return }
            guard let self, self.generation == id, !self.ready else { return }
            self.reconnect()
        }
        onState?(.connecting)
        socket.resume()
        receiveTask = Task { [weak self, socket] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == id, !self.stopped, !Task.isCancelled else { return }
                    self.lastFrame = Date()
                    self.armIdle()
                    let bytes: Data
                    switch message {
                    case .string(let text): bytes = Data(text.utf8)
                    case .data(let data): bytes = data
                    @unknown default: throw ConfiguredRealtimeError.invalidFrame
                    }
                    self.consume(try ConfiguredRealtimeFrame(json: bytes))
                }
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.reconnect()
            }
        }
        armExpiry()
    }

    private func consume(_ frame: ConfiguredRealtimeFrame) {
        guard !stopped, let configuration else { return }
        switch frame.action {
        case 0: break
        case 1, 2: acknowledge(frame)
        case 4:
            guard !attaching, !ready else { return }
            guard let interval = frame.idleTimeoutSeconds else { reconnect(); return }
            if let details = frame.object["connectionDetails"] as? [String: Any],
               let client = details["clientId"], client as? String != IntegrationContract.ablyClientID {
                terminate(.failed); return
            }
            idleInterval = interval; armIdle(); attaching = true
            let id = generation
            guard let socket else { return }
            attachTask = Task { [weak self, socket] in
                do { try await socket.send(.string(configuration.ticket.attachJSON)) }
                catch {
                    guard let self, self.generation == id, !Task.isCancelled else { return }
                    self.reconnect()
                }
            }
            onState?(.connected)
        case 11:
            guard attaching, !ready, frame.object["channel"] as? String == configuration.channelName else { return }
            ready = true; attaching = false; retryCount = 0
            subscribeTask?.cancel(); subscribeTask = nil; subscriptionDeadline = nil
            let id = generation
            let buffered = earlyMessages; earlyMessages = []
            onState?(.subscribed)
            for message in buffered {
                guard generation == id, !stopped else { return }
                onMessage?(message)
            }
        case 15:
            guard ready || attaching,
                  frame.object["channel"] as? String == configuration.channelName,
                  let entries = frame.messageEntries else { return }
            let id = generation
            for (index, entry) in entries.enumerated() {
                guard generation == id, !stopped else { return }
                guard let message = entry as? [String: Any] else { continue }
                if let name = message["name"], !(name is NSNull), !(name is String) { continue }
                if let sender = message["clientId"], !(sender is NSNull), !(sender is String) { continue }
                if let messageID = message["id"], !(messageID is NSNull), !(messageID is String) { continue }
                if let encoding = message["encoding"], !(encoding is NSNull), !(encoding is String) { continue }
                let encoding = message["encoding"] as? String ?? ""
                guard encoding.isEmpty || encoding == "json" || encoding == "utf8" else { continue }
                var data = message["data"]
                if let text = data as? String, let bytes = text.data(using: .utf8) {
                    if let object = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) { data = object }
                    else if encoding == "json" { continue }
                }
                let frameID = (frame.object["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let transportID = (message["id"] as? String) ?? frameID.map { "\($0):\(index)" }
                let decoded = ConfiguredRealtimeMessage(id: transportID,
                    name: message["name"] as? String, clientId: message["clientId"] as? String, data: data)
                if ready { onMessage?(decoded) }
                else if earlyMessages.count < 64 { earlyMessages.append(decoded) }
                else { reconnect(); return }
            }
        case 6: reconnect()
        case 8: terminate(.closed)
        case 9:
            if let channel = frame.object["channel"] as? String, channel != configuration.channelName { return }
            if let code = frame.errorCode, (40140...40143).contains(code) { reconnect(immediate: true) }
            else { reconnect() }
        case 13:
            if frame.object["channel"] as? String == configuration.channelName { reconnect() }
        case 17: renew()
        default: break
        }
    }

    private func terminate(_ state: State) {
        lifecycle = UUID()
        stopped = true
        retireSocket()
        configuration = nil; refresh = nil
        onState?(state)
    }

    private func reconnect(immediate: Bool = false) {
        guard !stopped, retryTask == nil else { return }
        if refreshTask != nil {
            retireSocket(cancelRefresh: false)
            onState?(.reconnecting)
            return
        }
        retireSocket()
        onState?(.reconnecting)
        if immediate, retryCount == 0 { retryCount = 1; renew(); return }
        let delay = min(30, pow(2, Double(min(retryCount, 5)))) * Double.random(in: 0.8...1.2)
        retryCount = min(6, retryCount + 1)
        let id = generation
        retryTask = Task { [weak self] in
            do { try await Self.wait(until: Date().addingTimeInterval(delay)) } catch { return }
            guard let self, self.generation == id, !self.stopped else { return }
            self.retryTask = nil
            self.renew()
        }
    }

    private func renew() {
        guard !stopped, refreshTask == nil, let refresh, let previous = configuration else { return }
        let id = lifecycle
        refreshTask = Task { [weak self] in
            do {
                let updated = try await refresh()
                guard let self, self.lifecycle == id, !self.stopped, !Task.isCancelled else { return }
                self.refreshTask = nil
                guard updated.channelName == previous.channelName,
                      previous.ticket.roomID == nil || updated.ticket.roomID == previous.ticket.roomID else {
                    self.terminate(.failed); return
                }
                self.configuration = updated
                self.open()
            } catch {
                guard let self, self.lifecycle == id, !self.stopped, !Task.isCancelled else { return }
                self.refreshTask = nil
                self.reconnect()
            }
        }
    }

    private func armExpiry() {
        expiryTask?.cancel(); expiryTask = nil
        guard let expiry = configuration?.ticket.expiresAt else { return }
        let remaining = expiry.timeIntervalSinceNow
        let delay = remaining > 60 ? remaining - 60 : max(0.5, remaining * 0.8)
        let deadline = Date().addingTimeInterval(delay)
        nextRefresh = deadline
        let id = generation
        expiryTask = Task { [weak self] in
            do { try await Self.wait(until: deadline) } catch { return }
            guard let self, self.generation == id, !self.stopped else { return }
            self.renew()
        }
    }

    private func armIdle() {
        idleTask?.cancel(); idleTask = nil
        guard let idleInterval else { return }
        let deadline = lastFrame.addingTimeInterval(idleInterval)
        let id = generation
        idleTask = Task { [weak self] in
            do { try await Self.wait(until: deadline) } catch { return }
            guard let self, self.generation == id, !self.stopped else { return }
            self.reconnect()
        }
    }

    func resume() {
        guard !stopped, refreshTask == nil else { return }
        let now = Date()
        if socket == nil {
            retryTask?.cancel(); retryTask = nil
            renew()
        } else if let expiry = configuration?.ticket.expiresAt, expiry <= now {
            reconnect(immediate: true)
        } else if let nextRefresh, nextRefresh <= now {
            reconnect(immediate: true)
        } else if let deadline = subscriptionDeadline, deadline <= now {
            reconnect(immediate: true)
        } else if let interval = idleInterval, now.timeIntervalSince(lastFrame) >= interval {
            reconnect(immediate: true)
        } else if socket?.state == .completed || socket?.state == .canceling {
            reconnect(immediate: true)
        }
    }

    func publish(name: String, payload: Any, completion: @escaping (Bool) -> Void) {
        guard !stopped, ready, let socket, socket.state == .running, let configuration, pending.count < 256,
              configuration.ticket.expiresAt.map({ $0 > Date() }) ?? true,
              serial < Int.max, JSONSerialization.isValidJSONObject(payload),
              let bytes = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: bytes, encoding: .utf8) else { completion(false); return }
        let number = serial
        let object: [String: Any] = ["action": 15, "channel": configuration.channelName, "msgSerial": number,
            "messages": [["name": name, "data": json, "encoding": "json", "clientId": IntegrationContract.ablyClientID]]]
        guard let encoded = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: encoded, encoding: .utf8) else { completion(false); return }
        serial += 1
        let id = generation
        let previousSend = sendTail
        let send = Task { [weak self, socket] in
            await previousSend?.value
            guard !Task.isCancelled, let self, self.generation == id, self.ready else { return }
            do { try await socket.send(.string(text)) }
            catch {
                guard self.generation == id, !Task.isCancelled else { return }
                self.complete(number, success: false)
                self.reconnect()
            }
        }
        let timeout = Task { [weak self] in
            do { try await Self.wait(until: Date().addingTimeInterval(20)) } catch { return }
            guard let self, self.generation == id else { return }
            self.reconnect()
        }
        pending[number] = Pending(completion: completion, send: send, timeout: timeout)
        sendTail = send
    }

    private func acknowledge(_ frame: ConfiguredRealtimeFrame) {
        let start: Int?
        if frame.object["msgSerial"] == nil { start = 0 }
        else { start = ConfiguredRealtimeTicket.integer(frame.object["msgSerial"]) }
        guard let start, start >= 0,
              let count = ConfiguredRealtimeTicket.integer(frame.object["count"]), count > 0,
              start <= Int.max - count, start + count <= serial else { return }
        let end = start + count
        for number in pending.keys.sorted() where number < end {
            complete(number, success: number >= start && frame.action == 1)
        }
    }

    private func complete(_ number: Int, success: Bool) {
        guard let item = pending.removeValue(forKey: number) else { return }
        item.send.cancel(); item.timeout.cancel(); item.completion(success)
    }

    private static func wait(until deadline: Date) async throws {
        while deadline.timeIntervalSinceNow > 0 {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(max(0, min(deadline.timeIntervalSinceNow, 86_400))))
        }
        try Task.checkCancellation()
    }
}
