import SwiftUI

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
                        Text(requestedVoiceSeat == seat ? "Waiting" : "Mic \(seat + 1)")
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
            Text(own ? "Your room is ready" : "Room unavailable").font(.tutuHeadline)
            Text(own ? "You can set up your camera and room. Live streaming is unavailable right now." : "This room isn't broadcasting right now. Try again later.").font(.tutuSubheadline)
            if own {
                Text(camera.status).font(.tutuCaption)
                HStack {
                    Button(video ? "Camera off" : "Camera on") { video.toggle(); if video { Task { await camera.start() } } else { camera.stop() } }
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
        HStack { Text(title).font(.tutuTitle3); Spacer(); ArtButton(label: "Close", asset: "nav-close", size: 28) { panel = nil } }
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
            Text(isMe ? "You" : following ? "Following" : person.interests.first ?? "Viewer")
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
                                Text(gift.id == "heart" ? "Free" : (store.state?.inventory[gift.id] ?? 0) > 0 ? "Collected" : "\(gift.price) coins").font(.tutuCaption2).foregroundStyle(Palette.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(selected == gift ? Palette.pink.opacity(0.14) : .white, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(alignment: .topTrailing) { if selected == gift { Artwork(name: "control-check").frame(width: 16, height: 16).padding(4) } }
                        }.buttonStyle(.plain).accessibilityAddTraits(selected == gift ? [.isSelected] : [])
                    }
                }
            }
            Text("Gift effects appear in this room on your device.").font(.tutuCaption).foregroundStyle(Palette.secondary)
            PinkButton(title: canShow ? "Show \(selected.name)" : "Collect · \(selected.price) coins") {
                if canShow { onShow(selected) } else { onCollect(selected) }
            }
        }.padding(20)
    }
}

struct CreateRoomView: View {
    @EnvironmentObject private var store: AppStore
    @State private var title = ""
    @State private var category = "Daily"
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
                SectionTabs(titles: RoomCategories.options, selection: $category)
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
            guard store.state?.following.contains(personID) == true, store.state?.followers.contains(personID) == true, !store.isPersonHidden(personID) else { store.show("A little connection first", "Follow each other before starting a call."); dismiss(); return }
            await camera.start(video: video); started = true
        }.onDisappear { camera.stop() }.onChange(of: scene) { _, phase in if phase != .active { camera.stop(); dismiss() } }
            .moderationVisibility(hidden: store.isPersonHidden(personID))
    }
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
                Text(myRank.map { "#\($0)" } ?? "—")
                    .font(.outfit(size: 18, weight: .bold)).foregroundStyle(Palette.pink).frame(minWidth: 30)
                Avatar(person: store.me, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.me.name).font(.tutuHeadline).lineLimit(1)
                    Text(myRank == nil ? "No coins spent yet" : "Your rank · " + selected.rawValue)
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
