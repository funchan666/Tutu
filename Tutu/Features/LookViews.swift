import SwiftUI
import AVFoundation

struct DiscoverView: View {
    @EnvironmentObject private var store: AppStore
    @State private var focused: String?
    var body: some View {
        ZStack(alignment: .top) {
            if store.looks.isEmpty { EmptyState(title: "A fresh start", message: "Your next inspiration will appear here.") }
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.looks) { look in DiscoverLook(look: look, isFocused: focused == look.id).containerRelativeFrame(.vertical).id(look.id) }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.paging).scrollIndicators(.hidden).scrollPosition(id: $focused).ignoresSafeArea(.container, edges: .top)
            MainHeading(asset: "heading-discover") {
                NavigationLink(value: Route.profile(store.me.id)) { Avatar(person: store.me, size: 38) }
                    .buttonStyle(.plain).accessibilityLabel("My profile")
            }
        }.onChange(of: focused) { _, _ in MoviePlayback.shared.stop() }.onDisappear { MoviePlayback.shared.stop() }
    }
}
struct DiscoverLook: View {
    @EnvironmentObject private var store: AppStore
    let look: Look
    let isFocused: Bool
    @State private var more = false
    @State private var playing = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                MediaArtwork(reference: look.media.first ?? "wardrobe-placeholder").frame(width: geo.size.width, height: geo.size.height)
                if let video = look.video, let url = store.mediaURL(video) {
                    if playing { MovieView(url: url, autoplay: true).frame(width: geo.size.width, height: geo.size.height) }
                    else { Button("Play video") { playing = true }.font(.tutuHeadline).padding(20).background(.white, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                Color.black.opacity(0.17).allowsHitTesting(false)
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            NavigationLink(value: Route.profile(look.authorID)) {
                                Text(store.person(look.authorID).name).font(.outfit(size: 16, weight: .bold, design: .rounded))
                            }.buttonStyle(.plain)
                            if look.authorID != store.me.id {
                                ArtButton(label: store.state?.following.contains(look.authorID) == true ? "Unfollow" : "Follow",
                                          asset: store.state?.following.contains(look.authorID) == true ? "control-content-followed" : "control-content-follow", size: 32) {
                                    store.toggleFollow(look.authorID)
                                }
                            }
                        }
                        Text(look.text).font(.outfit(size: 12, design: .rounded)).lineSpacing(3).lineLimit(3)
                    }.foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 14) {
                        ArtButton(label: "Like", asset: store.state?.likedLooks.contains(look.id) == true ? "icon-liked" : "icon-like", size: 48) {
                            store.commit { value in
                                if value.likedLooks.contains(look.id) { value.likedLooks.remove(look.id) } else { value.likedLooks.insert(look.id) }
                            }
                        }
                        NavigationLink(value: Route.post(look.id)) { Artwork(name: "icon-comment").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("Comments")
                        ArtButton(label: "More", asset: "icon-content-more", size: 44) { more = true }
                    }.padding(.bottom, 84)
                }.padding(.horizontal, 16).padding(.bottom, 18)
            }.clipped()
        }.sheet(isPresented: $more) { MemberActions(targetID: look.id, authorID: look.authorID, kind: "post") }.onDisappear { playing = false }.onChange(of: isFocused) { _, active in if !active { playing = false } }
    }
}
struct PostDetailView: View {
    @EnvironmentObject private var store: AppStore
    let postID: String
    @State private var text = ""
    @State private var report: ReportTarget?
    var look: Look? { store.looks.first { $0.id == postID } }
    var comments: [LookComment] { (store.state?.comments ?? []).filter { $0.postID == postID && !(store.state?.blocked.contains($0.authorID) ?? false) } }
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
                            HStack { ArtButton(label: "Like", asset: store.state?.likedLooks.contains(postID) == true ? "icon-liked" : "icon-like") { store.commit { s in if s.likedLooks.contains(postID) { s.likedLooks.remove(postID) } else { s.likedLooks.insert(postID) } } }; Button(store.state?.savedLooks.contains(postID) == true ? "Saved" : "Save") { store.commit { s in if s.savedLooks.contains(postID) { s.savedLooks.remove(postID) } else { s.savedLooks.insert(postID) } } }.foregroundStyle(Palette.pink).font(.tutuSubheadline.bold()); Spacer(); Text(look.created, style: .date).font(.tutuCaption).foregroundStyle(Palette.secondary) }
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
                    HStack { TextField("Add a comment", text: $text, axis: .vertical).lineLimit(1...4).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 22)); ArtButton(label: "Save comment", asset: "icon-send") { let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { return }; if store.commit({ $0.comments.append(LookComment(postID: postID, authorID: store.me.id, text: String(trimmed.prefix(1000)))); $0.drafts["comment-" + postID] = nil }) { text = "" } } }.padding(12).background(Palette.blush)
                }
            } else { EmptyState(title: "This post is unavailable") }
        }.sheet(item: $report) { MemberActions(targetID: $0.id, authorID: $0.author, kind: $0.kind) }
            .onAppear { text = store.state?.drafts["comment-" + postID] ?? "" }
            .onDisappear { if !text.isEmpty { store.commit { $0.drafts["comment-" + postID] = text } }; MoviePlayback.shared.stop() }
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
                if !error.isEmpty { Text(error).font(.tutuSubheadline).foregroundStyle(.red) }
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
    func open(_ url: URL) {
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
            Task { @MainActor [weak self] in guard self?.activeURL == url else { return }; self?.playing = false }
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
                if !error.isEmpty { Text(error).font(.tutuCaption).foregroundStyle(.white) }
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
    func makeUIView(context: Context) -> MovieLayerView { let v = MovieLayerView(); v.playerLayer.videoGravity = .resizeAspect; v.playerLayer.player = player; return v }
    func updateUIView(_ uiView: MovieLayerView, context: Context) { uiView.playerLayer.player = player }
}
final class MovieLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
