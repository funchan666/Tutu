import SwiftUI
import AVFoundation

private enum DiscoverSheet: Identifiable {
    case comments(Look), options(Look)
    var id: String {
        switch self {
        case .comments(let look): return "comments-" + look.id
        case .options(let look): return "options-" + look.id
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var focused: String?
    @State private var visible = false
    @State private var sheet: DiscoverSheet?
    @State private var ownedURL: URL?
    private var looks: [Look] { store.discoverLooks }
    private var current: Look? { looks.first { $0.id == focused } ?? looks.first }
    private var playbackKey: String {
        guard visible, scenePhase == .active, store.tab == 3, sheet == nil, store.notice == nil else { return "" }
        return current?.id ?? ""
    }
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            if looks.isEmpty {
                EmptyState(title: "All caught up", message: "There are no more looks to show right now.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.blush)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(looks) { look in
                            DiscoverLook(look: look, isFocused: current?.id == look.id,
                                         showComments: { sheet = .comments(look) },
                                         showOptions: { sheet = .options(look) })
                                .containerRelativeFrame(.vertical).id(look.id)
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.paging).scrollIndicators(.hidden)
                    .scrollPosition(id: $focused).scrollDisabled(sheet != nil)
                    .ignoresSafeArea(.container, edges: .top)
            }
            MainHeading(asset: "heading-discover") {
                HStack(spacing: 8) {
                    InboxEntryButton()
                    if let current {
                        NavigationLink(value: Route.profile(current.authorID)) {
                            Avatar(person: store.person(current.authorID), size: 42)
                                .allowsHitTesting(false).frame(width: 48, height: 48).contentShape(Circle())
                        }.buttonStyle(.plain).accessibilityLabel("View \(store.person(current.authorID).name)'s profile")
                    }
                }
            }
        }
        .onAppear { visible = true; if focused == nil { focused = looks.first?.id } }
        .onDisappear { visible = false; stopPlayback() }
        .onChange(of: looks.map(\.id)) { _, ids in
            if focused == nil || !ids.contains(focused ?? "") { focused = ids.first }
        }
        .task(id: playbackKey) {
            let requested = playbackKey
            guard !requested.isEmpty else {
                if let ownedURL, MoviePlayback.shared.activeURL == ownedURL, MoviePlayback.shared.playing {
                    MoviePlayback.shared.toggle()
                }
                return
            }
            guard let look = looks.first(where: { $0.id == requested }),
                  let reference = look.video, let url = store.mediaURL(reference) else { stopPlayback(); return }
            if ownedURL != url { stopPlayback() }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard !Task.isCancelled, playbackKey == requested else { return }
            ownedURL = url
            MoviePlayback.shared.open(url, loop: true)
            if !MoviePlayback.shared.playing { MoviePlayback.shared.toggle() }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .comments(let look): LookCommentsSheet(postID: look.id)
            case .options(let look):
                MemberActions(targetID: look.id, authorID: look.authorID, kind: "post", contentPreview: look.text, contentContext: "Discover video")
            }
        }
    }
    private func stopPlayback() {
        if let ownedURL, MoviePlayback.shared.activeURL == ownedURL { MoviePlayback.shared.stop() }
        ownedURL = nil
    }
}

