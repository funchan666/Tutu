import SwiftUI

struct ProfileStats: View {
    @EnvironmentObject private var store: AppStore
    let person: Person
    var isMe: Bool { person.id == store.me.id }
    var body: some View {
        HStack(spacing: 0) {
            stat(isMe ? store.state?.followers.count ?? 0 : 12 + (Catalog.people.firstIndex(where: { $0.id == person.id }) ?? 0) * 7 + (store.state?.following.contains(person.id) == true ? 1 : 0), "Follower", route: isMe ? .relationships("Follower") : nil)
            Divider().frame(height: 26)
            stat(isMe ? store.state?.following.count ?? 0 : 8 + (Catalog.people.firstIndex(where: { $0.id == person.id }) ?? 0) * 3, "Following", route: isMe ? .relationships("Following") : nil)
            Divider().frame(height: 26)
            stat(isMe ? store.state?.likedLooks.count ?? 0 : 0, "Likes", route: nil)
        }.padding(.vertical, 12)
    }
    func stat(_ count: Int, _ name: String, route: Route?) -> some View {
        Group {
            if let route { NavigationLink(value: route) { label(count, name) }.buttonStyle(.plain) }
            else { label(count, name) }
        }.frame(maxWidth: .infinity)
    }
    func label(_ count: Int, _ name: String) -> some View { VStack(spacing: 7) { Text(count.formatted()).font(.outfit(size: 16, weight: .bold, design: .rounded)); Text(name).font(.outfit(size: 12, design: .rounded)).foregroundStyle(Palette.secondary) } }
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
        section == "Likes" ? store.looks.filter { store.state?.likedLooks.contains($0.id) == true } : store.looks.filter { $0.authorID == store.me.id }
    }
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-profile") {
                HStack(spacing: 2) {
                    NavArt(route: .atelier, asset: "runway-frame", label: "Style Atelier")
                    NavArt(route: .inbox, asset: "nav-more", label: "Messages")
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
                    Artwork(name: "profile-shortcuts")
                        .overlay {
                            HStack(spacing: 0) {
                                shortcut("Get Coins", route: .wallet)
                                shortcut("Backpack", route: .shop(true))
                                shortcut("My Level", route: .info("My Level"))
                                shortcut("Daily Check", route: .checkin)
                            }
                        }
                    HStack {
                        CoinLabel(amount: store.state?.coins ?? 0)
                        Spacer()
                        Text(store.state?.checkinDates.contains(AppStore.dayKey(Date())) == true ? "Checked in today" : "A little reward awaits")
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
    @State private var gifts = false
    var person: Person { store.person(personID) }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .top) {
                        MediaArtwork(reference: person.photos.first ?? "wardrobe-placeholder").frame(height: 350)
                        HStack { ArtButton(label: "Back", asset: "nav-back") { dismiss() }; Spacer(); ArtButton(label: "More", asset: "nav-more") { more = true } }.padding(16)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) { HStack { Text(person.name).font(.tutuTitle2.bold()); PersonGenderMark(person: person); if person.birthday != nil { Text("\(person.age)").font(.tutuCaption) }; Spacer() }; Text("@" + person.handle).font(.tutuSubheadline); Text(person.location).font(.tutuCaption) }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.blush, in: RoundedRectangle(cornerRadius: 18))
                        Text(person.bio).font(.tutuSubheadline).fixedSize(horizontal: false, vertical: true)
                        InterestTags(values: person.interests)
                        ProfileStats(person: person)
                        if let room = store.rooms.first(where: { $0.hostID == personID }) { NavigationLink(value: Route.room(room.id)) { Artwork(name: room.voice ? "voice-banner" : "live-banner").frame(height: 52) }.buttonStyle(.plain) }
                        SectionTabs(titles: ["Posts", "Photo album"], selection: $section).padding(.horizontal, -16)
                        if store.state?.blocked.contains(personID) == true { EmptyState(title: "This member is blocked", message: "You can manage blocked members in Privacy settings.") }
                        else if section == "Posts" {
                            let posts = store.looks.filter { $0.authorID == personID }
                            ForEach(posts) { LookRow(look: $0) }
                            if posts.isEmpty { EmptyState(title: "No posts yet") }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) { ForEach(Array(person.photos.enumerated()), id: \.offset) { i, ref in NavigationLink(value: Route.album(personID, i)) { MediaArtwork(reference: ref).frame(height: 138).clipShape(RoundedRectangle(cornerRadius: 14)) } } }
                            if person.photos.isEmpty { EmptyState(title: "No photos yet") }
                        }
                    }.padding(16).background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)).padding(.top, -24)
                }
            }
            HStack(spacing: 10) {
                FollowButton(personID: personID)
                NavigationLink(value: Route.chat(personID)) { Text("Start a Chat").font(.tutuHeadline).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50).background { Image("button-base").resizable() } }.buttonStyle(.plain)
                ArtButton(label: "Send a gift", asset: "icon-gift") { gifts = true }
            }.padding(.horizontal, 16).padding(.vertical, 8).background(.white)
        }.background(Palette.blush).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $more) { MemberActions(targetID: personID, authorID: personID, kind: "member") }
            .sheet(isPresented: $gifts) { GiftDeliveryView(personID: personID) }
            .moderationVisibility(hidden: store.isPersonHidden(personID))
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
                    if !error.isEmpty { Text(error).foregroundStyle(.red).font(.tutuSubheadline) }
                    PinkButton(title: "Save", asset: "button-save") { save() }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
        }.onAppear { if person == nil { person = store.me; name = store.me.name; bio = store.me.bio; country = store.me.country; gender = store.me.gender; tags = Set(store.me.interests); birthday = store.me.birthday.map(AppStore.dayKey) ?? "" } }
            .sheet(isPresented: $media) { MediaSourceView { item in do { let ref = try store.importMedia(item); person?.avatar = ref.reference } catch { self.error = error.localizedDescription } } }
    }
    func choice(_ name: String, values: [String], selection: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 12) { Text(name).font(.tutuHeadline); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(values, id: \.self) { value in Pill(title: value, selected: value == selection.wrappedValue) { selection.wrappedValue = value } } } } } }
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


/// Compact live-room business card. Profile and album navigation happen after dismissal.
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
            Text(title).font(.outfit(size: 15, weight: .semibold))
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
