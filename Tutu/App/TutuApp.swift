import SwiftUI

@main struct TutuApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var wallet = WalletService()
    var body: some Scene {
        WindowGroup { StartupGateView().font(.tutuBody).environmentObject(store).environmentObject(wallet).preferredColorScheme(.light).tint(Palette.pink) }
    }
}
enum Route: Hashable {
    case atelier, profile(String), chat(String), room(String), post(String), album(String, Int), wallet, shop(Bool), checkin, settings, editProfile, inbox, systemMessages, search, leaderboard, createRoom, compose, relationships(String), info(String), stylist(String, String), call(String, Bool), security, privacy, language
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var path: [Route] = []
    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                // Profile editing is a pushed destination, never an authentication gate.
                Group { if store.state == nil { WelcomeView() } else { MainTabs() } }
                    .navigationDestination(for: Route.self) { route in destination(route) }
                    .toolbar(.hidden, for: .navigationBar)
            }.id(store.sessionID ?? "welcome")
            if store.welcomeVisible { WelcomeCoinDrop() }
            CoinSpendOverlay()
            NoticeOverlay()
        }.onChange(of: store.sessionID) { _, _ in path = [] }
            .onChange(of: store.walletRequest) { _, _ in if path.last != .wallet { path.append(.wallet) } }
            .onChange(of: store.state?.hiddenContent) { _, _ in removeHiddenDestinations() }
            .onChange(of: store.state?.blocked) { _, _ in removeHiddenDestinations() }
    }
    private func removeHiddenDestinations() {
        let firstHidden = path.firstIndex { route in
            switch route {
            case .profile(let id), .chat(let id), .album(let id, _), .call(let id, _): return store.isPersonHidden(id)
            case .room(let id): return !store.rooms.contains(where: { $0.id == id })
            case .post(let id): return !store.looks.contains(where: { $0.id == id })
            default: return false
            }
        }
        if let firstHidden { path.removeSubrange(firstHidden...) }
    }
    @ViewBuilder func destination(_ route: Route) -> some View {
        switch route {
        case .profile(let id): if id == store.me.id { Page(title: "My Profile") { MyProfileView() } } else { ProfileView(personID: id) }
        case .chat(let id): ChatView(personID: id)
        case .room(let id): if let room = store.rooms.first(where: { $0.id == id }) { RoomView(room: room) } else { Page(title: "Room") { EmptyState(title: "This room is unavailable") } }
        case .post(let id): PostDetailView(postID: id)
        case .album(let id, let index): AlbumView(personID: id, initialIndex: index)
        case .wallet: WalletView()
        case .atelier: StyleAtelierView()
        case .shop(let backpack): GiftShopView(initialBackpack: backpack)
        case .checkin: CheckinView()
        case .settings: SettingsView()
        case .editProfile: EditProfileView()
        case .inbox: InboxView()
        case .systemMessages: SystemMessagesView()
        case .search: SearchView()
        case .leaderboard: LeaderboardView()
        case .createRoom: CreateRoomView()
        case .compose: ComposeLookView()
        case .relationships(let kind): RelationshipView(kind: kind)
        case .info(let kind): InformationView(kind: kind)
        case .stylist(let style, let occasion): StylistChatView(style: style, occasion: occasion)
        case .call(let id, let video): CallView(personID: id, video: video)
        case .security: SecurityView()
        case .privacy: PrivacyView()
        case .language: LanguageView()
        }
    }
}
struct MainTabs: View {
    @EnvironmentObject private var store: AppStore
    private let names = ["Style Live", "Party", "Create Your Look", "Discover", "Profile"]
    private let assets = ["tab-live", "tab-party", "tab-studio", "tab-discover", "tab-profile"]
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch store.tab {
                case 0: LiveHomeView()
                case 1: PartyHomeView()
                case 2: StyleStudioView()
                case 3: DiscoverView()
                default: MyProfileView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let room = store.minimizedRoom {
                NavigationLink(value: Route.room(room.id)) { HStack { Artwork(name: "icon-room-chat").frame(width: 30, height: 30); Text(room.title).font(.tutuCaption.bold()); Spacer(); Text("Open").font(.tutuCaption) }.padding(10).background(Palette.blush) }.buttonStyle(.plain)
            }
            HStack(spacing: 0) { ForEach(0..<5) { index in
                Button { store.tab = index } label: { Artwork(name: assets[index] + (store.tab == index ? "-active" : "")).frame(width: 28, height: 28).frame(maxWidth: .infinity).frame(height: 54).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(names[index]).accessibilityAddTraits(store.tab == index ? [.isSelected] : [])
            } }.background(.white)
        }.background(SceneBackground()).foregroundStyle(Palette.ink).onAppear { store.arriveHome() }
    }
}


/// Matches LaunchScreen.storyboard: full-screen black, a 112pt centered icon,
/// then three 8pt pink lights 28pt below it. No full-screen image scaling.
struct StartupSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                Image("brand-mascot").resizable().scaledToFit()
                    .frame(width: 112, height: 112)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Image("tab-party-active").resizable().scaledToFit()
                            .frame(width: 8, height: 8)
                            .opacity(reduceMotion ? 0.7 : (pulsing ? 1 : [0.35, 0.65, 1.0][index]))
                            .scaleEffect(reduceMotion ? 1 : (pulsing ? 1.15 : 1))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.65).repeatForever(autoreverses: true).delay(Double(index) * 0.16), value: pulsing)
                    }
                }.position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 88)
            }
        }.ignoresSafeArea().statusBarHidden(true)
            .accessibilityElement(children: .ignore).accessibilityLabel("Tutu is loading")
            .onAppear { pulsing = true }
    }
}

struct StartupGateView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var wallet: WalletService
    @State private var ready = false
    var body: some View {
        Group {
            if ready { RootView() }
            else { StartupSplashView() }
        }.task {
            guard !ready else { return }
            await store.restoreSession()
            guard !Task.isCancelled else { return }
            wallet.start(store: store)
            // Move on as soon as local restoration finishes; no fake progress or fixed delay.
            ready = true
        }.onChange(of: store.sessionID) { _, _ in
            if ready { Task { await wallet.recover(store: store) } }
        }
    }
}
