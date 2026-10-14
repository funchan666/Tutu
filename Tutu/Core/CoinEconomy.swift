import SwiftUI

enum CoinEconomy {
    static let welcomeCoins = 360
    static let runwayFrame = "runway-ribbon"
    static let runwayPrice = 240
}
struct CoinSpend: Identifiable {
    enum Item { case gift(Gift, Int), runwayFrame }
    let id = UUID()
    let accountID: String
    let item: Item
    var amount: Int { switch item { case .gift(let gift, let quantity): return gift.price * quantity; case .runwayFrame: return CoinEconomy.runwayPrice } }
    var title: String { switch item { case .gift(let gift, let quantity): return "\(gift.name) × \(quantity)"; case .runwayFrame: return "Runway Ribbon" } }
    var artwork: String { switch item { case .gift(let gift, _): return gift.image; case .runwayFrame: return "runway-frame" } }
    var detail: String { switch item { case .gift: return "Add to your collection and wear it as your profile charm. Sending to another member is currently unavailable."; case .runwayFrame: return "Unlock this original avatar frame once. Wear it whenever you like." } }
}
extension ProfileState {
    mutating func creditCoins(_ amount: Int, title: String) {
        guard amount > 0 else { return }
        let debtPayment = min(amount, refundDebt ?? 0)
        refundDebt = max(0, (refundDebt ?? 0) - debtPayment)
        coins += amount - debtPayment
        ledger.insert(WalletEntry(title: title, amount: amount), at: 0)
        if debtPayment > 0 { ledger.insert(WalletEntry(title: "Refund balance adjustment", amount: -debtPayment), at: 0) }
    }
}
@MainActor extension AppStore {
    func arriveHome() {
        guard me.birthday != nil, let current = state, current.welcomeEligible == true else { return }
        if current.welcomeGranted != true {
            guard commit({ s in
                guard s.welcomeGranted != true else { return }
                s.creditCoins(CoinEconomy.welcomeCoins, title: "Your first style drop")
                s.welcomeGranted = true
                s.welcomeSeen = false
            }) else { return }
        }
        if state?.welcomeSeen != true { welcomeVisible = true }
    }
    func finishWelcome() {
        if commit({ $0.welcomeSeen = true }) { welcomeVisible = false }
    }
    func requestCoins(for item: CoinSpend.Item) {
        guard let id = sessionID else { return }
        if case .gift(_, let quantity) = item, !(1...99).contains(quantity) { return }
        if case .runwayFrame = item, state?.ownedCosmetics?.contains(CoinEconomy.runwayFrame) == true { return }
        let prompt = CoinSpend(accountID: id, item: item)
        guard (state?.coins ?? 0) >= prompt.amount else {
            coinPrompt = nil
            walletRequest += 1
            show("A few more coins", "\(prompt.title) costs \(prompt.amount) coins. You need \(prompt.amount - (state?.coins ?? 0)) more. Choose a pack in Get Coins; nothing has been deducted.")
            return
        }
        coinPrompt = prompt
    }
    func confirmCoinSpend() {
        guard let prompt = coinPrompt, prompt.accountID == sessionID else { coinPrompt = nil; return }
        coinPrompt = nil
        guard (state?.coins ?? 0) >= prompt.amount else { requestCoins(for: prompt.item); return }
        let success = commit { s in
            guard s.person.id == prompt.accountID, s.coins >= prompt.amount else { throw TutuFailure.message("Your balance changed. Please try again.") }
            switch prompt.item {
            case .gift(let gift, let quantity): s.inventory[gift.id, default: 0] += quantity
            case .runwayFrame:
                guard !(s.ownedCosmetics ?? []).contains(CoinEconomy.runwayFrame) else { throw TutuFailure.message("You already own this frame.") }
                var owned = s.ownedCosmetics ?? []; owned.insert(CoinEconomy.runwayFrame); s.ownedCosmetics = owned
                s.equippedFrame = CoinEconomy.runwayFrame
            }
            s.coins -= prompt.amount
            s.ledger.insert(WalletEntry(title: prompt.title, amount: -prompt.amount), at: 0)
        }
        if success { show("Made for your style", "\(prompt.title) is yours. \(prompt.amount) coins used · \(state?.coins ?? 0) coins remaining.") }
    }
}