struct DiscoverLook: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var playback = MoviePlayback.shared
    let look: Look
    let isFocused: Bool
    var showComments: () -> Void
    var showOptions: () -> Void
    @State private var heartVisible = false
    @State private var heartToken = 0
    private var liked: Bool { store.state?.likedLooks.contains(look.id) == true }
    private var commentCount: Int { store.comments.filter { $0.postID == look.id }.count }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    MediaArtwork(reference: look.media.first ?? "wardrobe-placeholder").allowsHitTesting(false)
                    if isFocused, let ref = look.video, let url = store.mediaURL(ref), playback.activeURL == url, let player = playback.player {
                        MovieLayer(player: player, fillsFrame: true).allowsHitTesting(false)
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle()).onTapGesture(count: 2) { likeFromVideo() }
                    .accessibilityAction(named: "Like video") { likeFromVideo() }
                if heartVisible {
                    Artwork(name: "icon-liked").frame(width: 90, height: 90)
                        .rotationEffect(.degrees(reduceMotion ? 0 : -12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.55).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            NavigationLink(value: Route.profile(look.authorID)) {
                                Text(store.person(look.authorID).name).font(.outfit(size: 20, weight: .bold, design: .rounded)).lineLimit(2)
                            }.buttonStyle(.plain)
                            FollowButton(personID: look.authorID, size: 32, contentStyle: true)
                        }
                        Text("@" + store.person(look.authorID).handle).font(.tutuCaption).foregroundStyle(.white.opacity(0.9))
                        Text(look.text).font(.outfit(size: 14, design: .rounded)).lineSpacing(3).lineLimit(4)
                    }.foregroundStyle(.white).shadow(color: .black.opacity(0.65), radius: 3, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 20) {
                        LookLikeButton(look: look)
                        Button(action: showComments) {
                            VStack(spacing: 3) {
                                Artwork(name: "icon-comment").frame(width: 48, height: 48)
                                Text(commentCount.formatted()).font(.tutuCaption.bold()).monospacedDigit()
                                    .contentTransition(.numericText())
                            }.frame(minWidth: 48, minHeight: 64).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(commentCount) comments. Open comments")
                        ArtButton(label: "Video options", asset: "icon-content-more", size: 48, action: showOptions)
                    }.foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .padding(.bottom, 12)
                }.padding(.horizontal, 18).padding(.bottom, 24)
                if isFocused, !playback.failure.isEmpty {
                    Text("This video couldn't load. Swipe to the next look.")
                        .font(.tutuSubheadline).foregroundStyle(.white).padding(18)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: heartToken) {
            guard heartToken > 0 else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { heartVisible = false }
        }
        .onChange(of: isFocused) { _, active in if !active { heartVisible = false } }
    }
    private func likeFromVideo() {
        guard liked || store.setLookLiked(look.id, liked: true) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.6)) { heartVisible = true }
        heartToken += 1
    }
}

struct LookLikeButton: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let look: Look
    var showCount = true
    @State private var scale: CGFloat = 1
    @State private var pulse = 0
    private var liked: Bool { store.state?.likedLooks.contains(look.id) == true }
    var body: some View {
        Button {
            let adding = !liked
            guard store.setLookLiked(look.id, liked: adding) else { return }
            UIImpactFeedbackGenerator(style: adding ? .light : .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.12)) { scale = reduceMotion ? 1 : (adding ? 1.24 : 0.82) }
            pulse += 1
        } label: {
            VStack(spacing: 3) {
                Artwork(name: liked ? "icon-liked" : "icon-like").frame(width: 48, height: 48).scaleEffect(scale)
                if showCount {
                    Text(store.likeCount(for: look).formatted()).font(.tutuCaption.bold()).monospacedDigit()
                        .contentTransition(.numericText()).animation(.easeOut(duration: 0.2), value: liked)
                }
            }.frame(minWidth: 48, minHeight: showCount ? 64 : 48).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(liked ? "Unlike" : "Like")
            .accessibilityValue("\(store.likeCount(for: look)) likes")
            .accessibilityAddTraits(liked ? [.isSelected] : [])
            .task(id: pulse) {
                guard pulse > 0 else { return }
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.5)) { scale = 1 }
            }
            .onDisappear { scale = 1 }
    }
}

