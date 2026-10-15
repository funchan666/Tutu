import SwiftUI
import AVFoundation

private enum RoomPanel: String, Identifiable {
    case options, members, invitation, report, gifts, hostProfile, messageActions
    var id: String { rawValue }
}
private enum RoomNextAction {
    case panel(RoomPanel), profile(String), chat(String), album(String, Int), minimize, leave, collect(Gift)
}
private enum RoomPersonDestination: Hashable {
    case profile(String), chat(String), album(String, Int)
}
struct RoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let room: StyleRoom
    @ObservedObject private var playback = MoviePlayback.shared
    @StateObject private var camera = CameraService()
    @State private var roomVisible = false
    @State private var resumeVideo = false
    @State private var sessionID: String?
    @State private var message = ""
    @State private var panel: RoomPanel?
    @State private var nextAction: RoomNextAction?
    @State private var personDestination: RoomPersonDestination?
    @State private var type = "Voice"
    @State private var video = false
    @State private var messages: [RoomMessage] = []
    @State private var giftEvent: RoomMessage?
    @State private var selectedMessage: RoomMessage?
    @State private var requestedVoiceSeat: Int?
    @State private var activityStep = 0
    @State private var lastScroll = Date.distantPast
    @FocusState private var composing: Bool
    var host: Person { store.person(room.hostID) }
    var own: Bool { room.hostID == store.me.id }
    var videoURL: URL? { room.video.flatMap { store.mediaURL($0) } }
    // The configured count includes the current viewer, but excludes the host.
    private var audience: [Person] {
        let candidates = store.people.filter { $0.id != room.hostID && $0.id != store.me.id }
        guard !candidates.isEmpty else { return [] }
        let offset = (Catalog.people.firstIndex(where: { $0.id == room.hostID }) ?? 0) % candidates.count
        let ordered = Array(candidates.dropFirst(offset)) + Array(candidates.prefix(offset))
        return Array(ordered.prefix(max(0, (room.viewerCount ?? 1) - (own ? 0 : 1))))
    }
    private var viewers: [Person] { (own ? [] : [store.me]) + audience }
    private var visibleMessages: [RoomMessage] {
        messages.filter { !store.isMessageHidden($0) }
    }
    private var supportsRoomActivity: Bool { room.voice || videoURL != nil }
    private var voiceSeatCount: Int { max(2, min(room.seats, 8)) }
    private var voiceMembers: [Person] {
        // Authored local seat assignments, not a connected audio session.
        let guestCount = 3 + room.id.utf8.reduce(0) { $0 + Int($1) } % 2
        return [host] + Array(audience.prefix(min(guestCount, voiceSeatCount - 2)))
    }
    private var activityRunning: Bool {
        roomVisible && supportsRoomActivity && scene == .active && panel == nil && !composing
            && store.notice == nil && (room.voice || playback.playing)
    }
    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                roomHeader
                HStack {
                    NavigationLink(value: Route.leaderboard) { Artwork(name: "lucky-star-banner").frame(width: 128, height: 38).frame(minHeight: 44) }.buttonStyle(.plain)
                    Spacer()
                    if room.isBroadcasting == true && supportsRoomActivity {
                        RoomLiveBadge(animated: roomVisible && panel == nil)
                    }
                }
                if room.voice && !composing {
                    voiceSeats
                    if requestedVoiceSeat != nil { voiceRequestStatus }
                }
                Spacer(minLength: 8)
                if let event = giftEvent, !store.isMessageHidden(event), let gift = Gift.all.first(where: { $0.id == event.giftID }) {
                    giftBanner(event, gift: gift)
                        .id(event.id)
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                }
                if supportsRoomActivity {
                    messageStream
                    if videoURL != nil, !playback.failure.isEmpty {
                        Text(playback.failure).font(.tutuCaption).padding(10).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                } else { cameraStatus }
                composer
            }
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 10)
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geometry in
                ZStack {
                    if room.voice { SceneBackground(name: "party-background") }
                    else {
                        MediaArtwork(reference: room.cover, alignment: .top)
                        if let url = videoURL, playback.activeURL == url, let player = playback.player {
                            MovieLayer(player: player, fillsFrame: true)
                        }
                    }
                    if own && video && camera.ready { CameraSurface(session: camera.capture) }
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            roomVisible = true; sessionID = store.sessionID
            startRoomVideo(); type = room.voice ? "Voice" : "Single Video"
            store.minimizedRoom = nil
            message = store.state?.drafts["room-" + room.id] ?? ""
            if messages.isEmpty {
                messages = Array((store.state?.roomMessages?[room.id] ?? []).suffix(40))
                if messages.isEmpty, supportsRoomActivity { advanceActivity(); advanceActivity() }
            }
        }
        .onDisappear {
            roomVisible = false; resumeVideo = false; giftEvent = nil
            stopRoomVideo(); camera.stop()
            if store.sessionID == sessionID, !store.isRoomHidden(room) {
                store.commit { $0.drafts["room-" + room.id] = message.isEmpty ? nil : message }
            }
        }
        .onChange(of: scene) { _, phase in
            if phase != .active {
                camera.stop(); video = false
                if let url = videoURL, playback.activeURL == url, playback.playing {
                    resumeVideo = true; playback.toggle()
                }
            } else if roomVisible, resumeVideo { resumeVideo = false; startRoomVideo() }
        }
        .onChange(of: store.state?.blocked) { _, _ in refreshModeration() }
        .onChange(of: store.state?.hiddenContent) { _, _ in refreshModeration() }
        .task(id: activityRunning) {
            guard activityRunning else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4.5)) } catch { return }
                guard !Task.isCancelled, activityRunning else { return }
                if Date().timeIntervalSince(lastScroll) > 6 { advanceActivity() }
            }
        }
        .task(id: giftEvent?.id) {
            guard giftEvent != nil else { return }
            do { try await Task.sleep(for: .seconds(3.6)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { giftEvent = nil }
        }
        .sheet(item: $panel, onDismiss: continueAfterSheet) { current in
            panelContent(current)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .foregroundStyle(Palette.ink)
                .background(current == .members ? Color.white : Palette.blush)
                .presentationBackground(current == .members ? Color.white : Palette.blush)
                .presentationCornerRadius(28)
                .presentationDragIndicator(.hidden)
                .overlay {
                    if current != .report && current != .messageActions && !(current == .gifts && !supportsRoomActivity) { NoticeOverlay() }
                }
        }
        .navigationDestination(item: $personDestination) { destination in
            switch destination {
            case .profile(let id): ProfileView(personID: id)
            case .chat(let id): ChatView(personID: id)
            case .album(let id, let index): AlbumView(personID: id, initialIndex: index)
            }
        }
        .moderationVisibility(hidden: store.isRoomHidden(room))
    }

    private var roomHeader: some View {
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                Button { open(.hostProfile) } label: {
                    HStack(spacing: 7) {
                        Avatar(person: host, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(host.name).font(.outfit(size: 14, weight: .semibold)).lineLimit(1)
                            Text(room.title).font(.outfit(size: 10)).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                if !own {
                    FollowButton(personID: host.id, size: 28)
                }
            }.padding(.leading, 8).padding(.trailing, 2).padding(.vertical, 4)
                .background(.black.opacity(0.28), in: Capsule())
            Button { open(.members) } label: {
                VStack(spacing: 2) {
                    HStack(spacing: -8) { ForEach(Array(audience.prefix(2))) { Avatar(person: $0, size: 20) } }
                    Text(viewers.count.formatted()).font(.outfit(size: 10, weight: .semibold)).monospacedDigit()
                }.frame(width: 50, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Room viewers, \(viewers.count)")
            ArtButton(label: "Room options", asset: "nav-more", size: 34) { open(.options) }
                .background(.white.opacity(0.96), in: Circle())
            ArtButton(label: "Leave room", asset: "nav-close", size: 30) { leaveRoom() }
        }
    }
    private var messageStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleMessages) { item in
                        Group {
                            if item.personID == store.me.id { messageBubble(item) }
                            else {
                                Button {
                                    selectedMessage = item
                                    open(.messageActions)
                                } label: { messageBubble(item).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(store.person(item.personID).name + ": " + item.text)
                                    .accessibilityHint("Report this message or block its sender")
                            }
                        }.id(item.id)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
                .onAppear { if let id = visibleMessages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                .onChange(of: visibleMessages.last?.id) { _, id in
                    if let id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in lastScroll = Date() })
        }.frame(maxWidth: 290).frame(height: composing ? 100 : 156).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func messageBubble(_ item: RoomMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let giftID = item.giftID { Artwork(name: "gift-" + giftID).frame(width: 24, height: 24) }
            (Text(store.person(item.personID).name + "  ").foregroundColor(Color(red: 1, green: 0.70, blue: 0.91)).fontWeight(.semibold) + Text(item.text).foregroundColor(.white))
                .font(.outfit(size: 12)).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
    }
    private func giftBanner(_ event: RoomMessage, gift: Gift) -> some View {
        HStack(spacing: 10) {
            Avatar(person: store.person(event.personID), size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.person(event.personID).name).font(.outfit(size: 13, weight: .semibold))
                Text(gift.name).font(.outfit(size: 11)).foregroundStyle(.white.opacity(0.9))
            }
            Artwork(name: gift.image).frame(width: 58, height: 58)
            Text("×1").font(.outfit(size: 23, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.92))
        }.padding(.horizontal, 12).padding(.vertical, 3)
            .background(Palette.pink.opacity(0.7), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
    private var composer: some View {
        HStack(spacing: 6) {
            TextField("", text: $message, prompt: Text("Say something…").foregroundColor(.white.opacity(0.8)))
                .font(.tutuSubheadline).foregroundStyle(.white).tint(.white)
                .padding(.horizontal, 14).frame(height: 44)
                .background(.black.opacity(0.32), in: Capsule())
                .focused($composing).submitLabel(.send).onSubmit(send)
                .onChange(of: message) { _, value in if value.count > 300 { message = String(value.prefix(300)) } }
                .accessibilityLabel("Room message")
            ArtButton(label: "Send room message", asset: "icon-send", size: 36, action: send)
            if room.voice {
                ArtButton(label: requestedVoiceSeat == nil ? "Request to join a mic" : "Waiting for host approval", asset: "icon-mic", size: 32) {
                    requestVoiceSeat()
                }
            }
            ArtButton(label: "Gifts", asset: "icon-gift", size: 38) { open(.gifts) }
        }
    }
    private var voiceSeats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
            ForEach(0..<voiceSeatCount, id: \.self) { seat in
                VStack(spacing: 7) {
                    if voiceMembers.indices.contains(seat) {
                        let person = voiceMembers[seat]
                        Button {
                            if person.id == host.id { open(.hostProfile) }
                            else { personDestination = .profile(person.id) }
                        } label: { Avatar(person: person, size: 54) }
                            .buttonStyle(.plain).accessibilityLabel("View " + person.name)
                        Text(person.name).font(.tutuCaption).lineLimit(1)
                    } else {
                        ArtButton(label: requestedVoiceSeat == seat ? "Waiting for host approval" : "Request mic \(seat + 1)", asset: "icon-mic", size: 54) {
                            requestVoiceSeat(seat)
                        }
                        (requestedVoiceSeat == seat ? Text("Waiting") : Text("Mic \(seat + 1)"))
                            .font(.tutuCaption).foregroundStyle(requestedVoiceSeat == seat ? Palette.pink : Color.white)
                    }
                }.frame(maxWidth: .infinity)
            }
        }.padding(14).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 24))
    }
    private var voiceRequestStatus: some View {
        HStack(spacing: 8) {
            Text("Waiting for host approval").font(.outfit(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Cancel") { requestedVoiceSeat = nil }
                .font(.outfit(size: 12, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.70, blue: 0.91))
                .frame(minWidth: 44, minHeight: 44)
        }.padding(.horizontal, 12).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }
    private func requestVoiceSeat(_ preferredSeat: Int? = nil) {
        guard room.voice else { return }
        composing = false
        guard !own else { store.show("Host seat", "Your host seat is already assigned."); return }
        if requestedVoiceSeat == nil {
            let seat = preferredSeat ?? voiceMembers.count
            guard seat >= voiceMembers.count, seat < voiceSeatCount else { return }
            requestedVoiceSeat = seat
        }
        guard let seat = requestedVoiceSeat else { return }
        // Waiting UI only: never request microphone access or synthesize host approval.
        store.show("Waiting for host approval", "Mic \(seat + 1) · Your microphone stays off while you wait. You can cancel your request at any time.")
    }
    private var cameraStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: own ? "Your room is ready" : "Room unavailable").font(.tutuHeadline)
            Text(ui: own ? "You can set up your camera and room. Live streaming is unavailable right now." : "This room isn't broadcasting right now. Try again later.").font(.tutuSubheadline)
            if own {
                Text(ui: camera.status).font(.tutuCaption)
                HStack {
                    Button(LocalizedStringKey(video ? "Camera off" : "Camera on")) { video.toggle(); if video { Task { await camera.start() } } else { camera.stop() } }
                    Spacer()
                    Button("Switch camera") { Task { await camera.flip() } }.disabled(!video)
                }.font(.tutuSubheadline.bold()).frame(minHeight: 44)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private func panelContent(_ current: RoomPanel) -> some View {
        switch current {
        case .hostProfile:
            RoomHostCard(personID: host.id, onClose: { panel = nil },
                         onProfile: { finishSheet(with: .profile(host.id)) },
                         onMessage: { finishSheet(with: .chat(host.id)) },
                         onPhoto: { finishSheet(with: .album(host.id, $0)) })
                .presentationDetents([.height(470), .large])
        case .options:
            VStack(spacing: 12) {
                panelHeading("Room options")
                ScrollView {
                    VStack(spacing: 10) {
                        if own { SectionTabs(titles: ["Voice", "Single Video", "Dual Video", "Multi Video"], selection: $type) }
                        MenuRow(title: "Invite people") { finishSheet(with: .panel(.invitation)) }
                        MenuRow(title: "Minimize room") { finishSheet(with: .minimize) }
                        if !own { MenuRow(title: "Report or block") { finishSheet(with: .panel(.report)) } }
                        MenuRow(title: "Leave room", destructive: true) { finishSheet(with: .leave) }
                    }
                }
            }.padding(20).presentationDetents([.height(390), .large])
        case .members:
            viewerPanel
                .presentationDetents([.height(viewers.count > 4 ? 440 : 350), .large])
        case .gifts:
            if supportsRoomActivity {
                RoomGiftPicker(onClose: { panel = nil }, onShow: { gift in
                    showMyGift(gift); panel = nil
                }, onCollect: { gift in finishSheet(with: .collect(gift)) })
                    .presentationDetents([.height(530), .large])
            } else { GiftDeliveryView(personID: host.id) }
        case .messageActions:
            if let item = selectedMessage {
                MemberActions(targetID: item.id, authorID: item.personID, kind: "message",
                              contentPreview: store.person(item.personID).name + "\n" + item.text,
                              contentContext: "Room ID: \(room.id)\nMessage ID: \(item.id)\nSender: \(item.personID)\nMessage: \(item.text)\nGift ID: \(item.giftID ?? "none")")
                    .id(item.id)
            }
        case .report:
            MemberActions(targetID: room.id, authorID: host.id, kind: "room")
        case .invitation:
            VStack(spacing: 12) {
                panelHeading("Invite people")
                ScrollView {
                    ForEach(store.people.filter { store.state?.following.contains($0.id) == true }) { person in
                        HStack {
                            Avatar(person: person, size: 42); Text(person.name).font(.tutuHeadline); Spacer()
                            Button("Invite") { store.show("Invitation not sent", "Room invitations are unavailable. Please try again later.") }
                                .font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minWidth: 44, minHeight: 44)
                        }.padding(.vertical, 8)
                    }
                    if store.state?.following.isEmpty != false { EmptyState(title: "Follow someone first") }
                }
            }.padding(20).presentationDetents([.medium, .large])
        }
    }
    private func panelHeading(_ title: String) -> some View {
        HStack { Text(ui: title).font(.tutuTitle3); Spacer(); ArtButton(label: "Close", asset: "nav-close", size: 28) { panel = nil } }
    }
    private var viewerPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("In this room").font(.outfit(size: 22, weight: .bold))
                Spacer()
                ArtButton(label: "Close viewers", asset: "nav-close", size: 26) { panel = nil }
            }
            HStack(spacing: 12) {
                Button { finishSheet(with: .panel(.hostProfile)) } label: {
                    HStack(spacing: 12) {
                        Avatar(person: host, size: 54)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(host.name).font(.outfit(size: 16, weight: .semibold)).lineLimit(1)
                                Text("Host").font(.outfit(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.pink).padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Palette.blush, in: Capsule())
                            }
                            Text(room.title).font(.outfit(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("View host, " + host.name)
                FollowButton(personID: host.id, size: 36)
            }
            Divider().overlay(Palette.blush)
            HStack(spacing: 6) {
                Text("Viewers").font(.outfit(size: 13, weight: .semibold))
                Text(viewers.count.formatted()).font(.outfit(size: 13, weight: .semibold)).foregroundStyle(Palette.pink)
            }.accessibilityElement(children: .combine)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 18) {
                    ForEach(viewers) { person in
                        if person.id == store.me.id { viewerTile(person) }
                        else {
                            Button { finishSheet(with: .profile(person.id)) } label: { viewerTile(person) }
                                .buttonStyle(.plain)
                        }
                    }
                }.padding(.bottom, 8)
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }
    private func viewerTile(_ person: Person) -> some View {
        let isMe = person.id == store.me.id
        let following = store.state?.following.contains(person.id) == true
        return VStack(spacing: 5) {
            Avatar(person: person, size: 50)
            Text(person.name).font(.outfit(size: 12, weight: .medium)).lineLimit(1)
            Text(ui: isMe ? "You" : following ? "Following" : person.interests.first ?? "Viewer")
                .font(.outfit(size: 10)).foregroundStyle(isMe || following ? Palette.pink : Palette.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private func refreshModeration() {
        messages.removeAll { store.isMessageHidden($0) }
        if let event = giftEvent, store.isMessageHidden(event) { giftEvent = nil }
        if let destination = personDestination {
            let id: String
            switch destination {
            case .profile(let personID), .chat(let personID), .album(let personID, _): id = personID
            }
            if store.isPersonHidden(id) { personDestination = nil }
        }
    }
    private func open(_ next: RoomPanel) { composing = false; panel = next }
    private func finishSheet(with action: RoomNextAction) { nextAction = action; panel = nil }
    private func continueAfterSheet() {
        guard let action = nextAction else { return }
        nextAction = nil
        switch action {
        case .panel(let next): panel = next
        case .profile(let id): personDestination = .profile(id)
        case .chat(let id): personDestination = .chat(id)
        case .album(let id, let index): personDestination = .album(id, index)
        case .minimize: leaveRoom(minimized: true)
        case .leave: leaveRoom()
        case .collect(let gift): store.requestCoins(for: .gift(gift, 1))
        }
    }
    private func leaveRoom(minimized: Bool = false) {
        roomVisible = false; composing = false; requestedVoiceSeat = nil
        stopRoomVideo(); camera.stop()
        store.minimizedRoom = minimized ? room : nil
        dismiss()
    }
    private func startRoomVideo() {
        guard let url = videoURL else { return }
        playback.open(url, loop: true)
        if !playback.playing { playback.toggle() }
    }
    private func stopRoomVideo() { if let url = videoURL, playback.activeURL == url { playback.stop() } }
    private func append(_ entry: RoomMessage) {
        guard !store.isMessageHidden(entry) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            messages.removeAll { $0.id == entry.id }
            messages.append(entry)
            if messages.count > 60 { messages.removeFirst(messages.count - 60) }
            if entry.giftID != nil { giftEvent = entry }
        }
    }
    private func saveMyEntry(_ entry: RoomMessage) -> Bool {
        store.commit { state in
            var history = state.roomMessages ?? [:]
            var entries = history[room.id] ?? []
            entries.append(entry); history[room.id] = Array(entries.suffix(100))
            state.roomMessages = history
            state.drafts["room-" + room.id] = nil
        }
    }
    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard supportsRoomActivity else { store.show("Message not sent", "Room messaging is unavailable. Your message has been kept."); return }
        let entry = RoomMessage(personID: store.me.id, text: String(text.prefix(300)))
        if saveMyEntry(entry) { append(entry); message = ""; composing = false }
    }
    private func showMyGift(_ gift: Gift) {
        guard gift.id == "heart" || (store.state?.inventory[gift.id] ?? 0) > 0 else { return }
        let entry = RoomMessage(personID: store.me.id, text: "Cheered with " + gift.name, giftID: gift.id)
        if saveMyEntry(entry) { append(entry) }
    }
    private func advanceActivity() {
        // Authored local room activity; never treated as received network messages or gifts.
        guard !audience.isEmpty else { return }
        let captions = ["Love how this look comes together!", "The layers make it.", "That color combination is so good.", "Saving this outfit idea.", "I'd wear this for a city afternoon.", "The details are everything.", "Such a clean silhouette.", "This is my kind of style."]
        let person = audience[activityStep % audience.count]
        if activityStep % 4 == 3 {
            let gifts = Gift.all.filter { ["heart", "flowers", "star", "bear"].contains($0.id) }
            let gift = gifts[(activityStep / 4) % gifts.count]
            append(RoomMessage(id: "activity:\(room.id):\(person.id):gift:\(gift.id)", personID: person.id, text: "Cheered with " + gift.name, giftID: gift.id))
        } else { append(RoomMessage(id: "activity:\(room.id):\(person.id):text:\(activityStep % captions.count)", personID: person.id, text: captions[activityStep % captions.count])) }
        activityStep += 1
    }
}

private struct RoomGiftPicker: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected = Gift.all[1]
    let onClose: () -> Void
    let onShow: (Gift) -> Void
    let onCollect: (Gift) -> Void
    private var canShow: Bool { selected.id == "heart" || (store.state?.inventory[selected.id] ?? 0) > 0 }
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("Room gifts").font(.tutuTitle3); Spacer(); ArtButton(label: "Close", asset: "nav-close", size: 28, action: onClose) }
            Text("Heart Beat is free. Collected gifts are yours to reuse.").font(.tutuSubheadline).foregroundStyle(Palette.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(Gift.all) { gift in
                        Button { selected = gift } label: {
                            VStack(spacing: 6) {
                                Artwork(name: gift.image).frame(height: 54)
                                Text(gift.name).font(.tutuCaption2).lineLimit(1)
                                (gift.id == "heart" ? Text("Free") : (store.state?.inventory[gift.id] ?? 0) > 0 ? Text("Collected") : Text("\(gift.price) coins")).font(.tutuCaption2).foregroundStyle(Palette.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(selected == gift ? Palette.pink.opacity(0.14) : .white, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(alignment: .topTrailing) { if selected == gift { Artwork(name: "control-check").frame(width: 16, height: 16).padding(4) } }
                        }.buttonStyle(.plain).accessibilityAddTraits(selected == gift ? [.isSelected] : [])
                    }
                }
            }
            Text("Gift effects appear in this room on your device.").font(.tutuCaption).foregroundStyle(Palette.secondary)
            PinkButton(title: canShow ? store.appLanguage.format("Show %@", selected.name) : store.appLanguage.format("Collect · %lld coins", selected.price)) {
                if canShow { onShow(selected) } else { onCollect(selected) }
            }
        }.padding(20)
    }
}

