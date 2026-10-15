import Foundation
import Combine
import StoreKit

struct CoinPack: Codable, Identifiable {
    let id: String
    let coins: Int
    let referenceUSD: String
    var total: Int { coins }
    static var all: [CoinPack] { Catalog.snapshot?.settings.packs ?? [] }
}
@MainActor final class WalletService: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var purchasing: String?
    @Published private(set) var recovering = false
    @Published private(set) var status = ""
    @Published private(set) var paymentText = ""
    private var listener: Task<Void, Never>?
    private var processing = Set<String>()
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var activeOrder: UUID?
    private var purchaseLocked = false
    private var interactionAccount: String?
    private var retries: [String: Task<Void, Never>] = [:]
    private weak var store: AppStore?
    private let receipt = AtelierReceipt()

    func start(store: AppStore) {
        self.store = store
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                await self.process(result)
            }
        }
        Task { await recover(store: store) }
    }
    func purchase(_ pack: CoinPack, store: AppStore) async {
        await buy(sku: pack.id, pack: pack, event: nil, store: store)
    }
    func purchase(event: ConfiguredCoreEvent, store: AppStore) async {
        guard let order = event.purchase else { return }
        await buy(sku: order.sku, pack: nil, event: event, store: store)
    }
    private func buy(sku: String, pack: CoinPack?, event: ConfiguredCoreEvent?, store: AppStore) async {
        guard !purchaseLocked, let account = store.sessionID, let accountToken = UUID(uuidString: account) else { return }
        purchaseLocked = true; interactionAccount = account
        purchasing = sku; paymentText = "Preparing your purchase…"; status = ""
        defer { purchasing = nil; paymentText = ""; activeOrder = nil; purchaseLocked = false; interactionAccount = nil }
        do {
            let existing = try AtelierOrders.all()
            if let event, let order = event.purchase, existing.contains(where: { $0.mode == .ablyServer && $0.origin == IntegrationContract.baseURLString && ($0.orderCode == order.reference || $0.messageID == event.messageID) }) {
                await recover(store: store); return
            }
            guard SKPaymentQueue.canMakePayments() else { throw TutuFailure.message("Purchases are unavailable on this device.") }
            let products = try await AtelierProductQuery().fetch(sku)
            guard store.sessionID == account else { return }
            guard let product = products.first(where: { $0.id == sku }), product.type == .consumable else { throw TutuFailure.message("This pack isn't available from Apple right now. You haven't been charged.") }
            self.products[sku] = product
            if let pack, product.priceFormatStyle.currencyCode == "USD", product.price != Decimal(string: pack.referenceUSD) {
                throw TutuFailure.message("This pack's Apple price doesn't match its listed US price. No purchase was started.")
            }
            let id = UUID()
            var order = AtelierOrder(id: id, mode: event == nil ? .hostLocal : .ablyServer, productID: sku, accountID: account,
                accountToken: event == nil ? accountToken : id, walletInstance: store.state?.walletInstance,
                bundleID: Bundle.main.bundleIdentifier ?? "", version: AtelierHTTP.version, device: try AtelierKeychain.deviceID(), created: Date(),
                coins: pack?.total, orderCode: event?.purchase?.reference, messageID: event?.messageID,
                origin: event == nil ? nil : IntegrationContract.baseURLString, path: event == nil ? nil : IntegrationContract.settlementPath,
                fields: event == nil ? nil : [ConfiguredWireFields.look_edition, ConfiguredWireFields.atelier_stamp, ConfiguredWireFields.apple_stitch, ConfiguredWireFields.receipt_fabric, ConfiguredWireFields.checkout_thread])
            order.phase = .awaitingApple
            try AtelierOrders.save(order); activeOrder = id
            paymentText = "Complete your purchase with Apple…"
            switch try await product.purchase(options: [.appAccountToken(order.accountToken)]) {
            case .success(let result):
                paymentText = event == nil ? "Saving your coins…" : "Confirming your purchase…"
                await process(result, directOrder: id, interactive: true)
            case .pending:
                status = "Awaiting Apple approval. You have not been credited yet."
                if store.sessionID == account, purchasing != nil { store.show("Awaiting Apple approval", status) }
            case .userCancelled:
                order.phase = .cancelled; try AtelierOrders.save(order); status = "Purchase cancelled. No coins were added."
            @unknown default: status = "Purchase not completed. Please try again."
            }
        } catch {
            status = error.localizedDescription
            if store.sessionID == account, purchasing != nil { store.show("Purchase not completed", status) }
        }
    }
    func sessionEnded() { purchasing = nil; paymentText = "" }
    func recover(store: AppStore) async {
        guard !recovering else { return }; recovering = true
        defer { recovering = false }
        do { _ = try AtelierOrders.all() }
        catch { status = error.localizedDescription; return }
        for await result in Transaction.unfinished { await process(result) }
    }
    private func process(_ result: VerificationResult<Transaction>, directOrder: UUID? = nil, interactive: Bool = false) async {
        guard case .verified(let transaction) = result else { status = "Apple couldn't verify a purchase. No coins were added."; return }
        let transactionKey = transaction.appBundleID + ":" + String(describing: transaction.environment) + ":" + String(transaction.id)
        if processing.contains(transactionKey) {
            await withCheckedContinuation { waiters[transactionKey, default: []].append($0) }
            if interactive { await process(result, directOrder: directOrder, interactive: true) }
            return
        }
        guard let store else { return }
        processing.insert(transactionKey)
        defer {
            processing.remove(transactionKey)
            let pending = waiters.removeValue(forKey: transactionKey) ?? []
            pending.forEach { $0.resume() }
        }
        do {
            var orders = try AtelierOrders.all()
            let transactionID = String(transaction.id)
            let environment = String(describing: transaction.environment)
            let known = orders.filter { $0.transactionID == transactionID && $0.bundleID == transaction.appBundleID && $0.environment == environment }
            guard known.count <= 1 else { throw TutuFailure.message("This purchase needs review. No extra coins were added.") }
            if let directOrder, let knownOrder = known.first, knownOrder.id != directOrder { throw AtelierHTTP.Failure.invalidResponse }
            var candidate = known.first
            if candidate == nil, let directOrder { candidate = orders.first { $0.id == directOrder } }
            if candidate == nil {
                candidate = orders.first { $0.mode == .ablyServer && $0.id == transaction.appAccountToken && $0.transactionID == nil }
            }
            if candidate == nil, let account = store.sessionID, transaction.appAccountToken?.uuidString.lowercased() == account.lowercased(),
               store.state?.creditedTransactions.contains(transactionID) == true,
               let grant = store.state?.transactionGrants?[transactionID] {
                var migrated = AtelierOrder(id: UUID(), mode: .hostLocal, productID: transaction.productID, accountID: account,
                    accountToken: transaction.appAccountToken!, walletInstance: store.state?.walletInstance, bundleID: transaction.appBundleID,
                    version: AtelierHTTP.version, device: try AtelierKeychain.deviceID(), created: transaction.purchaseDate,
                    coins: grant, orderCode: nil, messageID: nil, origin: nil, path: nil, fields: nil)
                migrated.transactionID = transactionID; migrated.environment = environment; migrated.phase = .localDelivered
                try AtelierOrders.save(migrated); candidate = migrated; orders.append(migrated)
            }
            guard var order = candidate else {
                status = "A pending purchase needs its original order association. It has been kept for review."; return
            }
            guard order.productID == transaction.productID, order.bundleID == transaction.appBundleID,
                  order.accountToken == transaction.appAccountToken,
                  order.transactionID == nil || order.transactionID == transactionID,
                  order.environment == nil || order.environment == environment,
                  transaction.productType == .consumable else { throw TutuFailure.message("This purchase needs review. Its original order has been kept.") }
            if order.transactionID == nil {
                order.transactionID = transactionID; order.environment = environment; order.phase = .paid
                try AtelierOrders.save(order)
            }
            if transaction.revocationDate != nil {
                guard order.mode == .hostLocal, store.sessionID == order.accountID,
                      store.state?.walletInstance == order.walletInstance else { status = "A refunded purchase needs review."; return }
                guard store.commit({ value in
                    guard !value.revokedTransactions.contains(transactionID) else { return }
                    if let grant = value.transactionGrants?[transactionID], value.creditedTransactions.contains(transactionID) {
                        let reversed = min(value.coins, grant)
                        value.coins -= reversed; value.refundDebt = (value.refundDebt ?? 0) + grant - reversed
                        value.ledger.insert(WalletEntry(title: "Purchase refunded", amount: -reversed, kind: .refund), at: 0)
                    }
                    value.revokedTransactions.insert(transactionID)
                }) else { throw AtelierHTTP.Failure.storage }
                order.phase = .localDelivered; try AtelierOrders.save(order)
            }
            if order.phase != .localDelivered && order.phase != .serverConfirmed {
                switch order.mode {
                case .hostLocal:
                    guard store.sessionID == order.accountID, let epoch = order.walletInstance, store.state?.walletInstance == epoch,
                          let coins = order.coins, coins > 0, transaction.purchasedQuantity > 0,
                          coins <= Int.max / transaction.purchasedQuantity else {
                        status = "Sign in to the original wallet to review this pending purchase."; return
                    }
                    let grant = coins * transaction.purchasedQuantity
                    guard store.commit({ value in
                        if !value.creditedTransactions.contains(transactionID), !value.revokedTransactions.contains(transactionID) {
                            value.creditCoins(grant, title: "Apple purchase · \(grant) coins")
                            value.creditedTransactions.insert(transactionID)
                            var grants = value.transactionGrants ?? [:]; grants[transactionID] = grant; value.transactionGrants = grants
                        }
                    }) else { throw AtelierHTTP.Failure.storage }
                    order.phase = .localDelivered; try AtelierOrders.save(order)
                case .ablyServer:
                    guard let path = order.path, let origin = order.origin, let fields = order.fields, fields.count == 5,
                          let reference = order.orderCode else { throw AtelierHTTP.Failure.invalidResponse }
                    if interactive && receiptBytes() == nil { try await receipt.refresh() }
                    guard let receiptData = receiptBytes() else { throw TutuFailure.message("Purchased; confirmation is pending. Please do not buy again.") }
                    let values = [order.version, order.device, transactionID, receiptData.base64EncodedString(), reference]
                    let body = Dictionary(uniqueKeysWithValues: zip(fields, values))
                    let (data, response) = try await AtelierHTTP.response(path: path, body: body, origin: origin)
                    guard (200..<300).contains(response.statusCode), AtelierHTTP.zero(try AtelierHTTP.object(data)["code"]) else { throw AtelierHTTP.Failure.invalidResponse }
                    order.phase = .serverConfirmed; try AtelierOrders.save(order)
                }
            }
            guard (order.mode == .hostLocal && order.phase == .localDelivered) || (order.mode == .ablyServer && order.phase == .serverConfirmed) else { return }
            await transaction.finish()
            order.finished = true; try AtelierOrders.save(order)
            retries.removeValue(forKey: transactionKey)?.cancel()
            if interactive, purchasing != nil, store.sessionID == order.accountID { store.show("Purchase complete", order.mode == .hostLocal ? "Your coins have been saved to your wallet." : "Your purchase has been confirmed.") }
        } catch {
            status = "Purchased; confirmation is pending. Please do not buy again."
            if interactive, purchasing != nil, store.sessionID == interactionAccount { store.show("Purchase pending", status) }
            if retries[transactionKey] == nil {
                retries[transactionKey] = Task { [weak self] in
                    for delay in [4, 12, 30] {
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        guard let self, !Task.isCancelled else { return }
                        await self.process(result)
                    }
                    self?.retries[transactionKey] = nil
                }
            }
        }
    }
    private func receiptBytes() -> Data? {
        guard let url = Bundle.main.appStoreReceiptURL, let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }
    deinit { listener?.cancel(); retries.values.forEach { $0.cancel() } }
}