struct LookCommentsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let postID: String
    @State private var text = ""
    @State private var selectedComment: ReportTarget?
    @State private var submittedID: String?
    @FocusState private var writing: Bool
    private var look: Look? { store.looks.first { $0.id == postID } }
    private var comments: [LookComment] { store.comments.filter { $0.postID == postID } }
    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && look != nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comments").font(.outfit(size: 23, weight: .bold, design: .rounded))
                    Text("\(comments.count) in the conversation").font(.tutuCaption).foregroundStyle(Palette.secondary)
                }
                Spacer()
                ArtButton(label: "Close comments", asset: "nav-close", size: 32) { dismiss() }
            }.padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 16)
            if let look {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(person: store.person(look.authorID), size: 38).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.person(look.authorID).name).font(.tutuSubheadline.bold())
                        Text(look.text).font(.tutuCaption).foregroundStyle(Palette.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(14).background(Palette.blush, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if comments.isEmpty {
                            Text("Be the first to share a thought on this look.")
                                .font(.tutuSubheadline).foregroundStyle(Palette.secondary).padding(.vertical, 36)
                        }
                        ForEach(comments) { comment in commentRow(comment).id(comment.id) }
                    }.padding(.horizontal, 22).padding(.bottom, 12)
                }.scrollDismissesKeyboard(.interactively)
                    .onChange(of: submittedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) } }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Palette.ink).background(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .presentationDetents([.fraction(0.72), .large]).presentationCornerRadius(30)
        .presentationDragIndicator(.hidden).presentationBackground(.white)
        .sheet(item: $selectedComment) { target in
            MemberActions(targetID: target.id, authorID: target.author, kind: "comment",
                          contentPreview: comments.first { $0.id == target.id }?.text, contentContext: "Comment on \(postID)")
        }
        .overlay { if selectedComment == nil { NoticeOverlay() } }
        .onAppear { text = store.state?.drafts["comment-" + postID] ?? "" }
        .onDisappear {
            guard look != nil else { return }
            let draft = text
            store.commit { $0.drafts["comment-" + postID] = draft.isEmpty ? nil : draft }
        }
        .onChange(of: look == nil) { _, hidden in if hidden { dismiss() } }
    }
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Avatar(person: store.me, size: 32).allowsHitTesting(false).padding(.bottom, 7)
            TextField("What caught your eye?", text: $text, axis: .vertical)
                .font(.tutuSubheadline).lineLimit(1...4).focused($writing)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                .onChange(of: text) { _, value in if value.count > 1000 { text = String(value.prefix(1000)) } }
            ArtButton(label: "Post comment", asset: "icon-send", size: 42) {
                guard canSend, store.addComment(to: postID, text: text) else { return }
                text = ""; writing = false
                submittedID = store.state?.comments.last?.id
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }.disabled(!canSend).opacity(canSend ? 1 : 0.45)
        }.padding(.horizontal, 16).padding(.vertical, 12).background(Palette.blush)
    }
    private func commentRow(_ comment: LookComment) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Avatar(person: store.person(comment.authorID), size: 36).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    (comment.authorID == store.me.id ? Text("You") : Text(verbatim: store.person(comment.authorID).name))
                        .font(.outfit(size: 13, weight: .semibold, design: .rounded))
                    if comment.authorID == look?.authorID {
                        Text("Creator").font(.outfit(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.pink).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.blush, in: Capsule())
                    }
                }
                Text(comment.text).font(.outfit(size: 14, design: .rounded)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(comment.created, style: .relative).font(.outfit(size: 11, design: .rounded)).foregroundStyle(Palette.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .onTapGesture { if comment.authorID != store.me.id { openActions(comment) } }
            if comment.authorID == store.me.id {
                Button("Delete") { store.commit { $0.comments.removeAll { $0.id == comment.id } } }
                    .font(.tutuCaption).foregroundStyle(Palette.pink).frame(minWidth: 44, minHeight: 44)
            } else {
                ArtButton(label: "Report or block comment by \(store.person(comment.authorID).name)", asset: "nav-more", size: 24) { openActions(comment) }
            }
        }.padding(.vertical, 16)
    }
    private func openActions(_ comment: LookComment) {
        writing = false
        selectedComment = ReportTarget(id: comment.id, author: comment.authorID, kind: "comment")
    }
}

