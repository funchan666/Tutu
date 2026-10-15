import Foundation
import StoreKit

struct AtelierOrder: Codable, Equatable, Identifiable {
    enum Mode: String, Codable { case hostLocal, ablyServer }
    enum Phase: String, Codable { case prepared, awaitingApple, paid, localDelivered, serverConfirmed, cancelled, needsReview }
    let id: UUID
    let mode: Mode
    let productID: String
    let accountID: String
    let accountToken: UUID
    let walletInstance: UUID?
    let bundleID: String
    let version: String
    let device: String
    let created: Date
    let coins: Int?
    let orderCode: String?
    let messageID: String?
    let origin: String?
    let path: String?
    let fields: [String]?
    var phase: Phase = .prepared
    var transactionID: String?
    var environment: String?
    var finished = false
}
@MainActor enum AtelierOrders {
    static let service = "com.tutu.style.purchase-orders"
    static func all() throws -> [AtelierOrder] {
        var orders: [AtelierOrder] = []
        for key in try AtelierKeychain.accounts(service: service) {
            do {
                guard let data = try AtelierKeychain.read(service: service, key: key) else { continue }
                let order = try JSONDecoder().decode(AtelierOrder.self, from: data)
                guard order.id.uuidString == key else { continue }
                orders.append(order)
            } catch let error as DecodingError {
                #if DEBUG
                print("[Tutu orders] quarantined undecodable record \(key): \(error)")
                #endif
            }
        }
        return orders
    }
    static func save(_ order: AtelierOrder) throws {
        let bytes = try JSONEncoder().encode(order)
        try AtelierKeychain.write(bytes, service: service, key: order.id.uuidString)
        guard let check = try AtelierKeychain.read(service: service, key: order.id.uuidString),
              try JSONDecoder().decode(AtelierOrder.self, from: check) == order else { throw AtelierHTTP.Failure.storage }
    }
}
@MainActor final class AtelierReceipt: NSObject, SKRequestDelegate {
    private var request: SKReceiptRefreshRequest?
    private var continuation: CheckedContinuation<Void, Error>?
    private var deadline: DispatchWorkItem?
    func refresh() async throws {
        guard request == nil else { return }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = SKReceiptRefreshRequest(); self.request = request; request.delegate = self
            let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(AtelierHTTP.Failure.invalidResponse)) }
            deadline = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
            request.start()
        }
    }
    nonisolated func requestDidFinish(_ request: SKRequest) { Task { @MainActor in
        guard self.request === request else { return }; self.finish(.success(()))
    } }
    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) { Task { @MainActor in
        guard self.request === request else { return }; self.finish(.failure(error))
    } }
    private func finish(_ result: Result<Void, Error>) {
        deadline?.cancel(); deadline = nil; request?.delegate = nil; request?.cancel(); request = nil
        let completion = continuation; continuation = nil; completion?.resume(with: result)
    }
}

@MainActor final class AtelierProductQuery {
    private var continuation: CheckedContinuation<[Product], Error>?
    private var request: Task<Void, Never>?
    private var deadline: DispatchWorkItem?
    func fetch(_ sku: String) async throws -> [Product] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion in
                continuation = completion
                let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(URLError(.timedOut))) }
                deadline = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
                request = Task {
                    do { self.finish(.success(try await Product.products(for: [sku]))) }
                    catch { self.finish(.failure(error)) }
                }
                if Task.isCancelled { finish(.failure(CancellationError())) }
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    private func finish(_ result: Result<[Product], Error>) {
        let completion = continuation; continuation = nil
        deadline?.cancel(); deadline = nil; request?.cancel(); request = nil
        completion?.resume(with: result)
    }
}
