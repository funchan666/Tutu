import Foundation
import CryptoKit
import CoreFoundation

struct AtelierNotice: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    var read = false
}
struct AtelierPresence: Codable {
    let online: Bool
    let version: Int64
    let expires: Double
}
struct AtelierSocialRecord: Codable {
    let id: String
    let kind: String
    let payload: Data
    let digest: String
    let expires: Double
    var stage = 1
}
struct AtelierReceiptEvent: Codable {
    let id: String
    let message: String
    let kind: String
    let stage: String
    let sequence: Int
    let state: String
}
struct AtelierSocialState: Codable {
    var records: [String: AtelierSocialRecord] = [:]
    var outbox: [String: AtelierReceiptEvent] = [:]
    var notices: [AtelierNotice] = []
    var presence: [String: AtelierPresence] = [:]
    var posts: [Look] = []
}
@MainActor final class AtelierSocial {
    static let supported = ["AtelierBulletin", "RunwayPresence", "CircleLookPublished"]
    private weak var store: AppStore?
    private var transport: ConfiguredRealtimeTransport?
    private var scope = ""
    private var account = ""
    private var generation = UUID()
    private var timer: Task<Void, Never>?
    private var sending = Set<String>()
    private var nextSend: [String: Date] = [:]
    private var attempts: [String: Int] = [:]
    private var active = true
    private var nextSync = Date.distantPast
    func start(store: AppStore, transport: ConfiguredRealtimeTransport, channel: String) {
        stop()
        guard let id = store.sessionID else { return }
        self.store = store; self.transport = transport; account = id
        scope = Self.digest(Data((IntegrationContract.baseURLString! + "|" + channel).utf8))
        store.socialScope = scope
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        sync(reason: "session")
    }
    func stop() {
        generation = UUID(); timer?.cancel(); timer = nil
        if store?.socialScope == scope { store?.socialScope = nil }
        store = nil; transport = nil; sending = []; nextSend = [:]; attempts = [:]
    }
    func foreground(_ value: Bool) { active = value; if value { sync(reason: "foreground"); tick() } }
    func attached() { sync(reason: "attached"); tick() }
    private var valid: Bool { store?.sessionID == account && !scope.isEmpty }
    private var state: AtelierSocialState { store?.state?.social?[scope] ?? AtelierSocialState() }
    @discardableResult private func save(_ operation: (inout AtelierSocialState) -> Void) -> Bool {
        guard valid, let store else { return false }
        return store.commit { profile in
            var all = profile.social ?? [:]
            var value = all[scope] ?? AtelierSocialState(); operation(&value); all[scope] = value; profile.social = all
        }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func integer(_ value: Any?) -> Int64? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), !["d", "f"].contains(String(cString: n.objCType)) else { return nil }
        return n.int64Value
    }
    @discardableResult func receive(name: String?, data: Any?) -> Bool {
        guard valid else { return false }
        let object: [String: Any]?
        if let dictionary = data as? [String: Any] { object = dictionary }
        else if let text = data as? String, let bytes = text.data(using: .utf8), bytes.count <= 65_536 { object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] }
        else { object = nil }
        guard let object, let kind = object["stitch"] as? String else { return false }
        if kind == "AtelierReceiptAccepted" {
            if let id = object["receipt"] as? String, state.outbox[id] != nil {
                if save({ $0.outbox[id] = nil }) { sending.remove(id); nextSend[id] = nil; attempts[id] = nil }
            }
            return true
        }
        if kind == "AtelierReceipt" || kind == "AtelierReplayRequest" { return true }
        guard Self.supported.contains(kind) else { return false }
        guard let id = object["thread"] as? String, !id.isEmpty, id.count <= 128,
              let sent = Self.integer(object["issued"]), let expires = Self.integer(object["until"]),
              let details = object["detail"] as? [String: Any],
              let payload = try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]), payload.count <= 60_000,
              let envelope = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), envelope.count <= 65_536 else { return true }
        let now = Date().timeIntervalSince1970 * 1000
        guard sent >= 0, Double(sent) <= now + 30_000, expires > sent, Double(expires) > now,
              expires - sent <= (kind == "RunwayPresence" ? 300_000 : 604_800_000),
              kind != "RunwayPresence" || expires - sent >= 5_000 else { return true }
        let digest = Self.digest(envelope)
        if let old = state.records[id] { guard old.digest == digest else { return true }; apply(id); flush(); return true }
        prune()
        guard state.records.count < 500, state.outbox.count < 900 else { return true }
        let record = AtelierSocialRecord(id: id, kind: kind, payload: payload, digest: digest, expires: Double(expires))
        guard save({ value in value.records[id] = record; Self.receipt(&value, record, stage: "received", sequence: 1) }) else { return true }
        apply(id); flush(); return true
    }
    private static func receipt(_ state: inout AtelierSocialState, _ record: AtelierSocialRecord, stage: String, sequence: Int, success: Bool = true) {
        let id = record.id + ":" + String(sequence)
        state.outbox[id] = AtelierReceiptEvent(id: id, message: record.id, kind: record.kind, stage: stage, sequence: sequence, state: success ? "success" : "failed")
    }
    private func apply(_ id: String) {
        guard let record = state.records[id], record.stage == 1, let store else { return }
        if record.expires <= Date().timeIntervalSince1970 * 1000 {
            save { value in value.records[id]?.stage = 5; Self.receipt(&value, record, stage: "expired", sequence: 5, success: false) }; return
        }
        guard Catalog.snapshot != nil else { return }
        do {
            let detail = try AtelierHTTP.object(record.payload)
            switch record.kind {
            case "AtelierBulletin":
                guard let title = detail["heading"] as? String, let body = detail["copy"] as? String, !title.isEmpty, title.count <= 160, body.count <= 4000 else { throw AtelierHTTP.Failure.invalidResponse }
                let notice = AtelierNotice(id: id, title: title, body: body)
                save { value in
                    value.notices.insert(notice, at: 0)
                    value.records[id]?.stage = 2; Self.receipt(&value, record, stage: "applied", sequence: 2)
                }
            case "RunwayPresence":
                guard let person = detail["member"] as? String, Catalog.people.contains(where: { $0.id == person }),
                      let version = Self.integer(detail["revision"]), version >= 0,
                      let number = detail["online"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw AtelierHTTP.Failure.invalidResponse }
                let ignored = store.isPersonHidden(person) || (state.presence[person]?.version ?? -1) >= version
                save { value in
                    if !ignored { value.presence[person] = AtelierPresence(online: number.boolValue, version: version, expires: record.expires) }
                    value.records[id]?.stage = ignored ? 5 : 2
                    Self.receipt(&value, record, stage: ignored ? "ignored" : "applied", sequence: ignored ? 5 : 2)
                }
            case "CircleLookPublished":
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
                var post = try decoder.decode(Look.self, from: record.payload)
                guard !post.id.isEmpty, post.id.count <= 128, post.text.count <= 4000,
                      post.media.count <= 12, Catalog.people.contains(where: { $0.id == post.authorID }),
                      post.created.timeIntervalSinceNow <= 30 else { throw AtelierHTTP.Failure.invalidResponse }
                try post.media.forEach(AtelierSnapshot.validateMedia)
                if let video = post.video { try AtelierSnapshot.validateMedia(video) }
                let ignored = store.isPersonHidden(post.authorID) || store.isContentHidden("post", post.id) || store.looks.contains(where: { $0.id == post.id })
                guard ignored || state.posts.count < 300 else { return }
                post.localOnly = false
                save { value in
                    if !ignored { value.posts.insert(post, at: 0) }
                    value.records[id]?.stage = ignored ? 5 : 2
                    Self.receipt(&value, record, stage: ignored ? "ignored" : "applied", sequence: ignored ? 5 : 2)
                }
            default: break
            }
        } catch {
            save { value in value.records[id]?.stage = 5; Self.receipt(&value, record, stage: "failed", sequence: 5, success: false) }
        }
    }
    func markRead(_ id: String) {
        guard let record = state.records[id], record.kind == "AtelierBulletin", record.stage >= 2, record.stage < 4 else { return }
        save { value in
            if let index = value.notices.firstIndex(where: { $0.id == id }) { value.notices[index].read = true }
            value.records[id]?.stage = 4; Self.receipt(&value, record, stage: "read", sequence: 4)
        }
        flush()
    }
    func contentReady() { for id in state.records.keys { apply(id) }; tick() }
    private func tick() {
        guard valid, active else { return }
        for id in state.records.keys { apply(id) }
        if store?.notice == nil, let notice = state.notices.first(where: { state.records[$0.id]?.stage == 2 }), let record = state.records[notice.id] {
            if save({ value in value.records[notice.id]?.stage = 3; Self.receipt(&value, record, stage: "displayed", sequence: 3) }) {
                store?.show(notice.title, notice.body)
            }
        }
        store?.objectWillChange.send()
        flush()
        if Date() >= nextSync { sync(reason: "periodic") }
    }
    private func flush() {
        guard valid, active, let transport else { return }
        let ticket = generation
        for item in state.outbox.values where !sending.contains(item.id) && Date() >= (nextSend[item.id] ?? .distantPast) {
            sending.insert(item.id)
            let count = min(6, (attempts[item.id] ?? 0) + 1); attempts[item.id] = count
            nextSend[item.id] = Date().addingTimeInterval(min(60, pow(2, Double(count))))
            let payload: [String: Any] = ["stitch": "AtelierReceipt", "receipt": item.id, "thread": item.message, "kind": item.kind, "state": item.state, "detail": ["stage": item.stage, "sequence": item.sequence]]
            transport.publish(name: "AtelierReceipt", payload: payload) { [weak self] _ in
                Task { @MainActor in guard let self, self.generation == ticket else { return }; self.sending.remove(item.id) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self, self.generation == ticket else { return }; self.sending.remove(item.id)
            }
        }
    }
    private func sync(reason: String) {
        guard valid, active, let transport else { return }
        nextSync = Date().addingTimeInterval(60)
        transport.publish(name: "AtelierReplayRequest", payload: ["stitch": "AtelierReplayRequest", "revision": 1, "request": UUID().uuidString, "reason": reason, "pending": state.records.values.filter { $0.stage == 1 }.map(\.id), "supported": Self.supported]) { _ in }
    }
    private func prune() {
        let now = Date().timeIntervalSince1970 * 1000
        let ids = state.records.values.filter { record in record.stage >= 2 && (record.kind != "AtelierBulletin" || record.stage >= 4) && record.expires < now && !state.outbox.values.contains { $0.message == record.id } }.map(\.id)
        if !ids.isEmpty { save { value in for id in ids { value.records[id] = nil }; value.notices.removeAll { ids.contains($0.id) && $0.read } } }
    }
}
