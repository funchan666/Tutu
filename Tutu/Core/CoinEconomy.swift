import SwiftUI

enum CoinEconomy {
    static let welcomeCoins = 360
    static let stylistFreeReplies = 5
    static let stylistReplyPrice = 20
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
    var detail: String { switch item { case .gift: return "Add to your collection, wear it as a profile charm, or reuse its room effect on this device. Sending to another member is currently unavailable."; case .runwayFrame: return "Unlock this original avatar frame once. Wear it whenever you like." } }
}
extension ProfileState {
    mutating func creditCoins(_ amount: Int, title: String) {
        guard amount > 0 else { return }
        let debtPayment = min(amount, refundDebt ?? 0)
        refundDebt = max(0, (refundDebt ?? 0) - debtPayment)
        coins += amount - debtPayment
        ledger.insert(WalletEntry(title: title, amount: amount, kind: .credit), at: 0)
        if debtPayment > 0 { ledger.insert(WalletEntry(title: "Refund balance adjustment", amount: -debtPayment, kind: .refund), at: 0) }
    }
}
@MainActor extension AppStore {
    func arriveHome() {
        guard let current = state, current.welcomeEligible == true else { return }
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
            s.ledger.insert(WalletEntry(title: prompt.title, amount: -prompt.amount, kind: .spending), at: 0)
        }
        if success { show("Made for your style", "\(prompt.title) is yours. \(prompt.amount) coins used · \(state?.coins ?? 0) coins remaining.") }
    }
}

enum StarRankingPeriod: String, CaseIterable {
    case daily = "Daily", weekly = "Weekly", allTime = "All time"
    func includes(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard date <= now else { return false }
        switch self {
        case .daily: return calendar.dateInterval(of: .day, for: now)?.contains(date) == true
        case .weekly: return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true
        case .allTime: return true
        }
    }
}
struct StarRankingEntry: Identifiable {
    let personID: String
    let coins: Int
    var id: String { personID }
}
enum StarRankings {
    // Fixed local presentation data, separate from every account's actual wallet ledger.
    private static let featured = [
        (id: "mia", daily: 2860, weekly: 18400, total: 86400),
        (id: "lily", daily: 2240, weekly: 21600, total: 72800),
        (id: "ella", daily: 1980, weekly: 12960, total: 96400),
        (id: "ava", daily: 1640, weekly: 14800, total: 64200),
        (id: "noah", daily: 1280, weekly: 9840, total: 53200),
        (id: "leo", daily: 960, weekly: 11200, total: 48600),
        (id: "film-01", daily: 720, weekly: 7680, total: 35800),
        (id: "film-02", daily: 580, weekly: 6240, total: 42400),
        (id: "film-04", daily: 400, weekly: 4960, total: 28600),
        (id: "film-07", daily: 240, weekly: 3280, total: 19400)
    ]
    static func ownCoins(in state: ProfileState?, period: StarRankingPeriod, now: Date) -> Int {
        (state?.ledger ?? []).filter { period.includes($0.date, now: now) }.reduce(0) { $0 + $1.coinsSpent }
    }
    static func entries(people: [Person], state: ProfileState?, period: StarRankingPeriod, now: Date) -> [StarRankingEntry] {
        let available = Set(people.map(\.id))
        var rows = featured.compactMap { item -> StarRankingEntry? in
            guard available.contains(item.id), item.id != state?.person.id else { return nil }
            let amount: Int
            switch period {
            case .daily: amount = item.daily
            case .weekly: amount = item.weekly
            case .allTime: amount = item.total
            }
            return StarRankingEntry(personID: item.id, coins: amount)
        }
        let mine = ownCoins(in: state, period: period, now: now)
        if let state, mine > 0 { rows.append(StarRankingEntry(personID: state.person.id, coins: mine)) }
        return rows.sorted { $0.coins == $1.coins ? $0.personID < $1.personID : $0.coins > $1.coins }
    }
}
