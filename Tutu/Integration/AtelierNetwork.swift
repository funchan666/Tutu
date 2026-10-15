import Foundation
import UIKit
import Security
import UserNotifications
import Alamofire
import CoreFoundation

struct AtelierKeychain {
    static func read(service: String, key: String) throws -> Data? {
        var result: CFTypeRef?
        let code = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key, kSecReturnData: true] as CFDictionary, &result)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = result as? Data else { throw TutuFailure.message("Secure storage is unavailable. Unlock your device and try again.") }
        return data
    }
    static func write(_ data: Data, service: String, key: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key] as [CFString: Any]
        let code = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if code == errSecItemNotFound {
            var insert = query; insert[kSecValueData] = data; insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AtelierHTTP.Failure.storage }
        } else if code != errSecSuccess { throw AtelierHTTP.Failure.storage }
        guard try read(service: service, key: key) == data else { throw AtelierHTTP.Failure.storage }
    }
    static func accounts(service: String) throws -> [String] {
        var result: CFTypeRef?
        let code = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitAll] as CFDictionary, &result)
        if code == errSecItemNotFound { return [] }
        guard code == errSecSuccess, let rows = result as? [[String: Any]] else { throw AtelierHTTP.Failure.storage }
        return try rows.map { row in
            guard let key = row[kSecAttrAccount as String] as? String else { throw AtelierHTTP.Failure.storage }
            return key
        }
    }
    static func deviceID() throws -> String {
        let service = "com.tutu.style.installation"
        if let data = try read(service: service, key: "atelier-stamp") {
            guard let value = String(data: data, encoding: .utf8), UUID(uuidString: value) != nil else { throw AtelierHTTP.Failure.storage }
            return value
        }
        let id = UUID().uuidString
        try write(Data(id.utf8), service: service, key: "atelier-stamp")
        return id
    }
}
final class AtelierNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum AtelierHTTP {
    enum Failure: LocalizedError {
        case invalidResponse, storage, web, authentication
        var errorDescription: String? {
            switch self {
            case .storage: return "Your purchase could not be saved securely. Please try again."
            case .web: return "This page could not be opened. Please try again."
            case .authentication: return "Sign-in couldn't be completed. Please try again."
            case .invalidResponse: return "This service is temporarily unavailable. Please try again."
            }
        }
    }
    static let redirects = AtelierNoRedirect()
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
    }()
    static var base: URL { URL(string: IntegrationContract.baseURLString!)! }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static func response(path: String, body: [String: Any], origin: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let endpointBase: URL
        if let origin {
            guard let parsed = URL(string: origin) else { throw Failure.invalidResponse }
            endpointBase = parsed
        } else { endpointBase = base }
        guard endpointBase.scheme == "https", endpointBase.host != nil, endpointBase.user == nil, endpointBase.password == nil,
              path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: endpointBase)?.absoluteURL,
              url.host == endpointBase.host, url.scheme == endpointBase.scheme, url.port == endpointBase.port else { throw Failure.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = IntegrationContract.apiMethod
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        #if DEBUG
        if path == IntegrationContract.optionsPath || path == IntegrationContract.entryPath {
            print("[Tutu arrival] \(path) HTTP \(http.statusCode) \(String(data: data, encoding: .utf8) ?? "<non-text>")")
        }
        #endif
        return (data, http)
    }
    static func zero(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
        return String(cString: n.objCType) != "d" && String(cString: n.objCType) != "f" && n.int64Value == 0
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidResponse }
        return object
    }
    struct Envelope<T: Decodable>: Decodable { let code: Int; let message: String; let data: T }
    static func content<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let (bytes, response) = try await self.response(path: path, body: [:])
        guard (200..<300).contains(response.statusCode), zero(try object(bytes)["code"]) else { throw Failure.invalidResponse }
        return try JSONDecoder().decode(Envelope<T>.self, from: bytes).data
    }
    static func head() async throws {
        var request = URLRequest(url: base); request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard response is HTTPURLResponse else { throw Failure.invalidResponse }
    }
    @MainActor static func arrivalFields(extras: [String: Any] = [:]) async throws -> [String: Any] {
        _ = await AtelierPush.shared.waitForToken()
        try Task.checkCancellation()
        var fields = extras
        fields[ConfiguredWireFields.look_edition] = version
        fields[ConfiguredWireFields.atelier_stamp] = try AtelierKeychain.deviceID()
        fields[ConfiguredWireFields.ribbon_signal] = AtelierPush.shared.token
        fields[ConfiguredWireFields.runway_delivery] = IntegrationContract.continuationMode
        return fields
    }
}
@MainActor final class AtelierPush {
    static let shared = AtelierPush()
    private(set) var token = ""
    private var failed = false
    private var requesting = false
    private var waiters: [UUID: CheckedContinuation<String, Never>] = [:]
    private var timers: [UUID: DispatchWorkItem] = [:]
    func start() { UIApplication.shared.registerForRemoteNotifications() }
    func foreground() {
        guard !requesting else { return }; requesting = true
        Task {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]); settings = await center.notificationSettings() }
            requesting = false
            if settings.authorizationStatus == .denied { failed = true; completeAll() }
            else if token.isEmpty { failed = false; start() }
        }
    }
    func received(_ bytes: Data) {
        #if DEBUG
        print("[Tutu push] registration succeeded")
        #endif
        token = bytes.map { String(format: "%02x", $0) }.joined(); failed = false; completeAll() }
    func registrationFailed() {
        #if DEBUG
        print("[Tutu push] registration failed; bounded fallback enabled")
        #endif
        failed = true; completeAll() }
    func waitForToken() async -> String {
        if !token.isEmpty || failed || Task.isCancelled { return token }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: token); return }
                waiters[id] = continuation
                let timer = DispatchWorkItem { [weak self] in self?.complete(id) }
                timers[id] = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)
            }
        } onCancel: { Task { @MainActor in self.complete(id) } }
    }
    private func complete(_ id: UUID) { timers.removeValue(forKey: id)?.cancel(); waiters.removeValue(forKey: id)?.resume(returning: token) }
    private func completeAll() { for id in Array(waiters.keys) { complete(id) } }
}
@MainActor final class AtelierAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { AtelierPush.shared.start(); return true }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { AtelierPush.shared.received(deviceToken) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { AtelierPush.shared.registrationFailed() }
}
