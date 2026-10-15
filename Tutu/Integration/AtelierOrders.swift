import Foundation
@preconcurrency import StoreKit
import TPInAppReceipt

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
    var paymentUsername: String? = nil
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
    private var completions: [CheckedContinuation<Void, Error>] = []
    private var deadline: DispatchWorkItem?
    func refresh() async throws {
        try await withCheckedThrowingContinuation { completion in
            completions.append(completion)
            guard request == nil else { return }
            let request = SKReceiptRefreshRequest(); self.request = request; request.delegate = self
            let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(URLError(.timedOut))) }
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
        let pending = completions; completions.removeAll(); pending.forEach { $0.resume(with: result) }
    }
    struct Verified {
        let data: Data
        let environment: String
        let purchase: InAppPurchase
    }
    func verified(transactionID: String, productID: String, quantity: Int, canRefresh: () -> Bool) async throws -> Verified {
        do { return try await validate(transactionID: transactionID, productID: productID, quantity: quantity) }
        catch {
            guard canRefresh() else { throw error }
            try await refresh()
            return try await validate(transactionID: transactionID, productID: productID, quantity: quantity)
        }
    }
    func refundedPurchases() async throws -> [Verified] {
        let (data, environment, receipt) = try await validatedReceipt()
        return receipt.purchases.filter { $0.cancellationDate != nil }.map {
            Verified(data: data, environment: environment, purchase: $0)
        }
    }
    private func validatedReceipt() async throws -> (Data, String, AppReceipt) {
        guard let url = Bundle.main.appStoreReceiptURL, let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw TutuFailure.message("Purchased; confirmation is pending. Please do not buy again.")
        }
        let receipt = try AppReceipt.receipt(from: data)
        guard receipt.hasValidStructure else { throw AtelierHTTP.Failure.invalidResponse }
        let environment: String
        switch receipt.environment {
        case .production: environment = "Production"
        case .sandbox, .productionSandbox: environment = "Sandbox"
        default: throw TutuFailure.message("An App Store receipt is required to confirm this purchase.")
        }
        guard case .valid = await receipt.validate(), receipt.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw TutuFailure.message("Apple couldn't verify a purchase. No coins were added.")
        }
        return (data, environment, receipt)
    }
    private func validate(transactionID: String, productID: String, quantity: Int) async throws -> Verified {
        let (data, environment, receipt) = try await validatedReceipt()
        let matches = receipt.purchases.filter { $0.transactionIdentifier == transactionID }
        guard matches.count == 1, let purchase = matches.first,
              purchase.productIdentifier == productID, purchase.quantity == quantity, quantity > 0,
              purchase.productType == .consumable || purchase.productType == .unknown,
              purchase.subscriptionExpirationDate == nil else { throw AtelierHTTP.Failure.invalidResponse }
        return Verified(data: data, environment: environment, purchase: purchase)
    }
}

@MainActor final class AtelierProductQuery: NSObject, SKProductsRequestDelegate {
    private var continuation: CheckedContinuation<[SKProduct], Error>?
    private var request: SKProductsRequest?
    private var deadline: DispatchWorkItem?
    func fetch(_ sku: String) async throws -> [SKProduct] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion in
                continuation = completion
                let request = SKProductsRequest(productIdentifiers: [sku]); self.request = request; request.delegate = self
                let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(URLError(.timedOut))) }
                deadline = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
                if Task.isCancelled { finish(.failure(CancellationError())) } else { request.start() }
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) { Task { @MainActor in
        guard self.request === request else { return }; self.finish(.success(response.products))
    } }
    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) { Task { @MainActor in
        guard self.request === request else { return }; self.finish(.failure(error))
    } }
    private func finish(_ result: Result<[SKProduct], Error>) {
        let completion = continuation; continuation = nil
        deadline?.cancel(); deadline = nil; request?.delegate = nil; request?.cancel(); request = nil
        completion?.resume(with: result)
    }
}

extension SKProduct {
    var displayPrice: String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.locale = priceLocale
        return formatter.string(from: price) ?? price.stringValue
    }
}
