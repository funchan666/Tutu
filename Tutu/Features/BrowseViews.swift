import SwiftUI

struct NavArt: View {
    let route: Route
    let asset: String
    let label: String
    var body: some View { NavigationLink(value: route) { Artwork(name: asset).frame(width: 34, height: 34).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(label) }
}
struct LiveHomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var category = "All"
    private var liveRooms: [StyleRoom] { store.rooms.filter { !$0.voice } }
    private var filteredRooms: [StyleRoom] { liveRooms.filter { category == "All" || $0.styleCategory == category } }
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-style-live") {
                HStack(spacing: 2) {
                    NavArt(route: .leaderboard, asset: "icon-trophy", label: "Leaderboard")
                    NavArt(route: .createRoom, asset: "nav-create", label: "Create room")
                    NavArt(route: .search, asset: "nav-search", label: "Search")
                    InboxEntryButton()
                }
            }
            ScrollView {
                VStack(spacing: 4) {
                    FeaturedRoomsCarousel(rooms: Array(liveRooms.filter { $0.video != nil }.prefix(3)))
                        .padding(.horizontal, 16)
                    SectionTabs(titles: RoomCategories.filters, selection: $category, compact: true)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredRooms) { room in RoomCard(room: room) }
                    }.padding(.horizontal, 16)
                    if filteredRooms.isEmpty {
                        EmptyState(title: "No rooms here yet", message: "Try another category or create your own.")
                    }
                }.padding(.bottom, 16)
            }
        }
    }
}

struct FeaturedRoomsCarousel: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let rooms: [StyleRoom]
    @State private var selection = 0
    @State private var visible = false
    @State private var lastInteraction = Date()
    private var canRotate: Bool { visible && scene == .active && !reduceMotion && !voiceOver && rooms.count > 1 }
    var body: some View {
        if !rooms.isEmpty {
            ZStack(alignment: .bottom) {
                TabView(selection: $selection) {
                    ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                        NavigationLink(value: Route.room(room.id)) {
                            GeometryReader { geometry in
                                ZStack(alignment: .trailing) {
                                    MediaArtwork(reference: room.cover).blur(radius: 18)
                                    MediaArtwork(reference: room.cover, mode: .fit)
                                        .frame(width: geometry.size.width * 0.58, height: geometry.size.height)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) { if room.isBroadcasting == true { RoomLiveBadge(animated: selection == index) }; RoomAudienceBadge(count: room.viewerCount) }
                                        Spacer(minLength: 12)
                                        Text(room.title).font(.outfit(size: 17, weight: .bold)).lineLimit(2)
                                            .frame(maxWidth: geometry.size.width * 0.64, alignment: .leading)
                                        Text("Find your next favorite look").font(.tutuCaption).lineLimit(2)
                                            .frame(maxWidth: geometry.size.width * 0.58, alignment: .leading)
                                        Text("Watch Now").font(.outfit(size: 13, weight: .semibold))
                                            .padding(.horizontal, 20).frame(height: 36)
                                            .background { Image("button-base").resizable() }.padding(.top, 4)
                                    }.foregroundStyle(.white)
                                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                }.clipped()
                            }
                        }.buttonStyle(.plain).tag(index)
                            .accessibilityLabel("\(room.title), Watch Now")
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 5) {
                    ForEach(rooms.indices, id: \.self) { index in
                        Capsule().fill(.white.opacity(selection == index ? 1 : 0.45))
                            .frame(width: selection == index ? 14 : 5, height: 5)
                    }
                }.padding(.bottom, 12).allowsHitTesting(false).accessibilityHidden(true)
            }
            .frame(height: 208).clipShape(RoundedRectangle(cornerRadius: 18))
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in lastInteraction = Date() })
            .onAppear { visible = true; lastInteraction = Date() }
            .onDisappear { visible = false }
            .onChange(of: rooms.map(\.id)) { _, _ in selection = 0; lastInteraction = Date() }
            .task(id: "\(canRotate)-" + rooms.map(\.id).joined(separator: ",")) {
                guard canRotate else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    guard !Task.isCancelled, canRotate else { return }
                    if Date().timeIntervalSince(lastInteraction) >= 4 {
                        withAnimation(.easeInOut(duration: 0.45)) { selection = (selection + 1) % rooms.count }
                    }
                }
            }
        }
    }
}

