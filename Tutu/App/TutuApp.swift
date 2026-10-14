import SwiftUI

@main struct TutuApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var wallet = WalletService()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store).environmentObject(wallet).preferredColorScheme(.light).tint(Palette.pink).task { wallet.start(store: store) }.onChange(of: store.sessionID) { _, _ in Task { await wallet.recover(store: store) } } }
    }
}
enum Route: Hashable {
    case profile(String), chat(String), room(String), post(String), album(String, Int), wallet, shop(Bool), checkin, settings, editProfile, inbox, systemMessages, search, leaderboard, createRoom, compose, relationships(String), info(String), stylist(String, String), call(String, Bool), security, privacy, language
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var path: [Route] = []
    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                Group { if store.state == nil { WelcomeView() } else if store.me.birthday == nil { EditProfileView() } else { MainTabs() } }
                    .navigationDestination(for: Route.self) { route in destination(route) }
                    .toolbar(.hidden, for: .navigationBar)
            }.id(store.sessionID ?? "welcome")
            NoticeOverlay()
        }.onChange(of: store.sessionID) { _, _ in path = [] }
    }
    @ViewBuilder func destination(_ route: Route) -> some View {
        switch route {
        case .profile(let id): if id == store.me.id { Page(title: "My Profile") { MyProfileView() } } else { ProfileView(personID: id) }
        case .chat(let id): ChatView(personID: id)
        case .room(let id): if let room = store.rooms.first(where: { $0.id == id }) { RoomView(room: room) } else { Page(title: "Room") { EmptyState(title: "This room is unavailable") } }
        case .post(let id): PostDetailView(postID: id)
        case .album(let id, let index): AlbumView(personID: id, initialIndex: index)
        case .wallet: WalletView()
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
                NavigationLink(value: Route.room(room.id)) { HStack { Artwork(name: "icon-room-chat").frame(width: 30, height: 30); Text(room.title).font(.caption.bold()); Spacer(); Text("Open").font(.caption) }.padding(10).background(Palette.blush) }.buttonStyle(.plain)
            }
            HStack(spacing: 0) { ForEach(0..<5) { index in
                Button { store.tab = index } label: { Artwork(name: assets[index] + (store.tab == index ? "-active" : "")).frame(width: 28, height: 28).frame(maxWidth: .infinity).frame(height: 54).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(names[index]).accessibilityAddTraits(store.tab == index ? [.isSelected] : [])
            } }.background(.white)
        }.background(SceneBackground()).foregroundStyle(Palette.ink)
    }
}