private enum RoomCreationKind: String, CaseIterable {
    case live = "Live Room", voice = "Voice Room"
    var artwork: String { self == .voice ? "tab-party-active" : "tab-live-active" }
    var caption: String { self == .voice ? "Talk style together" : "Share your look" }
}
struct CreateRoomView: View {
    @EnvironmentObject private var store: AppStore
    @State private var title = ""
    @State private var category = "Daily"
    @State private var topic = VoiceRoomTopics.options[0]
    @State private var kind: RoomCreationKind = .live
    @State private var liveCover: String?
    @State private var voiceCover: String?
    @State private var coverKind: RoomCreationKind?
    @State private var media = false
    @State private var error = ""
    @State private var created: StyleRoom?
    @FocusState private var editingTitle: Bool
    private var cover: String {
        kind == .voice ? voiceCover ?? store.me.avatar : liveCover ?? "wardrobe-placeholder"
    }
    var body: some View {
        Page(title: "Create a room") {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Make room for your style").font(.outfit(size: 24, weight: .bold))
                        Text("A look to share. A conversation to start.")
                            .font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                    }
                    HStack(spacing: 12) {
                        ForEach(RoomCreationKind.allCases, id: \.self) { option in
                            Button {
                                editingTitle = false; kind = option; error = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Artwork(name: option.artwork).frame(width: 32, height: 32)
                                        Spacer()
                                        if kind == option { Artwork(name: "control-selected").frame(width: 22, height: 22) }
                                    }
                                    Text(ui: option.rawValue).font(.outfit(size: 16, weight: .semibold))
                                    Text(ui: option.caption).font(.outfit(size: 12)).foregroundStyle(Palette.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                    .background(kind == option ? Palette.blush : .white, in: RoundedRectangle(cornerRadius: 20))
                                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(kind == option ? Palette.pink : .clear, lineWidth: 1.5) }
                                    .contentShape(RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain).accessibilityAddTraits(kind == option ? [.isSelected] : [])
                        }
                    }
                    coverSelector
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Room name").font(.tutuHeadline)
                            Spacer()
                            Text("\(title.count)/60").font(.tutuCaption).foregroundStyle(Palette.secondary)
                        }
                        TextField(LocalizedStringKey(kind == .voice ? "What's everyone talking about?" : "Give your look a headline"), text: $title)
                            .font(.tutuBody).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .focused($editingTitle).submitLabel(.done).onSubmit { editingTitle = false }
                            .onChange(of: title) { _, value in
                                if value.count > 60 { title = String(value.prefix(60)) }
                                error = ""
                            }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(ui: kind == .voice ? "Conversation topic" : "Style category").font(.tutuHeadline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(kind == .voice ? VoiceRoomTopics.options : RoomCategories.options, id: \.self) { value in
                                topicButton(value)
                            }
                        }
                    }
                    if kind == .voice {
                        HStack(spacing: 12) {
                            Artwork(name: "icon-mic").frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("8 seats, one conversation").font(.tutuSubheadline.bold())
                                Text("Bring your next style conversation together.").font(.tutuCaption).foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                    if !error.isEmpty { Text(ui: error).font(.tutuSubheadline).foregroundStyle(Palette.pink).accessibilityLabel("Room name error. " + error) }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 9) {
                        PinkButton(title: kind == .voice ? "Create voice room" : "Create live room", action: create)
                        Text("Creating a room doesn't start a broadcast.")
                            .font(.tutuCaption).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10).background(Palette.blush)
                }
        }.sheet(isPresented: $media, onDismiss: { coverKind = nil }) {
            MediaSourceView(title: "Choose a room cover", subtitle: "Give your room a look of its own.") { item in
                do {
                    let reference = try store.importMedia(item).reference
                    if coverKind == .voice { voiceCover = reference } else { liveCover = reference }
                } catch { store.show("Cover not added", error.localizedDescription) }
            }
        }.navigationDestination(item: $created) { RoomView(room: $0) }
    }
    private var coverSelector: some View {
        Button {
            editingTitle = false; coverKind = kind; media = true
        } label: {
            HStack(spacing: 16) {
                MediaArtwork(reference: cover).frame(width: 88, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 14)).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Room cover").font(.tutuHeadline)
                    Text(ui: kind == .voice ? "Your avatar is the default cover." : "Pick a photo that sets the mood.")
                        .font(.tutuCaption).foregroundStyle(Palette.secondary)
                    Text("Change photo").font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink)
                }
                Spacer(minLength: 0)
                Artwork(name: "icon-photo").frame(width: 32, height: 32).allowsHitTesting(false)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityLabel("Change room cover")
    }
    private func topicButton(_ value: String) -> some View {
        let selected = (kind == .voice ? topic : category) == value
        return Button {
            if kind == .voice { topic = value } else { category = value }
        } label: {
            Text(ui: value).font(.outfit(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Palette.ink).frame(maxWidth: .infinity).frame(minHeight: 44)
                .background {
                    if selected { Image("button-base").resizable() } else { Color.white }
                }.clipShape(Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func create() {
        editingTitle = false
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { error = "Add a room name to get started."; return }
        let room = StyleRoom(id: UUID().uuidString, hostID: store.me.id, title: name, category: category,
                             voice: kind == .voice, voiceTopic: kind == .voice ? topic : nil, cover: cover)
        if store.commit({ $0.rooms.append(room) }) { created = room }
    }
}
struct CallView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @Environment(\.openURL) private var openURL
    let personID: String
    let video: Bool
    @StateObject private var camera = CameraService()
    @State private var busy = false
    @State private var visible = false
    @State private var captureTask: Task<Void, Never>?
    private var permissionDenied: Bool {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        let lens = AVCaptureDevice.authorizationStatus(for: .video)
        return microphone == .denied || microphone == .restricted ||
            (video && (lens == .denied || lens == .restricted))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header.padding(20)
                ScrollView {
                    VStack(spacing: 20) {
                        preview.frame(height: max(240, min(420, geometry.size.height * 0.44)))
                        statusPanel
                        HStack(alignment: .top, spacing: 12) {
                            control(title: camera.microphoneEnabled ? "Mute" : "Unmute", asset: "icon-mic",
                                    enabled: camera.microphoneAvailable && !busy, selected: !camera.microphoneEnabled) {
                                camera.setMicrophoneEnabled(!camera.microphoneEnabled)
                            }
                            if video {
                                control(title: "Switch camera", asset: "call-video", enabled: camera.ready && !busy) {
                                    prepareCapture(flipping: true)
                                }
                            }
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }.scrollIndicators(.hidden)
                Button(action: endCall) {
                    HStack(spacing: 10) {
                        Artwork(name: "call-voice").frame(width: 28, height: 28).rotationEffect(.degrees(135))
                        Text("End call").font(.tutuHeadline)
                    }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 56)
                        .background { Image("button-base").resizable() }
                }.buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
        .background { SceneBackground(name: "party-background") }
        .foregroundStyle(.white).toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard store.state?.following.contains(personID) == true, store.followerIDs.contains(personID), !store.isPersonHidden(personID) else {
                store.show("A little connection first", "Follow each other before starting a call."); dismiss(); return
            }
            visible = true; prepareCapture()
        }
        .onDisappear { stopCapture() }
        .onChange(of: scene) { _, phase in
            // System permission sheets temporarily make the app inactive. Do not dismiss then.
            if phase == .background { endCall() }
        }
        .onChange(of: store.sessionID) { _, _ in endCall() }
        .moderationVisibility(hidden: store.isPersonHidden(personID))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(person: store.person(personID), size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.person(personID).name).font(.outfit(size: 18, weight: .semibold)).lineLimit(1)
                Text(ui: video ? "Video call" : "Voice call").font(.tutuCaption).foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            ArtButton(label: "Close call", asset: "nav-close", size: 28) { endCall() }
                .background(.white.opacity(0.9), in: Circle())
        }
    }

    private var preview: some View {
        ZStack {
            Palette.ink
            if video && camera.ready {
                CameraSurface(session: camera.capture)
                    .accessibilityLabel("Your local camera preview")
            } else if video {
                VStack(spacing: 16) {
                    Artwork(name: "call-video").frame(width: 76, height: 76)
                    Text(ui: busy ? "Preparing…" : "Camera preview is unavailable")
                        .font(.tutuSubheadline).multilineTextAlignment(.center)
                }.padding(20)
            } else {
                VStack(spacing: 20) {
                    Avatar(person: store.person(personID), size: 116)
                    Text(store.person(personID).name).font(.outfit(size: 26, weight: .bold))
                    Artwork(name: "call-voice").frame(width: 40, height: 40)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if video && camera.ready {
                Text("You · Local preview").font(.outfit(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Palette.ink.opacity(0.85), in: Capsule()).padding(14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
    }

    private var statusPanel: some View {
        VStack(spacing: 10) {
            Text(ui: busy ? "Preparing…" : video && camera.ready ? "Your camera is ready" : camera.ready ? "Your microphone is ready" : "Check your permissions")
                .font(.outfit(size: 17, weight: .semibold))
            Text("Calls are not available yet. No call is connected.")
                .font(.tutuCaption).foregroundStyle(.white.opacity(0.8))
            if !busy && (!camera.ready || !camera.microphoneAvailable) {
                Text(ui: camera.status).font(.tutuCaption).foregroundStyle(.white.opacity(0.85))
                Button(permissionDenied ? "Open Settings" : "Try again") {
                    if permissionDenied, let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    else { prepareCapture() }
                }.font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44)
            }
        }.multilineTextAlignment(.center).padding(16).frame(maxWidth: .infinity)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func control(title: String, asset: String, enabled: Bool, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Artwork(name: asset).frame(width: 32, height: 32).frame(width: 58, height: 58)
                    .background(selected ? Palette.pink.opacity(0.3) : Color.white.opacity(0.14), in: Circle())
                Text(ui: title).font(.outfit(size: 12, weight: .medium)).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).opacity(enabled ? 1 : 0.45)
        }.buttonStyle(.plain).disabled(!enabled)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func prepareCapture(flipping: Bool = false) {
        guard visible, !busy else { return }
        busy = true
        captureTask = Task { @MainActor in
            if flipping { await camera.flip(previewWithoutMicrophone: true) }
            else { await camera.start(video: video, previewWithoutMicrophone: video) }
            guard !Task.isCancelled, visible else { return }
            busy = false; captureTask = nil
        }
    }
    private func stopCapture() {
        visible = false; captureTask?.cancel(); captureTask = nil; busy = false; camera.stop()
    }
    private func endCall() { stopCapture(); dismiss() }
}
struct LeaderboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var period = StarRankingPeriod.daily.rawValue
    var body: some View {
        Page(title: "Lucky Star") {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                rankingContent(now: Date())
            }
        }
    }
    private func rankingContent(now: Date) -> some View {
        let selected = StarRankingPeriod(rawValue: period) ?? .daily
        let entries = StarRankings.entries(people: store.people, state: store.state, period: selected, now: now)
        let mine = StarRankings.ownCoins(in: store.state, period: selected, now: now)
        let myRank = entries.firstIndex(where: { $0.personID == store.me.id }).map { $0 + 1 }
        return VStack(spacing: 10) {
            Artwork(name: "lucky-star-banner").frame(height: 60).padding(.top, 8)
            Text("Ranked by coins spent").font(.tutuCaption).foregroundStyle(Palette.secondary)
            SectionTabs(titles: StarRankingPeriod.allCases.map(\.rawValue), selection: $period)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(value: Route.profile(entry.personID)) {
                            rankingRow(entry, rank: index + 1)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
            HStack(spacing: 10) {
                Text(ui: myRank.map { "#\($0)" } ?? "—")
                    .font(.outfit(size: 18, weight: .bold)).foregroundStyle(Palette.pink).frame(minWidth: 30)
                Avatar(person: store.me, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.me.name).font(.tutuHeadline).lineLimit(1)
                    Text(ui: myRank == nil ? "No coins spent yet" : "Your rank · " + selected.rawValue)
                        .font(.tutuCaption).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 4)
                spentAmount(mine)
            }.padding(14).background(Palette.blush, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }
    private func rankingRow(_ entry: StarRankingEntry, rank: Int) -> some View {
        let person = store.person(entry.personID)
        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                if rank <= 3 { Artwork(name: "icon-trophy").frame(width: 22, height: 22) }
                Text(String(rank)).font(.outfit(size: rank <= 3 ? 19 : 16, weight: .bold))
                    .foregroundStyle(rank <= 3 ? Palette.pink : Palette.secondary)
            }.frame(width: 26)
            Avatar(person: person, size: rank <= 3 ? 50 : 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(person.name).font(.tutuHeadline).lineLimit(1)
                Text(entry.personID == store.me.id ? "You" : "@" + person.handle)
                    .font(.tutuCaption).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            spentAmount(entry.coins)
        }.padding(.horizontal, 12).padding(.vertical, rank <= 3 ? 15 : 12)
            .background(rank <= 3 ? Color.white : Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rank \(rank), \(person.name), \(entry.coins) coins spent")
    }
    private func spentAmount(_ amount: Int) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Artwork(name: "icon-coin").frame(width: 16, height: 16)
                Text(amount.formatted()).font(.outfit(size: 16, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text("coins spent").font(.tutuCaption2).foregroundStyle(Palette.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }
}
