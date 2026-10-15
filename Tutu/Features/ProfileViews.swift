import SwiftUI

struct ProfileStats: View {
    @EnvironmentObject private var store: AppStore
    let person: Person
    var isMe: Bool { person.id == store.me.id }
    private var receivedLikes: Int {
        store.looks.filter { $0.authorID == person.id }.reduce(0) { $0 + store.likeCount(for: $1) }
    }
    var body: some View {
        HStack(spacing: 0) {
            stat(isMe ? store.followerIDs.count : (Catalog.snapshot?.settings.counters[person.id]?.followers ?? 0) + (store.state?.following.contains(person.id) == true ? 1 : 0), "Follower", route: isMe ? .relationships("Follower") : nil)
            Divider().frame(height: 26)
            stat(isMe ? store.state?.following.count ?? 0 : (Catalog.snapshot?.settings.counters[person.id]?.following ?? 0), "Following", route: isMe ? .relationships("Following") : nil)
            Divider().frame(height: 26)
            stat(isMe ? store.likedLooks.count : receivedLikes, "Likes", route: nil)
        }.padding(.vertical, 12)
    }
    func stat(_ count: Int, _ name: String, route: Route?) -> some View {
        Group {
            if let route { NavigationLink(value: route) { label(count, name) }.buttonStyle(.plain) }
            else { label(count, name) }
        }.frame(maxWidth: .infinity)
    }
    func label(_ count: Int, _ name: String) -> some View { VStack(spacing: 7) { Text(count.formatted()).font(.outfit(size: 16, weight: .bold, design: .rounded)); Text(ui: name).font(.outfit(size: 12, design: .rounded)).foregroundStyle(Palette.secondary) } }
}
extension Array where Element: Equatable { func firstIndex(of element: Element, default fallback: Int) -> Int { firstIndex(of: element) ?? fallback } }
struct InterestTags: View {
    let values: [String]
    var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(values, id: \.self) { Text($0).font(.tutuCaption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 7).background(.white.opacity(0.8), in: Capsule()) } } } }
}
struct PersonGenderMark: View {
    let person: Person
    var body: some View {
        if person.gender == "Woman" || person.gender == "Man" {
            Artwork(name: person.gender == "Man" ? "icon-male" : "icon-female").frame(width: 18, height: 18)
        }
    }
}
struct MyProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var section = "My Looks"
    @State private var media = false
    var posts: [Look] {
        section == "Likes" ? store.likedLooks : store.looks.filter { $0.authorID == store.me.id }
    }
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-profile") {
                HStack(spacing: 2) {
                    NavArt(route: .atelier, asset: "runway-frame", label: "Style Atelier")
                    InboxEntryButton()
                    NavArt(route: .settings, asset: "nav-settings", label: "Settings")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        Avatar(person: store.me, size: 90)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(store.me.name).font(.outfit(size: 17, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                                HStack(spacing: 4) {
                                    PersonGenderMark(person: store.me)
                                    if store.me.birthday != nil { Text("\(store.me.age)").font(.outfit(size: 12, design: .rounded)) }
                                }.padding(.horizontal, 7).padding(.vertical, 4).background(.white.opacity(0.55), in: Capsule())
                            }
                            Text("@" + store.me.handle).font(.outfit(size: 13, design: .rounded)).foregroundStyle(Palette.secondary)
                            Text(store.me.country).font(.outfit(size: 12, design: .rounded)).foregroundStyle(Palette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 4)
                    InterestTags(values: store.me.interests + ["Lv. \(store.state?.level ?? 1)"])
                    ProfileStats(person: store.me)
                    NavigationLink(value: Route.editProfile) {
                        Artwork(name: "button-edit").frame(height: 60).frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("Edit Profile")
                    VStack(spacing: 6) {
                        SectionTabs(titles: ["My Looks", "My Closet", "Likes"], selection: $section, compact: true)
                        profileMedia.frame(height: 158)
                    }
                    if store.appLanguage == .english {
                        Artwork(name: "profile-shortcuts")
                            .overlay {
                                HStack(spacing: 0) {
                                    shortcut("Get Coins", route: .wallet)
                                    shortcut("Backpack", route: .shop(true))
                                    shortcut("My Level", route: .info("My Level"))
                                    shortcut("Daily Check", route: .checkin)
                                }
                            }
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            localizedShortcut("Get Coins", asset: "icon-coin", route: .wallet)
                            localizedShortcut("Backpack", asset: "icon-gift", route: .shop(true))
                            localizedShortcut("My Level", asset: "gift-star", route: .info("My Level"))
                            localizedShortcut("Daily Check", asset: "control-check", route: .checkin)
                        }
                    }
                    HStack {
                        CoinLabel(amount: store.state?.coins ?? 0)
                        Spacer()
                        Text(ui: store.state?.checkinDates.contains(AppStore.dayKey(Date())) == true ? "Checked in today" : "A little reward awaits")
                            .font(.outfit(size: 11, design: .rounded)).foregroundStyle(Palette.secondary)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
        }.sheet(isPresented: $media) {
            MediaSourceView { selection in
                do { let file = try store.importMedia(selection); _ = store.commit { $0.person.photos.append(file.reference) } }
                catch { store.show("Photo not saved", error.localizedDescription) }
            }
        }
    }
    @ViewBuilder var profileMedia: some View {
        if section == "My Closet" {
            if store.me.photos.isEmpty { compactEmpty { Button("Add a photo") { media = true } } }
            else {
                mediaRail {
                    ForEach(Array(store.me.photos.enumerated()), id: \.offset) { index, ref in
                        NavigationLink(value: Route.album(store.me.id, index)) { MediaArtwork(reference: ref).frame(width: 112, height: 148).clipShape(RoundedRectangle(cornerRadius: 13)) }.buttonStyle(.plain)
                    }
                    Button { media = true } label: { Artwork(name: "button-add-photo").frame(width: 112, height: 148) }.buttonStyle(.plain).accessibilityLabel("Add a photo")
                }
            }
        } else if posts.isEmpty {
            compactEmpty {
                if section == "My Looks" { NavigationLink("Create a look", value: Route.compose) }
                else { Text("Tap a heart to keep a look here.") }
            }
        } else {
            mediaRail {
                ForEach(posts) { look in
                    NavigationLink(value: Route.post(look.id)) {
                        MediaArtwork(reference: look.media.first ?? "wardrobe-placeholder").frame(width: 112, height: 148).clipShape(RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).accessibilityLabel(look.text.isEmpty ? "Open look" : look.text)
                }
                if section == "My Looks" { NavigationLink("Create a look", value: Route.compose).frame(width: 100, height: 148).font(.tutuCaption).foregroundStyle(Palette.pink) }
            }
        }
    }
    func mediaRail<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { content() } }
    }
    func compactEmpty<Action: View>(@ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 0) {
            Artwork(name: "empty-state").frame(width: 84, height: 91)
            action().font(.outfit(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Palette.pink).frame(minHeight: 44)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func localizedShortcut(_ title: String, asset: String, route: Route) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 9) {
                Artwork(name: asset).frame(width: 34, height: 34)
                Text(ui: title).font(.tutuCaption).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 86).padding(.vertical, 8)
                .background(Palette.blush, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
    func shortcut(_ name: String, route: Route) -> some View {
        NavigationLink(value: route) { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(name)
    }
}
struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let personID: String
    @State private var section = "Posts"
    @State private var more = false
    private var person: Person { store.person(personID) }
    private var posts: [Look] { store.looks.filter { $0.authorID == personID } }
    private var broadcastingRoom: StyleRoom? {
        store.rooms.first {
            $0.hostID == personID && $0.isBroadcasting == true &&
            ($0.voice || $0.video.flatMap { store.mediaURL($0) } != nil)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(width: geometry.size.width, safeTop: geometry.safeAreaInsets.top)
                        VStack(alignment: .leading, spacing: 24) {
                            identity
                            if !person.bio.isEmpty || !person.interests.isEmpty { introduction }
                            if let room = broadcastingRoom { roomEntry(room) }
                            contentTabs
                            profileContent
                        }
                        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
                        .padding(.top, -30)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .top)
                actionBar
            }
        }
        .foregroundStyle(Palette.ink).background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $more) { MemberActions(targetID: personID, authorID: personID, kind: "member") }
        .moderationVisibility(hidden: store.isPersonHidden(personID))
    }

    private func hero(width: CGFloat, safeTop: CGFloat) -> some View {
        MediaArtwork(reference: person.avatar, alignment: .top)
            .frame(height: width * 1.24)
            .overlay(alignment: .top) {
                HStack {
                    ArtButton(label: "Back", asset: "nav-back", size: 26) { dismiss() }
                        .background(.white.opacity(0.94), in: Circle())
                    Spacer()
                    ArtButton(label: "More", asset: "nav-more", size: 28) { more = true }
                        .background(.white.opacity(0.94), in: Circle())
                }.padding(.horizontal, 18).padding(.top, safeTop + 8)
            }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(person.name).font(.outfit(size: 30, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("@" + person.handle).font(.outfit(size: 14)).foregroundStyle(Palette.secondary)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { demographicBadge; locationLabel }
                VStack(alignment: .leading, spacing: 10) { demographicBadge; locationLabel }
            }
            ProfileStats(person: person)
                .padding(.horizontal, 4)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Image("profile-background").resizable().scaledToFill()
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var demographicBadge: some View {
        if person.age > 0 || !person.gender.isEmpty {
            HStack(spacing: 5) {
                PersonGenderMark(person: person)
                if person.age > 0 { Text(String(person.age)).monospacedDigit() }
                if !person.gender.isEmpty { Text(ui: person.gender) }
            }
            .font(.outfit(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.9), in: Capsule())
        }
    }

    @ViewBuilder private var locationLabel: some View {
        if !person.location.isEmpty {
            Text(person.location).font(.outfit(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style notes").font(.outfit(size: 13, weight: .semibold)).foregroundStyle(Palette.pink)
            if !person.bio.isEmpty {
                Text(person.bio).font(.outfit(size: 17)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !person.interests.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(person.interests, id: \.self) { interest in
                        Text(interest).font(.outfit(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Palette.blush, in: Capsule())
                    }
                }
            }
        }
    }

    private func roomEntry(_ room: StyleRoom) -> some View {
        NavigationLink(value: Route.room(room.id)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    RoomLiveBadge(title: room.voice ? "Voice room" : "Live Now")
                    Text(room.title).font(.outfit(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Text("Join").font(.outfit(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background { Image("button-base").resizable() }
            }
            .padding(14).background(Palette.blush, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }

    private var contentTabs: some View {
        HStack(spacing: 6) {
            contentTab("Posts", count: posts.count)
            contentTab("Photo album", count: person.photos.count)
        }.padding(5).background(Palette.blush, in: Capsule())
    }

    private func contentTab(_ title: String, count: Int) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { section = title } } label: {
            HStack(spacing: 6) {
                Text(ui: title).font(.outfit(size: 14, weight: .semibold))
                Text(String(count)).font(.outfit(size: 11, weight: .medium)).monospacedDigit()
            }
            .foregroundStyle(section == title ? Palette.pink : Palette.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(section == title ? Color.white : Color.clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(section == title ? [.isSelected] : [])
    }

    @ViewBuilder private var profileContent: some View {
        if section == "Posts" {
            ForEach(posts) { LookRow(look: $0) }
            if posts.isEmpty { EmptyState(title: "No posts yet") }
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(person.photos.enumerated()), id: \.offset) { index, reference in
                    NavigationLink(value: Route.album(personID, index)) {
                        MediaArtwork(reference: reference, alignment: .top)
                            .aspectRatio(0.78, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityLabel("View photo \(index + 1)")
                }
            }
            if person.photos.isEmpty { EmptyState(title: "No photos yet") }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            FollowButton(personID: personID, size: 50)
            NavigationLink(value: Route.chat(personID)) {
                Text("Start a Chat").font(.tutuHeadline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(minHeight: 50)
                    .background { Image("button-base").resizable() }
            }.buttonStyle(.plain)
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.white)
    }
}
struct EditProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var person: Person?
    @State private var name = ""
    @State private var bio = ""
    @State private var birthday = ""
    @State private var country = "United States"
    @State private var gender = "Woman"
    @State private var tags = Set<String>()
    @State private var media = false
    @State private var error = ""
    var body: some View {
        Page(title: "Edit Profile") {
            ScrollView {
                VStack(spacing: 20) {
                    Button { media = true } label: { VStack(spacing: 10) { Avatar(person: person ?? store.me, size: 96); Text("Change photo").font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink) } }.buttonStyle(.plain)
                    Field(title: "Nickname", text: $name)
                    Field(title: "Birthday · YYYY-MM-DD", text: $birthday).keyboardType(.numbersAndPunctuation)
                    choice("Country or region", values: ["United States", "United Kingdom", "Canada", "Australia", "France", "Germany", "Other"], selection: $country)
                    choice("Gender", values: ["Woman", "Man", "Nonbinary", "Prefer not to say"], selection: $gender)
                    VStack(alignment: .leading, spacing: 12) { Text("Your interests").font(.tutuHeadline); LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) { ForEach(["Minimalist", "Streetwear", "Vintage", "Music", "Travel", "Style", "Pop", "Singing"], id: \.self) { tag in Pill(title: tag, selected: tags.contains(tag)) { if tags.contains(tag) { tags.remove(tag) } else if tags.count < 5 { tags.insert(tag) } } } } }
                    VStack(alignment: .leading) { Text("About you").font(.tutuHeadline); TextEditor(text: $bio).frame(height: 110).padding(10).scrollContentBackground(.hidden).background(.white, in: RoundedRectangle(cornerRadius: 16)); Text("\(bio.count)/300").font(.tutuCaption).foregroundStyle(Palette.secondary) }
                    if !error.isEmpty { Text(ui: error).foregroundStyle(.red).font(.tutuSubheadline) }
                    PinkButton(title: "Save", asset: "button-save") { save() }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
        }.onAppear { if person == nil { person = store.me; name = store.me.name; bio = store.me.bio; country = store.me.country; gender = store.me.gender; tags = Set(store.me.interests); birthday = store.me.birthday.map(AppStore.dayKey) ?? "" } }
            .sheet(isPresented: $media) {
                MediaSourceView(title: "Your profile photo", avatarPerson: person ?? store.me) { item in
                    do { let ref = try store.importMedia(item); person?.avatar = ref.reference }
                    catch { self.error = error.localizedDescription }
                }
            }
    }
    func choice(_ name: String, values: [String], selection: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 12) { Text(ui: name).font(.tutuHeadline); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(values, id: \.self) { value in Pill(title: value, selected: value == selection.wrappedValue) { selection.wrappedValue = value } } } } } }
    func save() {
        let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        guard let dob = format.date(from: birthday), format.string(from: dob) == birthday, let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year, (18...110).contains(age) else { error = "Enter a valid birthday. You must be 18 or older."; return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40, bio.count <= 300 else { error = "Use a name of 1–40 characters and an introduction under 300 characters."; return }
        guard var p = person else { return }
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines); p.bio = bio; p.birthday = dob; p.country = country; p.gender = gender; p.interests = tags.sorted()
        if store.commit({ $0.person = p }) { dismiss() }
    }
}
struct AlbumView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let personID: String
    let initialIndex: Int
    @State private var index = 0
    @State private var report: ReportTarget?
    var person: Person { store.person(personID) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { ArtButton(label: "Back", asset: "nav-back") { dismiss() }; Spacer(); Text("\(person.photos.isEmpty ? 0 : index + 1) / \(person.photos.count)").font(.tutuHeadline); Spacer(); if personID != store.me.id { ArtButton(label: "More", asset: "nav-more") { if person.photos.indices.contains(index) { report = ReportTarget(id: person.photos[index], author: personID, kind: "photo") } } } else { Color.clear.frame(width: 44, height: 44) } }.padding(12).background(Palette.blush)
            if person.photos.isEmpty { EmptyState(title: "No photos yet").frame(maxHeight: .infinity) }
            else { TabView(selection: $index) { ForEach(Array(person.photos.enumerated()), id: \.offset) { i, reference in MediaArtwork(reference: reference, mode: .fit).tag(i) } }.tabViewStyle(.page(indexDisplayMode: .never)) }
            HStack { NavigationLink(value: Route.profile(personID)) { HStack { Avatar(person: person, size: 38); Text(person.name).font(.tutuHeadline) } }.buttonStyle(.plain); Spacer(); if personID != store.me.id { FollowButton(personID: personID) } }.padding(16).background(Palette.blush)
        }.background(Color.black).toolbar(.hidden, for: .navigationBar).onAppear { index = min(max(0, initialIndex), max(0, person.photos.count - 1)) }.sheet(item: $report) { MemberActions(targetID: $0.id, authorID: $0.author, kind: $0.kind) }
            .onChange(of: person.photos) { _, photos in index = min(index, max(0, photos.count - 1)) }
            .moderationVisibility(hidden: store.isPersonHidden(personID))
    }
}


struct RoomHostCard: View {
    @EnvironmentObject private var store: AppStore
    let personID: String
    let onClose: () -> Void
    let onProfile: () -> Void
    let onMessage: () -> Void
    let onPhoto: (Int) -> Void
    private var person: Person { store.person(personID) }
    private var photos: [String] { Array(person.photos.prefix(3)) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    identity
                    if !person.bio.isEmpty {
                        Text(person.bio).font(.outfit(size: 13)).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    InterestTags(values: person.interests)
                    ProfileStats(person: person)
                    if !photos.isEmpty { photoStrip }
                }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 8)
            }.scrollIndicators(.hidden)
            HStack(spacing: 10) {
                FollowButton(personID: personID, size: 48)
                cardButton("Profile", primary: false, action: onProfile)
                if personID != store.me.id {
                    cardButton("Message", primary: true, action: onMessage)
                }
            }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
        }
        .background {
            GeometryReader { geometry in
                Image("profile-background").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .overlay(alignment: .topTrailing) {
            ArtButton(label: "Close profile card", asset: "nav-close", size: 24, action: onClose).padding(4)
        }
    }
    private var identity: some View {
        HStack(alignment: .center, spacing: 12) {
            Avatar(person: person, size: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text(person.name).font(.outfit(size: 21, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text("@" + person.handle).font(.outfit(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                if person.age > 0 || !person.gender.isEmpty {
                    HStack(spacing: 5) {
                        PersonGenderMark(person: person)
                        Text([person.age > 0 ? String(person.age) : "", person.gender].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.outfit(size: 12, weight: .medium))
                    }.padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.75), in: Capsule())
                }
                if !person.location.isEmpty {
                    Text(person.location).font(.outfit(size: 12)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.trailing, 24)
    }
    private var photoStrip: some View {
        GeometryReader { geometry in
            let width = max(0, (geometry.size.width - CGFloat(photos.count - 1) * 10) / CGFloat(photos.count))
            HStack(spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    Button { onPhoto(index) } label: {
                        MediaArtwork(reference: photo, alignment: .top)
                            .frame(width: width, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityLabel("View photo \(index + 1)")
                }
            }
        }.frame(height: 110)
    }
    private func cardButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(ui: title).font(.outfit(size: 15, weight: .semibold))
                .foregroundStyle(primary ? Color.white : Palette.pink)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background {
                    if primary { Image("button-base").resizable() }
                    else { Color.white.opacity(0.85) }
                }
                .clipShape(Capsule())
                .overlay { if !primary { Capsule().strokeBorder(Palette.pink.opacity(0.65), lineWidth: 1) } }
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}
