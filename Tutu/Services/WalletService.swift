import Foundation
import Combine
import StoreKit

struct CoinPack: Identifiable {
    let id: String
    let coins: Int
    let bonus: Int
    let referenceUSD: String
    var total: Int { coins + bonus }
    var bonusPercent: Int { coins == 0 ? 0 : bonus * 100 / coins }
    static let all: [CoinPack] = [
        .init(id: "com.tutu.style.coins.100", coins: 100, bonus: 0, referenceUSD: "0.99"),
        .init(id: "com.tutu.style.coins.500", coins: 500, bonus: 25, referenceUSD: "4.99"),
        .init(id: "com.tutu.style.coins.1000", coins: 1000, bonus: 100, referenceUSD: "9.99"),
        .init(id: "com.tutu.style.coins.2000", coins: 2000, bonus: 300, referenceUSD: "19.99"),
        .init(id: "com.tutu.style.coins.5000", coins: 5000, bonus: 1000, referenceUSD: "49.99"),
        .init(id: "com.tutu.style.coins.10000", coins: 10000, bonus: 2500, referenceUSD: "99.99"),
        .init(id: "com.tutu.style.coins.1500", coins: 1500, bonus: 150, referenceUSD: "14.99"),
        .init(id: "com.tutu.style.coins.3000", coins: 3000, bonus: 450, referenceUSD: "29.99")
    ]
}
@MainActor final class WalletService: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var loading = false
    @Published private(set) var purchasing: String?
    @Published private(set) var status = ""
    private var listener: Task<Void, Never>?
    // Enable only after real account settlement and gift delivery are integrated.
    // This prevents charging for gifts that cannot currently be delivered.
    private let commerceReady = false
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
    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let list = try await Product.products(for: CoinPack.all.map(\.id))
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            status = list.isEmpty ? "Coin packs are currently unavailable. Please try again later." : ""
        } catch { status = "Couldn't load prices. Check your connection and try again." }
    }
    func purchase(_ pack: CoinPack, store: AppStore) async {
        guard purchasing == nil else { return }
        guard commerceReady else { store.show("Purchases unavailable", "Coin purchases are temporarily unavailable. You haven't been charged. Please try again later."); return }
        guard let product = products[pack.id], let id = store.sessionID, let token = UUID(uuidString: id) else { store.show("Price unavailable", "Refresh the coin packs and try again."); return }
        purchasing = pack.id; defer { purchasing = nil }
        do {
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let verification): await process(verification, store: store)
            case .pending: store.show("Awaiting approval", "Your purchase is pending. Coins will arrive after Apple approves and verifies it.")
            case .userCancelled: break
            @unknown default: store.show("Purchase not completed", "Please try again later.")
            }
        } catch { store.show("Purchase not completed", "The purchase couldn't be completed. Please try again.") }
    }
    func recover(store: AppStore) async {
        guard store.sessionID != nil else { return }
        for await result in Transaction.unfinished { await process(result, store: store) }
    }
    private func process(_ result: VerificationResult<Transaction>, store: AppStore) async {
        guard case .verified(let transaction) = result else { status = "A purchase could not be verified. No coins were added."; return }
        guard let pack = CoinPack.all.first(where: { $0.id == transaction.productID }), let account = store.sessionID,
              transaction.appAccountToken?.uuidString.lowercased() == account.lowercased() else { return }
        let key = String(transaction.id)
        if transaction.revocationDate != nil {
            if store.state?.revokedTransactions.contains(key) == true { await transaction.finish(); return }
            if store.commit({ s in
                if s.creditedTransactions.contains(key) { let reversed = min(s.coins, pack.total); s.coins -= reversed; s.ledger.insert(WalletEntry(title: "Purchase refunded", amount: -reversed), at: 0) }
                s.revokedTransactions.insert(key)
            }) { await transaction.finish() }
            return
        }
        if store.state?.creditedTransactions.contains(key) == true { await transaction.finish(); return }
        // Persist the grant and transaction ID together before finishing with Apple.
        if store.commit({ s in s.coins += pack.total; s.creditedTransactions.insert(key); s.ledger.insert(WalletEntry(title: "\(pack.total) coins", amount: pack.total), at: 0) }) { await transaction.finish() }
    }
    deinit { listener?.cancel() }
}
