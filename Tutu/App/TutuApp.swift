import SwiftUI

@main struct TutuApp: App {
    @UIApplicationDelegateAdaptor(AtelierAppDelegate.self) private var appDelegate
    @StateObject private var gateway = AtelierGateway()
    @StateObject private var store = AppStore()
    @StateObject private var wallet = WalletService()
    var body: some Scene {
        WindowGroup { StartupGateView().font(.tutuBody).environmentObject(store).environmentObject(wallet).environmentObject(gateway).environment(\.locale, store.appLanguage.locale).preferredColorScheme(.light).tint(Palette.pink) }
    }
}
enum Route: Hashable {
    case atelier, profile(String), chat(String), room(String), post(String), album(String, Int), wallet, shop(Bool), checkin, settings, editProfile, inbox, systemMessages, search, leaderboard, createRoom, compose, relationships(String), info(String), stylist(String, String), call(String, Bool), security, privacy, language
}
struct RootView: View {
    @EnvironmentObject private var gateway: AtelierGateway
    @EnvironmentObject private var store: AppStore
    @State private var path: [Route] = []
    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                Group { if store.state != nil && gateway.route == .native { MainTabs() } else { WelcomeView() } }
                    .navigationDestination(for: Route.self) { route in destination(route) }
                    .toolbar(.hidden, for: .navigationBar)
            }.id(store.sessionID ?? "welcome")
                .allowsHitTesting(store.accountExit == nil)
                .accessibilityHidden(store.accountExit != nil)

            CoinSpendOverlay()
            NoticeOverlay()
            AccountExitOverlay()
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
    @EnvironmentObject private var gateway: AtelierGateway
    @EnvironmentObject private var store: AppStore
    private let names = ["Style Live", "Party", "Create Your Look", "Discover", "Profile"]
    private let assets = ["tab-live", "tab-party", "tab-studio", "tab-discover", "tab-profile"]
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if Catalog.snapshot == nil {
                    VStack(spacing: 16) {
                        Text(gateway.contentLoading ? "Loading your style collection…" : gateway.contentError).font(.tutuSubheadline)
                        if !gateway.contentLoading { PinkButton(title: "Try again") { gateway.reloadContent() } }
                    }.padding(24)
                } else { switch store.tab {
                case 0: LiveHomeView()
                case 1: PartyHomeView()
                case 2: StyleStudioView()
                case 3: DiscoverView()
                default: MyProfileView()
                } }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let room = store.minimizedRoom {
                NavigationLink(value: Route.room(room.id)) { HStack { if room.isBroadcasting == true { RoomLiveBadge() } else { Artwork(name: "icon-room-chat").frame(width: 30, height: 30) }; Text(room.title).font(.tutuCaption.bold()); Spacer(); Text("Open").font(.tutuCaption) }.padding(10).background(Palette.blush) }.buttonStyle(.plain)
            }
            HStack(spacing: 0) { ForEach(0..<5) { index in
                Button { store.tab = index } label: { Artwork(name: assets[index] + (store.tab == index ? "-active" : "")).frame(width: 28, height: 28).frame(maxWidth: .infinity).frame(height: 54).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(Text(ui: names[index])).accessibilityAddTraits(store.tab == index ? [.isSelected] : [])
            } }.background(.white)
        }.background(SceneBackground()).foregroundStyle(Palette.ink).onAppear { store.arriveHome() }
    }
}


struct StartupGateView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var wallet: WalletService
    @EnvironmentObject private var gateway: AtelierGateway
    @Environment(\.scenePhase) private var scene
    var body: some View {
        ZStack {
            RootView().opacity(gateway.route == .web ? 0 : 1).allowsHitTesting(gateway.route != .web)
                .accessibilityHidden(gateway.route == .web)
            if let web = gateway.web {
                AtelierWebHost(owner: web).ignoresSafeArea().opacity(gateway.route == .web ? 1 : 0)
                    .allowsHitTesting(gateway.route == .web).accessibilityHidden(gateway.route != .web)
                if gateway.route == .web { AtelierWebFeedback(owner: web) }
            }
            if gateway.route == .web { NoticeOverlay() }
            if wallet.purchasing != nil {
                Color.black.opacity(0.55).ignoresSafeArea().accessibilityHidden(true)
                Text(wallet.paymentText).font(.tutuHeadline).foregroundStyle(.white).multilineTextAlignment(.center).padding(28)
                    .accessibilityAddTraits(.isModal)
            }
        }.task { gateway.start(store: store, wallet: wallet); gateway.foreground(scene == .active) }
        .onChange(of: scene) { _, phase in gateway.foreground(phase == .active) }
        .onChange(of: store.sessionID) { old, new in
            if old != nil && new == nil { wallet.sessionEnded(); gateway.sessionEnded() }
            if new != nil { Task { await wallet.recover(store: store) } }
        }
        .onOpenURL { gateway.wake($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            Task { await wallet.recover(store: store) }
        }
    }
}
