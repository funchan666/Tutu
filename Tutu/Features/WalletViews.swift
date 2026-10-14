import SwiftUI

struct WalletView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var wallet: WalletService
    var body: some View {
        Page(title: "Get Coins") {
            ScrollView {
                VStack(spacing: 22) {
                    HStack { VStack(alignment: .leading, spacing: 8) { Text("Your balance").font(.subheadline).foregroundStyle(Palette.secondary); CoinLabel(amount: store.state?.coins ?? 0) }; Spacer(); NavArt(route: .info("Coins"), asset: "nav-help", label: "About coins") }.panel()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(Array(CoinPack.all.enumerated()), id: \.element.id) { index, pack in
                            Button { Task { await wallet.purchase(pack, store: store) } } label: {
                                VStack(spacing: 10) {
                                    HStack { Spacer(); if pack.bonus > 0 { Text("+\(pack.bonusPercent)%").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.pink) } }.frame(height: 14)
                                    Artwork(name: index == 0 ? "icon-flame" : "icon-coin").frame(width: 50, height: 50)
                                    Text(pack.total.formatted()).font(.system(size: 18, weight: .bold, design: .rounded))
                                    if pack.bonus > 0 { Text("\(pack.coins) + \(pack.bonus)").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                                    Text(wallet.purchasing == pack.id ? "Processing…" : wallet.products[pack.id]?.displayPrice ?? "Unavailable").font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).padding(.vertical, 8).frame(maxWidth: .infinity).background(Palette.blush, in: Capsule())
                                }.padding(12).frame(maxWidth: .infinity).frame(height: 180).background(.white, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain).disabled(wallet.purchasing != nil)
                        }
                    }
                    if wallet.loading { Text("Loading prices…").font(.subheadline) }
                    if !wallet.status.isEmpty { Text(wallet.status).font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center) }
                    PinkButton(title: "Refresh prices", busy: wallet.loading) { Task { await wallet.load() } }
                    Text("Payments use Apple's secure purchase sheet. No payment is taken unless you confirm a purchase with Apple.").font(.caption).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    NavigationLink(value: Route.shop(false)) { Text("Visit the gift shop").font(.headline).foregroundStyle(Palette.pink).padding(12) }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recent activity").font(.headline)
                        if store.state?.ledger.isEmpty != false { Text("Your coin activity will appear here.").font(.subheadline).foregroundStyle(Palette.secondary) }
                        ForEach(Array((store.state?.ledger ?? []).prefix(30))) { entry in HStack { VStack(alignment: .leading, spacing: 5) { Text(entry.title).font(.subheadline); Text(entry.date, style: .date).font(.caption).foregroundStyle(Palette.secondary) }; Spacer(); Text(entry.amount > 0 ? "+\(entry.amount)" : "\(entry.amount)").font(.subheadline.bold()).foregroundStyle(entry.amount >= 0 ? Palette.pink : Palette.ink) } }
                    }.panel()
                }.padding(16)
            }
        }.task { await wallet.load() }
    }
}
struct GiftShopView: View {
    @EnvironmentObject private var store: AppStore
    let initialBackpack: Bool
    @State private var section = "Gift Shop"
    @State private var selected = Gift.all[0]
    @State private var quantity = 1
    @State private var purchased = false
    var body: some View {
        Page(title: "Backpack") {
            VStack(spacing: 16) {
                SectionTabs(titles: ["Gift Shop", "My Backpack"], selection: $section)
                HStack { CoinLabel(amount: store.state?.coins ?? 0); Spacer(); NavigationLink("Get Coins", value: Route.wallet).font(.subheadline.bold()).foregroundStyle(Palette.pink) }.padding(.horizontal, 20)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
                        ForEach(Gift.all) { gift in
                            Button { selected = gift; purchased = false } label: {
                                VStack(spacing: 10) { Artwork(name: gift.image).frame(height: 62); Text(gift.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7); if section == "Gift Shop" { HStack(spacing: 3) { Artwork(name: "icon-coin").frame(width: 12, height: 12); Text("\(gift.price)").font(.caption) } } else { Text("Owned ×\(store.state?.inventory[gift.id] ?? 0)").font(.system(size: 10)) } }.frame(maxWidth: .infinity).padding(.vertical, 12).background(selected.id == gift.id ? Palette.pink.opacity(0.12) : .white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(selected.id == gift.id ? Palette.pink : .clear, lineWidth: 1.5))
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
                VStack(spacing: 12) {
                    HStack { Text(selected.name).font(.headline); Spacer(); if section == "Gift Shop" { Button("Less") { quantity = max(1, quantity-1) }.foregroundStyle(Palette.pink).frame(minHeight: 44); Text("\(quantity)").monospacedDigit().frame(width: 30); Button("More") { quantity = min(99, quantity+1) }.foregroundStyle(Palette.pink).frame(minHeight: 44) } }
                    if section == "Gift Shop" {
                        HStack { Text("Total").font(.subheadline); Spacer(); CoinLabel(amount: selected.price * quantity) }
                        PinkButton(title: purchased ? "Added to backpack" : "Buy · \(selected.price * quantity) coins") { purchased = store.buy(selected, quantity: quantity) }
                    } else {
                        Text("Choose a gift from a member's profile, chat, or room to send it. Your items remain in your backpack until delivery succeeds.").font(.subheadline).foregroundStyle(Palette.secondary)
                        PinkButton(title: "Open Gift Shop") { section = "Gift Shop" }
                    }
                }.padding(20).background(.white)
            }
        }.onAppear { section = initialBackpack ? "My Backpack" : "Gift Shop" }
    }
}
struct GiftDeliveryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let personID: String
    @State private var selected = Gift.all[0]
    @State private var quantity = 1
    @State private var busy = false
    var body: some View {
        VStack(spacing: 18) {
            HStack { Text("A gift for \(store.person(personID).name)").font(.headline); Spacer(); ArtButton(label: "Close", asset: "nav-close") { dismiss() } }
            ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) { ForEach(Gift.all) { gift in Button { selected = gift } label: { VStack { Artwork(name: gift.image).frame(height: 62); Text("×\(store.state?.inventory[gift.id] ?? 0)").font(.caption) }.padding(8).frame(maxWidth: .infinity).background(selected == gift ? Palette.pink.opacity(0.15) : .white, in: RoundedRectangle(cornerRadius: 15)) }.buttonStyle(.plain) } } }
            HStack { Button("Less") { quantity = max(1, quantity - 1) }; Spacer(); Text("\(selected.name) × \(quantity)").font(.headline); Spacer(); Button("More") { quantity = min(99, quantity + 1) } }.foregroundStyle(Palette.pink).frame(minHeight: 44)
            PinkButton(title: "Send gift", busy: busy) {
                guard !((store.state?.blocked.contains(personID)) ?? false) else { store.show("Member blocked", "Unblock this member before sending a gift."); return }
                guard (store.state?.inventory[selected.id] ?? 0) >= quantity else { store.show("Your backpack needs a little love", "Get this item from Gift Shop before sending it."); return }
                store.show("Gift delivery unavailable", "Your gift hasn't been delivered. All items remain in your backpack. Please try again later.")
            }
        }.padding(22).background(Palette.blush).presentationDetents([.medium, .large]).overlay { NoticeOverlay() }
    }
}
struct CheckinView: View {
    @EnvironmentObject private var store: AppStore
    var checked: Bool { store.state?.checkinDates.contains(AppStore.dayKey(Date())) == true }
    let rewards = [10,20,10,20,10,20,100]
    var body: some View {
        Page(title: "Daily Check") {
            ScrollView {
                VStack(spacing: 20) {
                    // The supplied artwork already contains the headline; do not repeat it.
                    GeometryReader { geometry in
                        Image("checkin-background").resizable().scaledToFit()
                            .frame(width: geometry.size.width)
                            .offset(y: -geometry.size.width * 200 / 780)
                    }.aspectRatio(780.0 / 650.0, contentMode: .fit).clipped()
                    HStack { Text("Day \(max(1, store.state?.checkinStreak ?? 0)) of 7").font(.headline); Spacer(); NavigationLink(value: Route.info("Daily Check")) { Artwork(name: "nav-help").frame(width: 26, height: 26).frame(width: 44, height: 44) } }.padding(.horizontal, 18)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(0..<7) { index in VStack(spacing: 10) { Text("Day \(index+1)").font(.caption.bold()); Artwork(name: "icon-coin").frame(height: 36); Text("× \(rewards[index])").font(.subheadline.bold()); if checked && index < (store.state?.checkinStreak ?? 0) { Artwork(name: "control-check").frame(width: 20, height: 20) } }.frame(maxWidth: .infinity).frame(height: 130).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(index+1 == store.state?.checkinStreak ? Palette.pink : .clear, lineWidth: 1.5)) }
                    }.padding(.horizontal, 18)
                    PinkButton(title: checked ? "Checked in today" : "Check In", asset: checked ? nil : "button-checkin") { if !checked { store.checkIn() } }.disabled(checked).padding(.horizontal, 18)
                    HStack { CoinLabel(amount: store.state?.coins ?? 0); Spacer(); Text("\(store.state?.points ?? 0) points · Lv. \(store.state?.level ?? 1)").font(.subheadline) }.padding(20)
                }.padding(.bottom, 20)
            }
        }
    }
}
