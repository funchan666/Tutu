import SwiftUI

struct RoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    let room: StyleRoom
    @StateObject private var camera = CameraService()
    @State private var message = ""
    @State private var gifts = false
    @State private var settings = false
    @State private var members = false
    @State private var report = false
    @State private var type = "Voice"
    @State private var microphone = false
    @State private var video = false
    @State private var invitation = false
    var host: Person { store.person(room.hostID) }
    var own: Bool { room.hostID == store.me.id }
    var body: some View {
        ZStack {
            if room.voice { SceneBackground(name: "party-background") }
            else { MediaArtwork(reference: room.cover).ignoresSafeArea() }
            if own && video && camera.ready { CameraSurface(session: camera.capture).ignoresSafeArea() }
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    NavigationLink(value: Route.profile(host.id)) { HStack { Avatar(person: host, size: 42); VStack(alignment: .leading, spacing: 4) { Text(host.name).font(.tutuHeadline); Text(room.title).font(.tutuCaption).lineLimit(1) } } }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if !own { ArtButton(label: "Follow host", asset: store.state?.following.contains(host.id) == true ? "control-selected" : "control-follow", size: 32) { store.toggleFollow(host.id) } }
                    ArtButton(label: "Room members", asset: "tab-profile-active", size: 28) { members = true }
                    ArtButton(label: "Leave room", asset: "nav-close", size: 30) { store.minimizedRoom = nil; camera.stop(); dismiss() }
                }.padding(12).background(.black.opacity(0.4), in: Capsule())
                HStack { NavigationLink(value: Route.leaderboard) { Artwork(name: "lucky-star-banner").frame(width: 140, height: 42) }; Spacer(); ArtButton(label: "Room options", asset: "nav-more") { settings = true } }
                if room.voice {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: type == "Dual Video" ? 2 : 4), spacing: 20) {
                        ForEach(0..<(type == "Single Video" ? 1 : type == "Dual Video" ? 2 : type == "Multi Video" ? 4 : 8), id: \.self) { seat in
                            VStack(spacing: 8) {
                                if seat == 0 { NavigationLink(value: Route.profile(host.id)) { Avatar(person: host, size: 58) }.buttonStyle(.plain) }
                                else { ArtButton(label: "Join seat \(seat + 1)", asset: "icon-mic", size: 54) { store.show("Seat unavailable", "Room audio is not connected. Please try again later.") } }
                                Text(seat == 0 ? host.name : "Mic \(seat+1)").font(.tutuCaption)
                            }.frame(maxWidth: .infinity)
                        }
                    }.padding(16).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 24))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text(own ? "Your room is ready" : "Room unavailable").font(.tutuHeadline)
                    Text(own ? "You can set up your camera and room. Live streaming is unavailable right now." : "This room isn't broadcasting right now. Try again later.").font(.tutuSubheadline)
                    if own { Text(camera.status).font(.tutuCaption); HStack { Button(video ? "Camera off" : "Camera on") { video.toggle(); if video { Task { await camera.start() } } else { camera.stop() } }; Spacer(); Button("Switch camera") { Task { await camera.flip() } }.disabled(!video) }.font(.tutuSubheadline.bold()).frame(minHeight: 44) }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
                HStack(spacing: 10) {
                    TextField("Say something…", text: $message).padding(14).background(.black.opacity(0.4), in: Capsule()).submitLabel(.send).onSubmit { send() }
                    ArtButton(label: "Send room message", asset: "icon-send", size: 36) { send() }
                    if room.voice { ArtButton(label: microphone ? "Mute" : "Unmute", asset: "icon-mic", size: 36) { store.show("Microphone unavailable", "Room audio isn't connected. Your microphone remains off."); microphone = false } }
                    ArtButton(label: "Gifts", asset: "icon-gift", size: 38) { gifts = true }
                }
            }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12).foregroundStyle(.white)
        }.toolbar(.hidden, for: .navigationBar).onAppear { type = room.voice ? "Voice" : "Single Video"; store.minimizedRoom = nil; message = store.state?.drafts["room-" + room.id] ?? "" }.onDisappear { camera.stop(); store.commit { $0.drafts["room-" + room.id] = message.isEmpty ? nil : message } }
            .onChange(of: scene) { _, phase in if phase != .active { camera.stop(); video = false } }
            .sheet(isPresented: $gifts) { GiftDeliveryView(personID: host.id) }
            .sheet(isPresented: $report) { MemberActions(targetID: room.id, authorID: host.id, kind: "room") }
            .sheet(isPresented: $members) { VStack(spacing: 16) { Text("Room members").font(.tutuTitle3.bold()); PersonRow(person: host); Text("No connected participants").font(.tutuSubheadline).foregroundStyle(Palette.secondary) }.padding(24).background(Palette.blush).presentationDetents([.medium]) }
            .sheet(isPresented: $settings) { VStack(spacing: 16) {
                Text("Room options").font(.tutuTitle3.bold())
                if own { SectionTabs(titles: ["Voice", "Single Video", "Dual Video", "Multi Video"], selection: $type) }
                MenuRow(title: "Invite people") { settings = false; invitation = true }
                MenuRow(title: "Minimize room") { camera.stop(); store.minimizedRoom = room; settings = false; dismiss() }
                if !own { MenuRow(title: "Report or block") { settings = false; report = true } }
                MenuRow(title: "Leave room", destructive: true) { camera.stop(); store.minimizedRoom = nil; settings = false; dismiss() }
            }.padding(24).background(Palette.blush).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $invitation) { VStack(spacing: 18) { Text("Invite people").font(.tutuTitle3.bold()); ScrollView { ForEach(store.people.filter { store.state?.following.contains($0.id) == true }) { p in HStack { Avatar(person: p); Text(p.name).font(.tutuHeadline); Spacer(); Button("Invite") { store.show("Invitation not sent", "Room invitations are unavailable. Please try again later.") }.foregroundStyle(Palette.pink) }.padding(12) } }; if store.state?.following.isEmpty != false { EmptyState(title: "Follow someone first") } }.padding(20).background(Palette.blush).presentationDetents([.medium, .large]).overlay { NoticeOverlay() } }
    }
    func send() { guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; store.show("Message not sent", "Room messaging is unavailable. Your message has been kept.") }
}
struct CreateRoomView: View {
    @EnvironmentObject private var store: AppStore
    @State private var title = ""
    @State private var category = "Pop"
    @State private var type = "Live Room"
    @State private var cover = "wardrobe-placeholder"
    @State private var media = false
    @State private var error = ""
    @State private var created: StyleRoom?
    var body: some View {
        Page(title: "Create a room") {
            ScrollView { VStack(spacing: 22) {
                SectionTabs(titles: ["Live Room", "Voice Room"], selection: $type)
                Button { media = true } label: { ZStack(alignment: .bottom) { MediaArtwork(reference: cover).frame(height: 220); Text("Choose a cover").font(.tutuHeadline).padding(14).frame(maxWidth: .infinity).background(.white.opacity(0.85)) }.clipShape(RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain)
                Field(title: "Room name", text: $title)
                SectionTabs(titles: ["Pop", "Singing", "Acoustic", "K-Pop"], selection: $category)
                if !error.isEmpty { Text(error).font(.tutuSubheadline).foregroundStyle(.red) }
                PinkButton(title: "Create Room", asset: "button-create-room") {
                    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 60 else { error = "Give your room a name under 60 characters."; return }
                    let room = StyleRoom(id: UUID().uuidString, hostID: store.me.id, title: title, category: category, voice: type == "Voice Room", cover: cover)
                    if store.commit({ $0.rooms.append(room) }) { created = room }
                }
                Text("Set up your room before going live. No broadcast starts when you create a room.").font(.tutuCaption).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            }.padding(20) }.scrollDismissesKeyboard(.interactively)
        }.sheet(isPresented: $media) { MediaSourceView { item in do { cover = try store.importMedia(item).reference } catch { self.error = error.localizedDescription } } }
            .navigationDestination(item: $created) { RoomView(room: $0) }
    }
}
struct CallView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    let personID: String
    let video: Bool
    @StateObject private var camera = CameraService()
    @State private var started = false
    var body: some View {
        ZStack {
            SceneBackground(name: "party-background")
            if video && camera.ready { CameraSurface(session: camera.capture).ignoresSafeArea() }
            VStack(spacing: 24) {
                HStack { Text(video ? "Video call" : "Voice call").font(.tutuHeadline); Spacer(); ArtButton(label: "Close call", asset: "nav-close") { camera.stop(); dismiss() } }
                Spacer()
                Avatar(person: store.person(personID), size: 94)
                Text(store.person(personID).name).font(.tutuTitle.bold())
                Text(started ? camera.status : "Preparing…").font(.tutuSubheadline).multilineTextAlignment(.center).padding(16).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                Text("No call has connected.").font(.tutuCaption)
                Spacer()
                HStack { if video { Button("Switch camera") { Task { await camera.flip() } } }; Spacer(); Button(camera.microphoneEnabled ? "Mute" : "Unmute") { camera.setMicrophoneEnabled(!camera.microphoneEnabled) }.disabled(!camera.ready) }.font(.tutuSubheadline.bold()).frame(minHeight: 44)
                PinkButton(title: "End call") { camera.stop(); dismiss() }
            }.padding(24).foregroundStyle(.white)
        }.toolbar(.hidden, for: .navigationBar).task {
            guard store.state?.following.contains(personID) == true, store.state?.followers.contains(personID) == true, store.state?.blocked.contains(personID) != true else { store.show("A little connection first", "Follow each other before starting a call."); dismiss(); return }
            await camera.start(video: video); started = true
        }.onDisappear { camera.stop() }.onChange(of: scene) { _, phase in if phase != .active { camera.stop(); dismiss() } }
    }
}
struct LeaderboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var period = "Daily"
    var body: some View {
        Page(title: "Lucky Star") {
            VStack(spacing: 16) {
                Artwork(name: "lucky-star-banner").frame(height: 64).padding(.top, 10)
                SectionTabs(titles: ["Daily", "Weekly", "All time"], selection: $period)
                ScrollView { EmptyState(title: "The next star could be you", message: "Rankings will appear when room activity is available.") }
                HStack { Text("—").font(.tutuTitle3.bold()); Avatar(person: store.me); VStack(alignment: .leading, spacing: 4) { Text(store.me.name).font(.tutuHeadline); Text("Your activity").font(.tutuCaption).foregroundStyle(Palette.secondary) }; Spacer(); Text("\(store.state?.points ?? 0) pts").font(.tutuSubheadline.bold()) }.panel().padding(16)
            }
        }
    }
}
