import SwiftUI

struct WalletView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var wallet: WalletService
    var body: some View {
        Page(title: "Get Coins") {
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: 16) {
                        Artwork(name: "welcome-wardrobe").frame(width: 100, height: 124)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR STYLE FUND").font(.outfit(size: 10, weight: .bold)).tracking(1.7).foregroundStyle(Palette.pink)
                            CoinLabel(amount: store.state?.coins ?? 0)
                            Text("Little details. Big entrance.").font(.outfit(size: 13)).foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose your coin drop").font(.outfit(size: 22, weight: .bold))
                        Text("US reference prices. Tap a pack to get its current Apple price; confirm payment in Apple's purchase sheet.").font(.outfit(size: 12)).foregroundStyle(Palette.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(CoinPack.all) { pack in
                            Button { Task { await wallet.purchase(pack, store: store) } } label: {
                                VStack(spacing: 10) {
                                    Artwork(name: "icon-coin").frame(width: 38, height: 38)
                                    Text(pack.total.formatted()).font(.outfit(size: 20, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1)
                                    Text("COINS").font(.outfit(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.secondary)
                                    Text(wallet.purchasing == pack.id ? "Connecting…" : wallet.products[pack.id]?.displayPrice ?? "US$" + pack.referenceUSD)
                                        .font(.outfit(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                                        .frame(maxWidth: .infinity).frame(height: 34).background(Palette.blush, in: Capsule())
                                }.padding(10).frame(maxWidth: .infinity).frame(height: 160).background(.white, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).disabled(wallet.purchasing != nil)
                            .accessibilityLabel("\(pack.total) coins, US reference price \(pack.referenceUSD) dollars. Buy from Apple.")
                        }
                    }
                    if !wallet.status.isEmpty { Text(wallet.status).font(.outfit(size: 13)).foregroundStyle(Palette.secondary) }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Where your coins go").font(.outfit(size: 21, weight: .bold))
                        NavigationLink(value: Route.atelier) {
                            HStack(spacing: 12) { Artwork(name: "runway-frame").frame(width: 52, height: 52); VStack(alignment: .leading, spacing: 4) { Text("Runway Ribbon").font(.outfit(size: 15, weight: .semibold)); Text("240 coins · permanent avatar frame").font(.outfit(size: 12)).foregroundStyle(Palette.secondary) }; Spacer(minLength: 0) }
                        }.buttonStyle(.plain)
                        NavigationLink(value: Route.shop(false)) {
                            HStack(spacing: 12) { Artwork(name: "gift-bear").frame(width: 52, height: 52); VStack(alignment: .leading, spacing: 4) { Text("Gift & charm collection").font(.outfit(size: 15, weight: .semibold)); Text("40–1,800 coins each · collect and wear").font(.outfit(size: 12)).foregroundStyle(Palette.secondary) }; Spacer(minLength: 0) }
                        }.buttonStyle(.plain)
                        Text("Always free: messages, voice and video chats, AI style conversations, browsing, likes, comments and posting.").font(.outfit(size: 13)).foregroundStyle(Palette.secondary)
                        Text("Gift delivery to another member is currently unavailable. Purchased collectibles are available in your backpack and as your profile charm.").font(.outfit(size: 11)).foregroundStyle(Palette.secondary)
                    }.panel()
                    Button(wallet.recovering ? "Checking purchases…" : "Check pending purchases") { Task { await wallet.recover(store: store) } }
                        .font(.outfit(size: 14, weight: .semibold)).foregroundStyle(Palette.pink).frame(minHeight: 44).disabled(wallet.recovering || wallet.purchasing != nil)
                    Text("Coins never expire. Your wallet and items are saved to this account on this device. Cross-device wallet sync is not available. The final price and currency are shown by Apple before you pay.")
                        .font(.outfit(size: 11)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recent activity").font(.outfit(size: 20, weight: .bold))
                        if let debt = store.state?.refundDebt, debt > 0 { Text("Refund adjustment remaining: \(debt) coins. Future credits settle this first.").font(.outfit(size: 12)).foregroundStyle(Palette.secondary) }
                        if store.state?.ledger.isEmpty != false { Text("Your coin activity will appear here.").font(.outfit(size: 14)).foregroundStyle(Palette.secondary) }
                        ForEach(Array((store.state?.ledger ?? []).prefix(30))) { entry in
                            HStack { VStack(alignment: .leading, spacing: 5) { Text(entry.title).font(.outfit(size: 14)); Text(entry.date, style: .date).font(.outfit(size: 11)).foregroundStyle(Palette.secondary) }; Spacer(); Text(entry.amount > 0 ? "+\(entry.amount)" : "\(entry.amount)").font(.outfit(size: 14, weight: .semibold)).foregroundStyle(entry.amount >= 0 ? Palette.pink : Palette.ink) }
                        }
                    }.panel()
                }.padding(16)
            }
        }
    }
}
struct GiftShopView: View {
    @EnvironmentObject private var store: AppStore
    let initialBackpack: Bool
    @State private var section = "Gift Shop"
    @State private var selected = Gift.all[0]
    @State private var quantity = 1
    var body: some View {
        Page(title: "Backpack") {
            VStack(spacing: 16) {
                SectionTabs(titles: ["Gift Shop", "My Backpack"], selection: $section)
                HStack { CoinLabel(amount: store.state?.coins ?? 0); Spacer(); NavigationLink("Get Coins", value: Route.wallet).font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink) }.padding(.horizontal, 20)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
                        ForEach(Gift.all) { gift in
                            Button { selected = gift } label: {
                                VStack(spacing: 10) { Artwork(name: gift.image).frame(height: 62); Text(gift.name).font(.outfit(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7); if section == "Gift Shop" { HStack(spacing: 3) { Artwork(name: "icon-coin").frame(width: 12, height: 12); Text("\(gift.price)").font(.tutuCaption) } } else { Text("Owned ×\(store.state?.inventory[gift.id] ?? 0)").font(.outfit(size: 10)) } }.frame(maxWidth: .infinity).padding(.vertical, 12).background(selected.id == gift.id ? Palette.pink.opacity(0.12) : .white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(selected.id == gift.id ? Palette.pink : .clear, lineWidth: 1.5))
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
                VStack(spacing: 12) {
                    HStack { Text(selected.name).font(.tutuHeadline); Spacer(); if section == "Gift Shop" { Button("Less") { quantity = max(1, quantity-1) }.foregroundStyle(Palette.pink).frame(minHeight: 44); Text("\(quantity)").monospacedDigit().frame(width: 30); Button("More") { quantity = min(99, quantity+1) }.foregroundStyle(Palette.pink).frame(minHeight: 44) } }
                    if section == "Gift Shop" {
                        HStack { Text("Total").font(.tutuSubheadline); Spacer(); CoinLabel(amount: selected.price * quantity) }
                        PinkButton(title: "Collect · \(selected.price * quantity) coins") { store.requestCoins(for: .gift(selected, quantity)) }
                        Text("Collect for your backpack or wear as a profile charm. Remote delivery is currently unavailable.").font(.outfit(size: 11)).foregroundStyle(Palette.secondary)
                    } else {
                        Text("Wear an owned collectible beside your avatar. Switching charms is free and keeps every item in your backpack.").font(.outfit(size: 13)).foregroundStyle(Palette.secondary)
                        if (store.state?.inventory[selected.id] ?? 0) > 0 {
                            PinkButton(title: store.state?.featuredGift == selected.id ? "Remove profile charm" : "Wear as profile charm") {
                                store.commit { $0.featuredGift = $0.featuredGift == selected.id ? nil : selected.id }
                            }
                        }
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
            HStack { Text("A gift for \(store.person(personID).name)").font(.tutuHeadline); Spacer(); ArtButton(label: "Close", asset: "nav-close") { dismiss() } }
            ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) { ForEach(Gift.all) { gift in Button { selected = gift } label: { VStack { Artwork(name: gift.image).frame(height: 62); Text("×\(store.state?.inventory[gift.id] ?? 0)").font(.tutuCaption) }.padding(8).frame(maxWidth: .infinity).background(selected == gift ? Palette.pink.opacity(0.15) : .white, in: RoundedRectangle(cornerRadius: 15)) }.buttonStyle(.plain) } } }
            HStack { Button("Less") { quantity = max(1, quantity - 1) }; Spacer(); Text("\(selected.name) × \(quantity)").font(.tutuHeadline); Spacer(); Button("More") { quantity = min(99, quantity + 1) } }.foregroundStyle(Palette.pink).frame(minHeight: 44)
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
                    HStack { Text("Day \(max(1, store.state?.checkinStreak ?? 0)) of 7").font(.tutuHeadline); Spacer(); NavigationLink(value: Route.info("Daily Check")) { Artwork(name: "nav-help").frame(width: 26, height: 26).frame(width: 44, height: 44) } }.padding(.horizontal, 18)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(0..<7) { index in VStack(spacing: 10) { Text("Day \(index+1)").font(.tutuCaption.bold()); Artwork(name: "icon-coin").frame(height: 36); Text("× \(rewards[index])").font(.tutuSubheadline.bold()); if checked && index < (store.state?.checkinStreak ?? 0) { Artwork(name: "control-check").frame(width: 20, height: 20) } }.frame(maxWidth: .infinity).frame(height: 130).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(index+1 == store.state?.checkinStreak ? Palette.pink : .clear, lineWidth: 1.5)) }
                    }.padding(.horizontal, 18)
                    PinkButton(title: checked ? "Checked in today" : "Check In", asset: checked ? nil : "button-checkin") { if !checked { store.checkIn() } }.disabled(checked).padding(.horizontal, 18)
                    HStack { CoinLabel(amount: store.state?.coins ?? 0); Spacer(); Text("\(store.state?.points ?? 0) points · Lv. \(store.state?.level ?? 1)").font(.tutuSubheadline) }.padding(20)
                }.padding(.bottom, 20)
            }
        }
    }
}
