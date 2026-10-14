import SwiftUI

struct WelcomeCoinDrop: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.10, green: 0.035, blue: 0.18).opacity(0.92).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Text("TUTU · FIRST STYLE DROP").font(.outfit(size: 11, weight: .semibold)).tracking(2.4).foregroundStyle(Color(red: 0.90, green: 0.72, blue: 0.97))
                        Artwork(name: "welcome-wardrobe").frame(height: min(geometry.size.height * 0.36, 275))
                            .scaleEffect(appeared ? 1 : 0.82).offset(y: appeared ? 0 : 22)
                            .rotationEffect(.degrees(appeared ? 0 : -7))
                        Text("Your style.\nYour opening act.").font(.outfit(size: 32, weight: .bold)).tracking(-0.8).multilineTextAlignment(.center).foregroundStyle(.white)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("+\(CoinEconomy.welcomeCoins)").font(.outfit(size: 54, weight: .bold)).contentTransition(.numericText())
                            Text("COINS").font(.outfit(size: 12, weight: .semibold)).tracking(2)
                        }.foregroundStyle(Color(red: 1, green: 0.81, blue: 0.91))
                        Text("Already in your wallet.\nPick a runway frame or start your charm collection.").font(.outfit(size: 14)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                        PinkButton(title: "Make an entrance") { store.finishWelcome() }.padding(.top, 8)
                        Text("A one-time welcome gift. Chatting is always free.").font(.outfit(size: 11)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                    }.padding(28).frame(maxWidth: 420).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
                }
            }.onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.72)) { appeared = true } }
        }.accessibilityAddTraits(.isModal).zIndex(80)
    }
}
struct CoinSpendOverlay: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if let prompt = store.coinPrompt {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("A LITTLE STYLE UPGRADE").font(.outfit(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.pink)
                    Artwork(name: prompt.artwork).frame(width: 110, height: 110)
                    Text(prompt.title).font(.outfit(size: 23, weight: .bold)).multilineTextAlignment(.center)
                    Text(prompt.detail).font(.outfit(size: 14)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    HStack { Text("Your balance"); Spacer(); CoinLabel(amount: store.state?.coins ?? 0) }.font(.outfit(size: 14))
                    HStack { Text("After this purchase"); Spacer(); CoinLabel(amount: max(0, (store.state?.coins ?? 0) - prompt.amount)) }.font(.outfit(size: 14))
                    PinkButton(title: "Use \(prompt.amount) coins") { store.confirmCoinSpend() }
                    Button("Keep browsing") { store.coinPrompt = nil }.font(.outfit(size: 14)).foregroundStyle(Palette.secondary).frame(minHeight: 44)
                }.padding(24).background(Palette.blush, in: RoundedRectangle(cornerRadius: 28)).padding(24).frame(maxWidth: 430)
            }.accessibilityAddTraits(.isModal).zIndex(90)
        }
    }
}
struct StyleAtelierView: View {
    @EnvironmentObject private var store: AppStore
    var owned: Bool { store.state?.ownedCosmetics?.contains(CoinEconomy.runwayFrame) == true }
    var worn: Bool { store.state?.equippedFrame == CoinEconomy.runwayFrame }
    var body: some View {
        Page(title: "Style Atelier") {
            ScrollView {
                VStack(spacing: 24) {
                    HStack { CoinLabel(amount: store.state?.coins ?? 0); Spacer(); NavigationLink("Get Coins", value: Route.wallet).font(.outfit(size: 14, weight: .semibold)).foregroundStyle(Palette.pink) }
                    Text("THE RUNWAY EDIT").font(.outfit(size: 11, weight: .semibold)).tracking(3).foregroundStyle(Palette.pink)
                    ZStack {
                        MediaArtwork(reference: store.me.avatar).frame(width: 190, height: 190).clipShape(Circle())
                        Artwork(name: "runway-frame").frame(width: 240, height: 240)
                    }.frame(height: 250)
                    VStack(spacing: 8) {
                        Text("Runway Ribbon").font(.outfit(size: 28, weight: .bold))
                        Text("Chrome curves. Orchid silk.\nA signature frame for your entrance.").font(.outfit(size: 15)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                        Text("Permanent unlock · 240 coins").font(.outfit(size: 12, weight: .semibold)).foregroundStyle(Palette.pink).padding(.top, 6)
                    }
                    PinkButton(title: owned ? (worn ? "Remove frame" : "Wear your frame") : "Unlock · 240 coins") {
                        if owned { store.commit { $0.equippedFrame = worn ? nil : CoinEconomy.runwayFrame } }
                        else { store.requestCoins(for: .runwayFrame) }
                    }
                    Text("Yours to wear, change, and wear again.\nNo renewal. No charge for changing your style.").font(.outfit(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    NavigationLink(value: Route.shop(true)) { Text("Style your profile with a gift charm").font(.outfit(size: 15, weight: .semibold)).foregroundStyle(Palette.pink).padding(.vertical, 14) }
                }.padding(22)
            }
        }
    }
}