struct PostDetailView: View {
    @EnvironmentObject private var store: AppStore
    let postID: String
    @State private var text = ""
    @State private var report: ReportTarget?
    var look: Look? { store.looks.first { $0.id == postID } }
    var comments: [LookComment] { store.comments.filter { $0.postID == postID } }
    var body: some View {
        Page(title: "Look") {
            if let look {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack { NavigationLink(value: Route.profile(look.authorID)) { HStack { Avatar(person: store.person(look.authorID)); Text(store.person(look.authorID).name).font(.tutuHeadline) } }.buttonStyle(.plain); Spacer(); ArtButton(label: "More", asset: "nav-more") { report = ReportTarget(id: postID, author: look.authorID, kind: "post") } }
                            if let ref = look.video, let url = store.mediaURL(ref) { MovieView(url: url).frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 20)) }
                            else { MediaArtwork(reference: look.media.first ?? "wardrobe-placeholder").frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 20)) }
                            Text(look.text).font(.tutuBody).fixedSize(horizontal: false, vertical: true)
                            HStack { LookLikeButton(look: look); Button(store.state?.savedLooks.contains(postID) == true ? "Saved" : "Save") { store.commit { s in if s.savedLooks.contains(postID) { s.savedLooks.remove(postID) } else { s.savedLooks.insert(postID) } } }.foregroundStyle(Palette.pink).font(.tutuSubheadline.bold()); Spacer(); Text(look.created, style: .date).font(.tutuCaption).foregroundStyle(Palette.secondary) }
                            Text("Comments · \(comments.count)").font(.tutuHeadline)
                            if comments.isEmpty { Text("Start a thoughtful conversation.").font(.tutuSubheadline).foregroundStyle(Palette.secondary) }
                            ForEach(comments) { comment in
                                HStack(alignment: .top, spacing: 12) {
                                    NavigationLink(value: Route.profile(comment.authorID)) { Avatar(person: store.person(comment.authorID), size: 38) }.buttonStyle(.plain)
                                    VStack(alignment: .leading, spacing: 6) { Text(store.person(comment.authorID).name).font(.tutuSubheadline.bold()); Text(comment.text).font(.tutuSubheadline); Text(comment.created, style: .time).font(.tutuCaption).foregroundStyle(Palette.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                                    if comment.authorID == store.me.id { Button("Delete") { store.commit { $0.comments.removeAll { $0.id == comment.id } } }.font(.tutuCaption).foregroundStyle(Palette.pink).frame(minHeight: 44) }
                                    else { ArtButton(label: "More comment options", asset: "nav-more", size: 28) { report = ReportTarget(id: comment.id, author: comment.authorID, kind: "comment") } }
                                }.panel()
                            }
                        }.padding(16)
                    }.scrollDismissesKeyboard(.interactively)
                    HStack { TextField("Add a comment", text: $text, axis: .vertical).lineLimit(1...4).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 22)); ArtButton(label: "Save comment", asset: "icon-send") { let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { return }; if store.addComment(to: postID, text: trimmed) { text = "" } } }.padding(12).background(Palette.blush)
                }
            } else { EmptyState(title: "This post is unavailable") }
        }.sheet(item: $report) { MemberActions(targetID: $0.id, authorID: $0.author, kind: $0.kind) }
            .onAppear { text = store.state?.drafts["comment-" + postID] ?? "" }
            .onDisappear { if !text.isEmpty, look != nil { store.commit { $0.drafts["comment-" + postID] = text } }; MoviePlayback.shared.stop() }
            .moderationVisibility(hidden: look == nil)
    }
}
struct ReportTarget: Identifiable { let id: String; let author: String; let kind: String }
struct ComposeLookView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var category = "Daily"
    @State private var image = ""
    @State private var video: String?
    @State private var media = false
    @State private var error = ""
    var body: some View {
        Page(title: "Create a look") {
            ScrollView { VStack(alignment: .leading, spacing: 20) {
                Text("What's your style today?").font(.tutuTitle2.bold())
                TextEditor(text: $caption).frame(height: 150).padding(12).scrollContentBackground(.hidden).background(.white, in: RoundedRectangle(cornerRadius: 18))
                Text("\(caption.count)/1000").font(.tutuCaption).foregroundStyle(Palette.secondary)
                if let video, let url = store.mediaURL(video) { MovieView(url: url).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 18)) }
                else if !image.isEmpty { MediaArtwork(reference: image).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 18)) }
                PinkButton(title: "Add photo or video") { media = true }
                SectionTabs(titles: ["Daily", "Minimalist", "Streetwear", "Vintage"], selection: $category).padding(.horizontal, -20)
                if !error.isEmpty { Text(ui: error).font(.tutuSubheadline).foregroundStyle(.red) }
                Text("Save your look to your profile. Sharing with other members is currently unavailable.").font(.tutuCaption).foregroundStyle(Palette.secondary)
                PinkButton(title: "Save look") {
                    let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard (!text.isEmpty || !image.isEmpty || video != nil), caption.count <= 1000 else { error = "Add a photo, video, or a caption under 1000 characters."; return }
                    let post = Look(authorID: store.me.id, text: text, media: [image.isEmpty ? "wardrobe-placeholder" : image], video: video, category: category)
                    if store.commit({ $0.looks.insert(post, at: 0); $0.drafts["compose"] = nil; $0.mediaDrafts["compose"] = nil; $0.drafts["compose-category"] = nil }) { caption = ""; image = ""; video = nil; dismiss() }
                }
            }.padding(20) }.scrollDismissesKeyboard(.interactively)
        }.sheet(isPresented: $media) { MediaSourceView(allowVideo: true) { selection in do { let file = try store.importMedia(selection); if store.commit({ $0.mediaDrafts["compose"] = file.reference }) { if file.video { video = file.reference; image = "" } else { image = file.reference; video = nil } } } catch { self.error = error.localizedDescription } } }
            .onAppear {
                caption = store.state?.drafts["compose"] ?? ""; category = store.state?.drafts["compose-category"] ?? "Daily"
                if let reference = store.state?.mediaDrafts["compose"] {
                    if ["jpg", "jpeg", "png"].contains((reference as NSString).pathExtension.lowercased()) { image = reference } else { video = reference }
                }
            }
            .onDisappear { store.commit { $0.drafts["compose"] = caption.isEmpty ? nil : caption; $0.drafts["compose-category"] = category }; MoviePlayback.shared.stop() }
    }
}
@MainActor final class MoviePlayback: ObservableObject {
    static let shared = MoviePlayback()
    @Published private(set) var player: AVPlayer?
    @Published private(set) var activeURL: URL?
    @Published private(set) var playing = false
    @Published private(set) var failure = ""
    private var observation: NSKeyValueObservation?
    private var ending: NSObjectProtocol?
    func open(_ url: URL, loop: Bool = false) {
        if activeURL == url { return }
        stop(); let item = AVPlayerItem(url: url); player = AVPlayer(playerItem: item); activeURL = url
        observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard let self, self.activeURL == url, failed else { return }
                self.failure = "This video couldn't be played. Try choosing the file again."; self.playing = false
            }
        }
        ending = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activeURL == url else { return }
                if loop, self.playing { self.player?.seek(to: .zero); self.player?.play() }
                else { self.playing = false }
            }
        }
    }
    func toggle() {
        guard let player, failure.isEmpty else { return }
        if playing { player.pause() }
        else { if let item = player.currentItem, item.currentTime() >= item.duration { player.seek(to: .zero) }; player.play() }
        playing.toggle()
    }
    func stop() {
        observation = nil
        if let ending { NotificationCenter.default.removeObserver(ending) }; ending = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil; activeURL = nil; playing = false; failure = ""
    }
}
struct MovieView: View {
    let url: URL
    var autoplay = false
    @ObservedObject private var playback = MoviePlayback.shared
    @State private var error = ""
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if playback.activeURL == url, let player = playback.player { MovieLayer(player: player) }
            VStack(spacing: 8) {
                if !error.isEmpty { Text(ui: error).font(.tutuCaption).foregroundStyle(.white) }
                if playback.activeURL == url && !playback.failure.isEmpty { Text(playback.failure).font(.tutuCaption).foregroundStyle(.white) }
                Button(playback.playing ? "Pause video" : "Play video") {
                    guard FileManager.default.fileExists(atPath: url.path) else { error = "This video is unavailable."; return }
                    playback.open(url); playback.toggle()
                }.font(.tutuSubheadline.bold()).padding(.horizontal, 24).padding(.vertical, 12).background(.white, in: Capsule())
            }.padding(16)
        }.onAppear { playback.open(url); if autoplay && !playback.playing { playback.toggle() } }.onDisappear { if playback.activeURL == url { playback.stop() } }
    }
}
struct MovieLayer: UIViewRepresentable {
    let player: AVPlayer
    var fillsFrame = false
    func makeUIView(context: Context) -> MovieLayerView {
        let view = MovieLayerView()
        view.clipsToBounds = true
        view.playerLayer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ uiView: MovieLayerView, context: Context) {
        uiView.playerLayer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        uiView.playerLayer.player = player
    }
    static func dismantleUIView(_ uiView: MovieLayerView, coordinator: ()) { uiView.playerLayer.player = nil }
}
final class MovieLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