struct RoomAudienceBadge: View {
    let count: Int?
    var body: some View {
        HStack(spacing: 3) {
            Text(count.map { $0.formatted() } ?? "—").monospacedDigit()
            Text("viewers")
        }.font(.outfit(size: 10, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.38), in: Capsule())
            .accessibilityLabel(count.map { "\($0) viewers" } ?? "Viewer count unavailable")
    }
}
struct RoomCard: View {
    @EnvironmentObject private var store: AppStore
    let room: StyleRoom
    var party = false
    var body: some View {
        NavigationLink(value: Route.room(room.id)) {
            ZStack(alignment: .bottomLeading) {
                MediaArtwork(reference: party ? store.person(room.hostID).avatar : room.cover, alignment: .top)
                if party {
                    VStack {
                        HStack {
                            if room.isBroadcasting == true { RoomLiveBadge() }
                            Spacer(minLength: 4)
                            Text("Voice").font(.outfit(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.pink).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(.white.opacity(0.94), in: Capsule())
                        }
                        Spacer()
                    }.padding(9)
                }
                if !party {
                    VStack {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                if room.isBroadcasting == true { RoomLiveBadge() }
                                Spacer(minLength: 0)
                                RoomAudienceBadge(count: room.viewerCount).fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                if room.isBroadcasting == true { RoomLiveBadge() }
                                RoomAudienceBadge(count: room.viewerCount).fixedSize()
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer()
                    }.padding(8)
                }
                VStack(alignment: party ? .center : .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(store.person(room.hostID).name).font(.outfit(size: 16, weight: .semibold, design: .rounded)).lineLimit(1)
                        if !party { PersonGenderMark(person: store.person(room.hostID)) }
                    }.frame(maxWidth: .infinity, alignment: party ? .center : .leading)
                    Text(room.title).font(.outfit(size: 11, design: .rounded)).lineLimit(1)
                    if party {
                        (room.viewerCount.map { Text("\($0) in room") } ?? Text("Join the conversation"))
                            .font(.outfit(size: 11)).lineLimit(1)
                        Artwork(name: "button-join").frame(height: 30).padding(.top, 3)
                    }
                }.foregroundStyle(.white)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: party ? 220 : 180).clipShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
struct PartyHomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var relation = "Explore"
    @State private var filter = "All"
    var filtered: [StyleRoom] {
        let matches = store.rooms.filter { room in
            guard room.voice else { return false }
            let follows = store.state?.following.contains(room.hostID) ?? false
            let follower = store.followerIDs.contains(room.hostID)
            let relationMatches = relation == "Explore" || relation == "Popular" || (relation == "Following" ? follows : follower)
            let topicMatches = filter == "All" || room.conversationTopic == filter
            return relationMatches && topicMatches
        }
        return relation == "Popular" ? matches.sorted {
            let left = $0.viewerCount ?? 0, right = $1.viewerCount ?? 0
            return left == right ? $0.id < $1.id : left > right
        } : matches
    }
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-party") {
                HStack(spacing: 2) {
                    NavArt(route: .search, asset: "nav-search", label: "Search")
                    InboxEntryButton()
                }
            }
            SectionTabs(titles: ["Explore", "Popular", "Following", "Followers"], selection: $relation, compact: true)
            ScrollView {
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(VoiceRoomTopics.filters, id: \.self) { choice in
                                Button { filter = choice } label: {
                                    Text(ui: choice).font(.outfit(size: 13, weight: filter == choice ? .semibold : .medium))
                                        .foregroundStyle(filter == choice ? Color.white : Palette.secondary)
                                        .padding(.horizontal, 16).frame(height: 34)
                                        .background {
                                            if filter == choice { Image("button-base").resizable() }
                                            else { Color.white.opacity(0.88) }
                                        }
                                        .clipShape(Capsule())
                                        .overlay { if filter != choice { Capsule().strokeBorder(Palette.pink.opacity(0.15), lineWidth: 1) } }
                                        .fixedSize(horizontal: true, vertical: false)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(filter == choice ? [.isSelected] : [])
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filtered) { RoomCard(room: $0, party: true) }
                    }
                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            EmptyState(title: "No voice rooms here", message: filter != "All" ? "Try All to see more rooms in this list." : relation == "Following" ? "Voice rooms hosted by people you follow will appear here." : relation == "Followers" ? "Voice rooms hosted by people who follow you will appear here." : "Check back for more style conversations.")
                            if filter != "All" || relation != "Explore" {
                                Button("Explore all voice rooms") { relation = "Explore"; filter = "All" }
                                    .font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44)
                            }
                        }.padding(.top, 36)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }.onChange(of: relation) { _, _ in filter = "All" }
    }
}
struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var section = "Users"
    @State private var country = "All"
    @State private var gender = "All"
    @State private var language = "All"
    @State private var age = "All"
    @State private var filters = false
    var users: [Person] {
        store.people.filter { person in
            let matches = query.isEmpty || (person.name + person.handle + person.interests.joined()).localizedCaseInsensitiveContains(query)
            let matchesAge = age == "All" || (age == "18–24" ? (18...24).contains(person.age) : age == "25–34" ? (25...34).contains(person.age) : person.age >= 35)
            return matches && matchesAge && (country == "All" || person.country == country) && (gender == "All" || person.gender == gender) && (language == "All" || person.language == language)
        }
    }
    var matchingIDs: Set<String> { Set(users.map(\.id)) }
    var body: some View {
        Page(title: "Search") {
            VStack(spacing: 14) {
                HStack { TextField("People, rooms and looks", text: $query).submitLabel(.search).padding(14).background(.white, in: Capsule()); Button("Filters") { filters = true }.font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44) }.padding(.horizontal, 16)
                SectionTabs(titles: ["Users", "Rooms", "Posts"], selection: $section)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if section == "Users" {
                            ForEach(users) { person in PersonRow(person: person) }
                            if users.isEmpty { EmptyState(title: "No people found", message: "Try another name or clear your filters.") }
                        } else if section == "Rooms" {
                            let rooms = store.rooms.filter { room in matchesProfile(room.hostID) && (query.isEmpty || room.title.localizedCaseInsensitiveContains(query) || store.person(room.hostID).name.localizedCaseInsensitiveContains(query)) }
                            ForEach(rooms) { room in NavigationLink(value: Route.room(room.id)) { HStack { Avatar(person: store.person(room.hostID)); VStack(alignment: .leading, spacing: 5) { Text(room.title).font(.tutuHeadline); Text(ui: room.voice ? "Voice room" : "Style live").font(.tutuCaption).foregroundStyle(Palette.secondary) }; Spacer(); if room.isBroadcasting == true { RoomLiveBadge() } }.panel() }.buttonStyle(.plain) }
                            if rooms.isEmpty { EmptyState(title: "No rooms found") }
                        } else {
                            let posts = store.looks.filter { matchesProfile($0.authorID) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)) }
                            ForEach(posts) { post in LookRow(look: post) }
                            if posts.isEmpty { EmptyState(title: "No posts found") }
                        }
                    }.padding(16)
                }.scrollDismissesKeyboard(.interactively)
            }
        }.sheet(isPresented: $filters) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Find your people").font(.tutuTitle2.bold()); Spacer(); ArtButton(label: "Close filters", asset: "nav-close") { filters = false } }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        filterGroup("Age", choices: ["All", "18–24", "25–34", "35+"], value: $age)
                        filterGroup("Gender", choices: ["All", "Woman", "Man", "Nonbinary"], value: $gender)
                        filterGroup("Country or region", choices: ["All", "United States", "United Kingdom", "Canada", "Australia", "France", "Germany"], value: $country)
                        filterGroup("Language", choices: ["All", "English", "French", "German"], value: $language)
                    }
                }
                Button("Clear filters") { country = "All"; gender = "All"; language = "All"; age = "All" }.foregroundStyle(Palette.pink)
                PinkButton(title: "Show results") { filters = false }
            }.padding(22).background(Palette.blush).presentationDetents([.large])
        }
    }
    func matchesProfile(_ id: String) -> Bool {
        let p = store.person(id)
        let ageMatch = age == "All" || (age == "18–24" ? (18...24).contains(p.age) : age == "25–34" ? (25...34).contains(p.age) : p.age >= 35)
        return ageMatch && (country == "All" || p.country == country) && (gender == "All" || p.gender == gender) && (language == "All" || p.language == language)
    }
    func filterGroup(_ title: String, choices: [String], value: Binding<String>) -> some View { VStack(alignment: .leading) { Text(ui: title).font(.tutuHeadline); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(choices, id: \.self) { item in Pill(title: item, selected: item == value.wrappedValue) { value.wrappedValue = item } } } } } }
}
struct PersonRow: View {
    @EnvironmentObject private var store: AppStore
    let person: Person
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.profile(person.id)) { HStack { Avatar(person: person); VStack(alignment: .leading, spacing: 4) { Text(person.name).font(.tutuHeadline); Text(person.country).font(.tutuCaption).foregroundStyle(Palette.secondary).lineLimit(1) } }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            FollowButton(personID: person.id)
        }.panel()
    }
}
struct RelationshipView: View {
    @EnvironmentObject private var store: AppStore
    let kind: String
    var ids: Set<String> {
        let saved = kind == "Following" ? store.state?.following ?? [] : store.followerIDs
        return Set(saved.filter { !store.isPersonHidden($0) })
    }
    var body: some View { Page(title: kind) { ScrollView { LazyVStack(spacing: 12) { ForEach(store.people.filter { ids.contains($0.id) }) { PersonRow(person: $0) }; if ids.isEmpty { EmptyState(title: kind == "Following" ? "Find your people" : "Your circle starts here", message: "Connections will appear here.") } }.padding(16) } } }
}
struct LookRow: View {
    @EnvironmentObject private var store: AppStore
    let look: Look
    var body: some View {
        NavigationLink(value: Route.post(look.id)) { HStack(spacing: 14) { MediaArtwork(reference: look.media.first ?? "wardrobe-placeholder").frame(width: 76, height: 88).clipShape(RoundedRectangle(cornerRadius: 14)); VStack(alignment: .leading, spacing: 6) { Text(store.person(look.authorID).name).font(.tutuHeadline); Text(look.text).font(.tutuSubheadline).lineLimit(3).foregroundStyle(Palette.secondary) }; Spacer(minLength: 0) }.panel() }.buttonStyle(.plain)
    }
}
