import Foundation
import Combine
import StoreKit

struct CoinPack: Identifiable {
    let id: String
    let coins: Int
    let referenceUSD: String
    var total: Int { coins }
    static let all: [CoinPack] = [
        .init(id: "izfxfjwpsvwjonwq", coins: 450, referenceUSD: "0.99"),
        .init(id: "qoohvxhjfzgwnzsv", coins: 950, referenceUSD: "1.99"),
        .init(id: "mvnosjxwqeapluwc", coins: 2600, referenceUSD: "4.99"),
        .init(id: "gogeyhnqocosotoj", coins: 5500, referenceUSD: "9.99"),
        .init(id: "gkduqkyagqmdczvp", coins: 12000, referenceUSD: "19.99"),
        .init(id: "hnqvktmrcxpslwad", coins: 19000, referenceUSD: "29.99"),
        .init(id: "wvioqagpchpyenva", coins: 33000, referenceUSD: "49.99"),
        .init(id: "zbrynfqjvctmksae", coins: 48000, referenceUSD: "69.99"),
        .init(id: "gmmdvhzpaszwhajc", coins: 72000, referenceUSD: "99.99")
    ]
}
@MainActor final class WalletService: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var purchasing: String?
    @Published private(set) var recovering = false
    @Published private(set) var status = ""
    private var listener: Task<Void, Never>?
    func start(store: AppStore) {
        guard listener == nil else { return }
        listener = Task { [weak self, weak store] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self, let store else { return }
                await self.process(result, store: store)
            }
        }
        Task { await recover(store: store) }
    }
    func purchase(_ pack: CoinPack, store: AppStore) async {
        guard purchasing == nil else { return }
        guard let account = store.sessionID, let token = UUID(uuidString: account) else { return }
        purchasing = pack.id; status = ""; defer { purchasing = nil }
        do {
            // Deliberately fetch this single product only after a purchase tap.
            // Never fetch or preload the catalog on page entry, app launch, or recovery.
            let products = try await Product.products(for: [pack.id])
            guard store.sessionID == account else { return }
            guard let product = products.first(where: { $0.id == pack.id }), product.type == .consumable else {
                store.show("Pack unavailable", "This pack isn't available from Apple right now. You haven't been charged. Please try again later."); return
            }
            self.products[pack.id] = product
            // The supplied USD price is immutable. Other storefronts use Apple's local price.
            if product.priceFormatStyle.currencyCode == "USD", product.price != Decimal(string: pack.referenceUSD) {
                store.show("Price needs updating", "This pack's Apple price doesn't match its listed US price. No purchase was started."); return
            }
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result): await process(result, store: store)
            case .pending:
                if store.sessionID == account { store.show("Awaiting Apple approval", "Your purchase is pending. Coins will be added only after Apple verifies it.") }
            case .userCancelled: status = "Purchase cancelled. No coins were added."
            @unknown default: status = "Purchase not completed. Please try again."
            }
        } catch {
            if store.sessionID == account { store.show("Purchase not completed", "Apple couldn't complete this purchase. If payment already went through, use Check pending purchases to recover it. You won't be credited twice.") }
        }
    }
    func recover(store: AppStore) async {
        // A session change may start a second pass; processing is idempotent before its first await.
        guard store.sessionID != nil else { return }
        recovering = true; defer { recovering = false }
        for await result in Transaction.unfinished { await process(result, store: store) }
    }
    private func process(_ result: VerificationResult<Transaction>, store: AppStore) async {
        guard case .verified(let transaction) = result else { status = "Apple couldn't verify a purchase. No coins were added."; return }
        guard transaction.productType == .consumable,
              let pack = CoinPack.all.first(where: { $0.id == transaction.productID }), let account = store.sessionID,
              transaction.appAccountToken?.uuidString.lowercased() == account.lowercased() else {
            status = "A pending purchase belongs to another account. Sign in to the account used for that purchase."; return
        }
        let key = String(transaction.id)
        if transaction.revocationDate != nil {
            if store.state?.revokedTransactions.contains(key) == true { await transaction.finish(); return }
            if store.commit({ s in
                if s.creditedTransactions.contains(key) {
                    let grant = s.transactionGrants?[key] ?? pack.total
                    let reversed = min(s.coins, grant)
                    s.coins -= reversed; s.refundDebt = (s.refundDebt ?? 0) + grant - reversed
                    s.ledger.insert(WalletEntry(title: "Purchase refunded", amount: -reversed), at: 0)
                }
                s.revokedTransactions.insert(key)
            }) { await transaction.finish() }
            return
        }
        guard store.state?.revokedTransactions.contains(key) != true else { await transaction.finish(); return }
        if store.state?.creditedTransactions.contains(key) == true { await transaction.finish(); return }
        let grant = pack.total * transaction.purchasedQuantity
        // Persist the credit, its exact quantity, and transaction ID together before finish().
        if store.commit({ s in
            s.creditCoins(grant, title: "Apple purchase · \(grant) coins")
            s.creditedTransactions.insert(key)
            var grants = s.transactionGrants ?? [:]; grants[key] = grant; s.transactionGrants = grants
        }) {
            await transaction.finish()
            if store.sessionID == account { store.show("Your coins have arrived", "\(grant) coins added. Your balance is \(store.state?.coins ?? 0).") }
        } else { status = "Payment verified, but the coins couldn't be saved. Check pending purchases to retry." }
    }
    deinit { listener?.cancel() }
}
