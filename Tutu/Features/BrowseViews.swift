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
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-style-live") {
                HStack(spacing: 2) {
                    NavArt(route: .leaderboard, asset: "icon-trophy", label: "Leaderboard")
                    NavArt(route: .createRoom, asset: "nav-create", label: "Create room")
                    NavArt(route: .search, asset: "nav-search", label: "Search")
                }
            }
            ScrollView {
                VStack(spacing: 4) {
                    if let room = store.rooms.first {
                        NavigationLink(value: Route.room(room.id)) {
                            ZStack(alignment: .bottomLeading) {
                                MediaArtwork(reference: room.cover).frame(height: 208)
                                Color.black.opacity(0.23)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(room.title).font(.outfit(size: 16, weight: .bold, design: .rounded))
                                    Text("Which look feels like you?").font(.outfit(size: 12, design: .rounded))
                                    Text("Open room").font(.outfit(size: 12, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 18).frame(height: 32)
                                        .background { Image("button-base").resizable() }.padding(.top, 4)
                                }.foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 2, y: 1).padding(14)
                            }.frame(height: 208).clipShape(RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).padding(.horizontal, 16)
                    }
                    SectionTabs(titles: ["All", "Pop", "Singing", "Acoustic", "K-Pop"], selection: $category, compact: true)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(store.rooms.filter { category == "All" || $0.category == category }) { room in RoomCard(room: room) }
                    }.padding(.horizontal, 16)
                    if store.rooms.filter({ category == "All" || $0.category == category }).isEmpty {
                        EmptyState(title: "No rooms here yet", message: "Try another category or create your own.")
                    }
                }.padding(.bottom, 16)
            }
        }
    }
}
struct RoomCard: View {
    @EnvironmentObject private var store: AppStore
    let room: StyleRoom
    var party = false
    var body: some View {
        NavigationLink(value: Route.room(room.id)) {
            ZStack(alignment: .bottomLeading) {
                MediaArtwork(reference: room.cover)
                Color.black.opacity(0.26)
                VStack(alignment: party ? .center : .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(store.person(room.hostID).name).font(.outfit(size: 16, weight: .semibold, design: .rounded))
                        if !party { PersonGenderMark(person: store.person(room.hostID)) }
                    }.frame(maxWidth: .infinity, alignment: party ? .center : .leading)
                    Text(room.title).font(.outfit(size: 11, design: .rounded)).lineLimit(1)
                    if party { Artwork(name: "button-join").frame(height: 30).padding(.top, 3) }
                }.foregroundStyle(.white).shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: party ? 220 : 180).clipShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
struct PartyHomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var relation = "Friends"
    @State private var filter = "All"
    var filtered: [StyleRoom] {
        store.rooms.filter { room in
            let follows = store.state?.following.contains(room.hostID) ?? false
            let follower = store.state?.followers.contains(room.hostID) ?? false
            let relationMatches = relation == "Friends" ? follows && follower : relation == "Following" ? follows : follower
            let availabilityMatches = filter == "All" || (filter == "Online" ? store.person(room.hostID).isOnline == true : room.isBroadcasting == true)
            return relationMatches && availabilityMatches
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-party") { NavArt(route: .search, asset: "nav-search", label: "Search") }
            SectionTabs(titles: ["Friends", "Following", "Follower"], selection: $relation, compact: true)
            ScrollView {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ForEach(["All", "Online", "Live Now"], id: \.self) { choice in
                            Button { filter = choice } label: {
                                Text(choice).font(.outfit(size: 13, design: .rounded))
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .foregroundStyle(filter == choice ? .white : Palette.secondary)
                                    .background {
                                        if filter == choice { Image("button-base").resizable() }
                                        else { Palette.blush.clipShape(Capsule()) }
                                    }.frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityAddTraits(filter == choice ? [.isSelected] : [])
                        }
                        Spacer(minLength: 0)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filtered) { RoomCard(room: $0, party: true) }
                    }
                    if filtered.isEmpty {
                        EmptyState(title: filter == "All" ? "No rooms yet" : "No rooms available", message: filter == "All" ? "Explore Style Live to find people to follow." : "Try All to see your circle's rooms.")
                            .padding(.top, 70)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
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
                            ForEach(rooms) { room in NavigationLink(value: Route.room(room.id)) { HStack { Avatar(person: store.person(room.hostID)); VStack(alignment: .leading, spacing: 5) { Text(room.title).font(.tutuHeadline); Text(room.voice ? "Voice room" : "Style live").font(.tutuCaption).foregroundStyle(Palette.secondary) }; Spacer() }.panel() }.buttonStyle(.plain) }
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
    func filterGroup(_ title: String, choices: [String], value: Binding<String>) -> some View { VStack(alignment: .leading) { Text(title).font(.tutuHeadline); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(choices, id: \.self) { item in Pill(title: item, selected: item == value.wrappedValue) { value.wrappedValue = item } } } } } }
}
struct PersonRow: View {
    @EnvironmentObject private var store: AppStore
    let person: Person
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.profile(person.id)) { HStack { Avatar(person: person); VStack(alignment: .leading, spacing: 4) { Text(person.name).font(.tutuHeadline); Text(person.country).font(.tutuCaption).foregroundStyle(Palette.secondary).lineLimit(1) } }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            ArtButton(label: store.state?.following.contains(person.id) == true ? "Unfollow" : "Follow", asset: store.state?.following.contains(person.id) == true ? "control-selected" : "control-follow") { store.toggleFollow(person.id) }
        }.panel()
    }
}
struct RelationshipView: View {
    @EnvironmentObject private var store: AppStore
    let kind: String
    var ids: Set<String> { kind == "Following" ? store.state?.following ?? [] : store.state?.followers ?? [] }
    var body: some View { Page(title: kind) { ScrollView { LazyVStack(spacing: 12) { ForEach(store.people.filter { ids.contains($0.id) }) { PersonRow(person: $0) }; if ids.isEmpty { EmptyState(title: kind == "Following" ? "Find your people" : "Your circle starts here", message: "Connections will appear here.") } }.padding(16) } } }
}
struct LookRow: View {
    @EnvironmentObject private var store: AppStore
    let look: Look
    var body: some View {
        NavigationLink(value: Route.post(look.id)) { HStack(spacing: 14) { MediaArtwork(reference: look.media.first ?? "wardrobe-placeholder").frame(width: 76, height: 88).clipShape(RoundedRectangle(cornerRadius: 14)); VStack(alignment: .leading, spacing: 6) { Text(store.person(look.authorID).name).font(.tutuHeadline); Text(look.text).font(.tutuSubheadline).lineLimit(3).foregroundStyle(Palette.secondary) }; Spacer(minLength: 0) }.panel() }.buttonStyle(.plain)
    }
}
