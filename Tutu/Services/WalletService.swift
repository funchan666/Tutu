import Foundation
import Combine
@preconcurrency import StoreKit

struct CoinPack: Codable, Identifiable {
    let id: String
    let coins: Int
    let referenceUSD: String
    var total: Int { coins }
    static var all: [CoinPack] { Catalog.snapshot?.settings.packs ?? [] }
}
@MainActor final class WalletService: NSObject, ObservableObject, SKPaymentTransactionObserver {
    @Published private(set) var products: [String: SKProduct] = [:]
    @Published private(set) var purchasing: String?
    @Published private(set) var recovering = false
    @Published private(set) var status = ""
    @Published private(set) var paymentText = ""
    private var observing = false
    private var processing = Set<String>()
    private var activeOrder: UUID?
    private var submitted = false
    private var interactionAccount: String?
    private var retries: [String: Task<Void, Never>] = [:]
    private weak var store: AppStore?
    private let receipt = AtelierReceipt()

    func start(store: AppStore) {
        self.store = store
        guard !observing else { return }
        observing = true
        SKPaymentQueue.default().add(self)
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
        guard activeOrder == nil, let account = store.sessionID, let accountToken = UUID(uuidString: account) else { return }
        start(store: store)
        let id = UUID(), epoch = store.state?.walletInstance
        activeOrder = id; submitted = false; interactionAccount = account
        purchasing = sku; paymentText = "Preparing your purchase…"; status = ""
        do {
            let existing = try AtelierOrders.all()
            if let event, let order = event.purchase, existing.contains(where: { $0.mode == .ablyServer && $0.origin == IntegrationContract.baseURLString && ($0.orderCode == order.reference || $0.messageID == event.messageID) }) {
                endInteraction(id); await recover(store: store); return
            }
            guard SKPaymentQueue.canMakePayments() else { throw TutuFailure.message("Purchases are unavailable on this device.") }
            let available = try await AtelierProductQuery().fetch(sku)
            guard activeOrder == id, store.sessionID == account, store.state?.walletInstance == epoch, !Task.isCancelled else {
                endInteraction(id); return
            }
            guard let product = available.first(where: { $0.productIdentifier == sku }), product.subscriptionPeriod == nil else {
                throw TutuFailure.message("This pack isn't available from Apple right now. You haven't been charged.")
            }
            products[sku] = product
            if let pack, product.priceLocale.currencyCode == "USD", product.price.decimalValue != Decimal(string: pack.referenceUSD) {
                throw TutuFailure.message("This pack's Apple price doesn't match its listed US price. No purchase was started.")
            }
            var order = AtelierOrder(id: id, mode: event == nil ? .hostLocal : .ablyServer, productID: sku, accountID: account,
                accountToken: event == nil ? accountToken : id, walletInstance: epoch,
                bundleID: Bundle.main.bundleIdentifier ?? "", version: AtelierHTTP.version, device: try AtelierKeychain.deviceID(), created: Date(),
                coins: pack?.total, orderCode: event?.purchase?.reference, messageID: event?.messageID,
                origin: event == nil ? nil : IntegrationContract.baseURLString, path: event == nil ? nil : IntegrationContract.settlementPath,
                fields: event == nil ? nil : [ConfiguredWireFields.look_edition, ConfiguredWireFields.atelier_stamp, ConfiguredWireFields.apple_stitch, ConfiguredWireFields.receipt_fabric, ConfiguredWireFields.checkout_thread])
            order.paymentUsername = id.uuidString
            order.phase = .awaitingApple
            try AtelierOrders.save(order)
            let payment = SKMutablePayment(product: product)
            payment.applicationUsername = order.paymentUsername
            payment.quantity = 1
            submitted = true; paymentText = "Complete your purchase with Apple…"
            SKPaymentQueue.default().add(payment)
        } catch {
            if activeOrder == id {
                status = error.localizedDescription
                if store.sessionID == account, purchasing != nil { store.show("Purchase not completed", status) }
                endInteraction(id)
            }
        }
    }
    func sessionEnded() {
        purchasing = nil; paymentText = ""; interactionAccount = nil
        if !submitted, let id = activeOrder { endInteraction(id) }
    }
    private func endInteraction(_ id: UUID) {
        guard activeOrder == id else { return }
        purchasing = nil; paymentText = ""; activeOrder = nil; submitted = false; interactionAccount = nil
    }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            for transaction in transactions { await self.handle(transaction) }
        }
    }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool { false }

    func recover(store: AppStore) async {
        guard !recovering else { return }; recovering = true
        defer { recovering = false }
        do { _ = try AtelierOrders.all() }
        catch { status = error.localizedDescription; return }
        for transaction in SKPaymentQueue.default().transactions { await handle(transaction) }
    }
    private func handle(_ transaction: SKPaymentTransaction) async {
        switch transaction.transactionState {
        case .purchasing: break
        case .deferred:
            if let id = transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)), activeOrder == id {
                status = "Awaiting Apple approval. You have not been credited yet."
                if store?.sessionID == interactionAccount, purchasing != nil { store?.show("Awaiting Apple approval", status) }
                endInteraction(id)
            }
        case .failed:
            let id = transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:))
            do {
                if let id, var order = try AtelierOrders.all().first(where: { $0.id == id }), order.transactionID == nil,
                   order.phase == .awaitingApple || order.phase == .prepared {
                    order.phase = .cancelled; try AtelierOrders.save(order)
                }
            } catch { status = error.localizedDescription }
            SKPaymentQueue.default().finishTransaction(transaction)
            if let id, activeOrder == id {
                let cancelled = (transaction.error as? SKError)?.code == .paymentCancelled
                status = cancelled ? "Purchase cancelled. No coins were added." : (transaction.error?.localizedDescription ?? "Purchase not completed. Please try again.")
                if !cancelled, store?.sessionID == interactionAccount, purchasing != nil { store?.show("Purchase not completed", status) }
                endInteraction(id)
            }
        case .purchased, .restored: await process(transaction)
        @unknown default: break
        }
    }
    private func boundOrder(_ transaction: SKPaymentTransaction, orders: [AtelierOrder]) throws -> AtelierOrder? {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        let known = orders.filter { $0.bundleID == bundle && $0.transactionID != nil && $0.transactionID == transaction.transactionIdentifier }
        guard known.count <= 1 else { throw AtelierHTTP.Failure.invalidResponse }
        if let order = known.first { return order }
        guard let binding = transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)) else { return nil }
        let matched = orders.filter {
            $0.bundleID == bundle && $0.transactionID == nil &&
            ($0.paymentUsername.flatMap(UUID.init(uuidString:)) == binding ||
             ($0.paymentUsername == nil && $0.mode == .ablyServer && $0.accountToken == binding))
        }
        guard matched.count <= 1 else { throw AtelierHTTP.Failure.invalidResponse }
        return matched.first
    }
    private func process(_ transaction: SKPaymentTransaction) async {
        guard let transactionID = transaction.transactionIdentifier, !transactionID.isEmpty, let store else { return }
        let transactionKey = (Bundle.main.bundleIdentifier ?? "") + ":" + transactionID
        guard processing.insert(transactionKey).inserted else { return }
        var matchedID: UUID?
        var interactive = false
        defer {
            processing.remove(transactionKey)
            if let id = matchedID { endInteraction(id) }
        }
        do {
            let orders = try AtelierOrders.all()
            var candidate = try boundOrder(transaction, orders: orders)
            if candidate == nil, transaction.transactionState == .purchased,
               let binding = transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)),
               let account = store.sessionID, UUID(uuidString: account) == binding,
               store.state?.creditedTransactions.contains(transactionID) == true,
               let grant = store.state?.transactionGrants?[transactionID] {
                var migrated = AtelierOrder(id: UUID(), mode: .hostLocal, productID: transaction.payment.productIdentifier, accountID: account,
                    accountToken: binding, walletInstance: store.state?.walletInstance, bundleID: Bundle.main.bundleIdentifier ?? "",
                    version: AtelierHTTP.version, device: try AtelierKeychain.deviceID(), created: transaction.transactionDate ?? Date(),
                    coins: grant, orderCode: nil, messageID: nil, origin: nil, path: nil, fields: nil)
                migrated.transactionID = transactionID; migrated.phase = .localDelivered
                try AtelierOrders.save(migrated); candidate = migrated
            }
            guard var order = candidate else {
                throw TutuFailure.message("A pending purchase needs its original order association. It has been kept for review.")
            }
            matchedID = order.id
            interactive = activeOrder == order.id && purchasing != nil && store.sessionID == interactionAccount
            guard order.productID == transaction.payment.productIdentifier,
                  order.bundleID == Bundle.main.bundleIdentifier,
                  order.transactionID == nil || order.transactionID == transactionID else { throw AtelierHTTP.Failure.invalidResponse }
            if let binding = transaction.payment.applicationUsername {
                let expected = order.paymentUsername.flatMap(UUID.init(uuidString:)) ?? order.accountToken
                guard UUID(uuidString: binding) == expected else { throw AtelierHTTP.Failure.invalidResponse }
            }
            if isDelivered(order) {
                try finish(transaction, order: &order)
                retries.removeValue(forKey: transactionKey)?.cancel()
                return
            }
            guard transaction.transactionState == .purchased else {
                throw TutuFailure.message("This restored purchase needs review. No coins were added.")
            }
            if order.transactionID == nil {
                order.transactionID = transactionID; order.phase = .paid
                try AtelierOrders.save(order)
            }
            if interactive { paymentText = order.mode == .hostLocal ? "Saving your coins…" : "Confirming your purchase…" }
            let verified = try await receipt.verified(transactionID: transactionID, productID: order.productID,
                quantity: transaction.payment.quantity, allowRefresh: interactive)
            guard order.environment == nil || order.environment?.lowercased() == verified.environment.lowercased() else {
                throw AtelierHTTP.Failure.invalidResponse
            }
            order.environment = verified.environment; try AtelierOrders.save(order)
            if verified.purchase.cancellationDate != nil {
                guard order.mode == .hostLocal, store.sessionID == order.accountID,
                      store.state?.walletInstance == order.walletInstance else { throw TutuFailure.message("A refunded purchase needs review.") }
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
            } else {
                switch order.mode {
                case .hostLocal:
                    let quantity = verified.purchase.quantity
                    guard store.sessionID == order.accountID, let epoch = order.walletInstance, store.state?.walletInstance == epoch,
                          let coins = order.coins, coins > 0, quantity > 0, coins <= Int.max / quantity else {
                        throw TutuFailure.message("Sign in to the original wallet to review this pending purchase.")
                    }
                    let grant = coins * quantity
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
                    let values = [order.version, order.device, transactionID, verified.data.base64EncodedString(), reference]
                    let body = Dictionary(uniqueKeysWithValues: zip(fields, values))
                    let (data, response) = try await AtelierHTTP.response(path: path, body: body, origin: origin)
                    guard (200..<300).contains(response.statusCode), AtelierHTTP.zero(try AtelierHTTP.object(data)["code"]) else { throw AtelierHTTP.Failure.invalidResponse }
                    order.phase = .serverConfirmed; try AtelierOrders.save(order)
                }
            }
            try finish(transaction, order: &order)
            retries.removeValue(forKey: transactionKey)?.cancel()
            if interactive, activeOrder == order.id, purchasing != nil, store.sessionID == order.accountID {
                store.show("Purchase complete", order.mode == .hostLocal ? "Your coins have been saved to your wallet." : "Your purchase has been confirmed.")
            }
        } catch {
            status = error.localizedDescription
            if interactive, purchasing != nil, store.sessionID == interactionAccount {
                store.show("Purchase pending", "Purchased; confirmation is pending. Please do not buy again.")
            }
            if matchedID == nil, let id = transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)), activeOrder == id {
                endInteraction(id)
            }
            if retries[transactionKey] == nil {
                retries[transactionKey] = Task { [weak self] in
                    for delay in [4, 12, 30] {
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        guard let self, !Task.isCancelled else { return }
                        await self.process(transaction)
                    }
                    self?.retries[transactionKey] = nil
                }
            }
        }
    }
    private func isDelivered(_ order: AtelierOrder) -> Bool {
        (order.mode == .hostLocal && order.phase == .localDelivered) || (order.mode == .ablyServer && order.phase == .serverConfirmed)
    }
    private func finish(_ transaction: SKPaymentTransaction, order: inout AtelierOrder) throws {
        guard isDelivered(order) else { throw AtelierHTTP.Failure.storage }
        let saved = try AtelierOrders.all().first { $0.id == order.id }
        guard saved == order else { throw AtelierHTTP.Failure.storage }
        SKPaymentQueue.default().finishTransaction(transaction)
        order.finished = true; try AtelierOrders.save(order)
    }
    deinit { retries.values.forEach { $0.cancel() } }
}
