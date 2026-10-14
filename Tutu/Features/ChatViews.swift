import SwiftUI
import AVFoundation

struct InboxView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Page(title: "Messages") {
            ScrollView { VStack(spacing: 14) {
                NavigationLink(value: Route.systemMessages) { HStack(spacing: 14) { Artwork(name: "icon-notification").frame(width: 52, height: 52); VStack(alignment: .leading, spacing: 5) { Text("System Messages").font(.tutuHeadline); Text("Updates for your account").font(.tutuSubheadline).foregroundStyle(Palette.secondary) }; Spacer() }.panel() }.buttonStyle(.plain)
                let ids = Set((store.state?.conversations.keys.map { $0 } ?? []) + (store.state?.mediaDrafts.keys.filter { Catalog.people.map(\.id).contains($0) } ?? []) + (store.state?.drafts.keys.filter { Catalog.people.map(\.id).contains($0) } ?? []))
                ForEach(store.people.filter { ids.contains($0.id) }) { person in NavigationLink(value: Route.chat(person.id)) { HStack(spacing: 12) { Avatar(person: person); VStack(alignment: .leading, spacing: 6) { Text(person.name).font(.tutuHeadline); Text(store.state?.drafts[person.id].flatMap { $0.isEmpty ? nil : "Draft: " + $0 } ?? store.conversation(person.id).last?.text ?? "Say hello").font(.tutuSubheadline).foregroundStyle(Palette.secondary).lineLimit(1) }; Spacer() }.panel() }.buttonStyle(.plain) }
                if store.people.filter({ ids.contains($0.id) }).isEmpty { EmptyState(title: "A hello can start something", message: "Open a member's profile and choose Start a Chat.") }
            }.padding(16) }
        }
    }
}
struct SystemMessagesView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View { Page(title: "System Messages") { ScrollView { VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 12) { Text("Welcome to your style world").font(.tutuHeadline); Text("Find inspiration, collect your favourite looks, and make your profile your own.").font(.tutuSubheadline).foregroundStyle(Palette.secondary) }.panel()
        ForEach(Array((store.state?.ledger ?? []).prefix(20))) { item in VStack(alignment: .leading, spacing: 8) { Text(item.title).font(.tutuHeadline); Text("\(item.amount > 0 ? "+" : "")\(item.amount) coins").font(.tutuSubheadline); Text(item.date, style: .date).font(.tutuCaption).foregroundStyle(Palette.secondary) }.frame(maxWidth: .infinity, alignment: .leading).panel() }
    }.padding(20) } } }
}
struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    let personID: String
    @State private var text = ""
    @State private var more = false
    @State private var tools = false
    @State private var gifts = false
    @State private var media = false
    @State private var voice = false
    @State private var call: CallDestination?
    @State private var report: ReportTarget?
    @State private var attachment: String?
    @State private var session: String?
    var person: Person { store.person(personID) }
    var body: some View {
        Page(title: person.name) {
            VStack(spacing: 0) {
                HStack { NavigationLink(value: Route.profile(personID)) { HStack { Avatar(person: person, size: 38); Text("Profile").font(.tutuSubheadline.bold()) } }.buttonStyle(.plain); Spacer(); Button("Video call") { beginCall(true) }.font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44); ArtButton(label: "More", asset: "nav-more") { more = true } }.padding(.horizontal, 16)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(spacing: 18) {
                            VStack(spacing: 12) { Avatar(person: person, size: 78); Text(person.name).font(.tutuTitle3.bold()); Text(person.bio).font(.tutuSubheadline).multilineTextAlignment(.center).foregroundStyle(Palette.secondary); InterestTags(values: person.interests); ProfileStats(person: person) }.panel().padding(.top, 8)
                            ForEach(store.conversation(personID)) { message in
                                if message.outgoing { MessageBubble(message: message) { retry(message) } }
                                else {
                                    Button { report = ReportTarget(id: message.id, author: personID, kind: "chat message") } label: { MessageBubble(message: message) }
                                        .buttonStyle(.plain).accessibilityHint("Report or block this message")
                                }
                            }
                            if let attachment {
                                HStack {
                                    if attachment.hasSuffix(".jpg") { MediaArtwork(reference: attachment).frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 12)) }
                                    else { Artwork(name: "icon-camera").frame(width: 44, height: 44) }
                                    Text(attachment.hasSuffix(".jpg") ? "Photo attached" : "Video attached").font(.tutuCaption)
                                    Spacer()
                                    Button("Remove") { if store.commit({ $0.mediaDrafts[personID] = nil }) { self.attachment = nil } }.foregroundStyle(Palette.pink)
                                }.panel()
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(16)
                    }.scrollDismissesKeyboard(.interactively).onChange(of: store.conversation(personID).map(\.id)) { _, _ in withAnimation { reader.scrollTo("bottom", anchor: .bottom) } }
                }
                VStack(spacing: 12) {
                    HStack { ArtButton(label: "More tools", asset: "nav-create", size: 34) { tools.toggle() }; TextField("Say hi…", text: $text, axis: .vertical).lineLimit(1...5).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 23)); ArtButton(label: "Send message", asset: "icon-send") { send() } }
                    if tools { HStack(spacing: 22) { ArtButton(label: "Photo or video", asset: "icon-photo") { media = true }; ArtButton(label: "Voice message", asset: "icon-mic") { voice = true }; ArtButton(label: "Send a gift", asset: "icon-gift") { gifts = true }; Button("Voice call") { beginCall(false) }.font(.tutuCaption.bold()).foregroundStyle(Palette.pink); Spacer() }.padding(.horizontal, 10) }
                }.padding(12).background(Palette.blush)
            }
        }.onAppear { text = store.state?.drafts[personID] ?? ""; attachment = store.state?.mediaDrafts[personID]; session = store.sessionID }
            .task(id: text) { try? await Task.sleep(for: .milliseconds(450)); guard !Task.isCancelled, session == store.sessionID, !store.isPersonHidden(personID) else { return }; store.commit { $0.drafts[personID] = text } }
            .onDisappear { if session == store.sessionID, !store.isPersonHidden(personID) { store.commit { $0.drafts[personID] = text } } }
            .sheet(isPresented: $more) { MemberActions(targetID: personID, authorID: personID, kind: "member") }
            .sheet(item: $report) { MemberActions(targetID: $0.id, authorID: $0.author, kind: $0.kind) }
            .sheet(isPresented: $gifts) { GiftDeliveryView(personID: personID) }
            .sheet(isPresented: $media) { MediaSourceView(allowVideo: true) { selection in do { let item = try store.importMedia(selection); if store.commit({ $0.mediaDrafts[personID] = item.reference }) { attachment = item.reference } } catch { store.show("Attachment not added", error.localizedDescription) } } }
            .sheet(isPresented: $voice) { VoiceRecorderView(personID: personID) }
            .fullScreenCover(item: $call) { CallView(personID: personID, video: $0.video).environmentObject(store).overlay { NoticeOverlay() } }
            .moderationVisibility(hidden: store.isPersonHidden(personID))
    }
    func beginCall(_ video: Bool) {
        guard !store.isPersonHidden(personID) else { store.show("Member blocked", "Unblock this member first."); return }
        guard store.state?.following.contains(personID) == true, store.followerIDs.contains(personID) else { store.show("A little connection first", "Follow each other before starting a call."); return }
        call = CallDestination(video: video)
    }
    func send() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil else { return }
        guard store.canContact(personID) else { return }
        // Only a server acknowledgement may create a delivered message.
        store.show("Message not sent", "Messaging is unavailable. Your text and attachment are still here.")
    }
    func retry(_ message: ConversationMessage) { text = message.text; send() }
}
struct CallDestination: Identifiable { let id = UUID(); let video: Bool }
struct MessageBubble: View {
    let message: ConversationMessage
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 6) {
            Text(message.created, style: .time).font(.tutuCaption2).foregroundStyle(Palette.secondary)
            HStack { if message.outgoing { Spacer(minLength: 40) }; Text(message.text).font(.tutuSubheadline).lineSpacing(4).padding(16).foregroundStyle(.white).background(message.outgoing ? Palette.pink : Color(red: 0.22, green: 0.65, blue: 0.95), in: RoundedRectangle(cornerRadius: 18)); if !message.outgoing { Spacer(minLength: 40) } }
            if message.status == "Not sent", let retry { Button("Not sent · Retry", action: retry).font(.tutuCaption).foregroundStyle(Palette.pink) }
        }.frame(maxWidth: .infinity, alignment: message.outgoing ? .trailing : .leading)
    }
}
@MainActor final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var recording = false
    @Published var hasRecording = false
    @Published var error = ""
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var url: URL?
    private var generation = UUID()
    func start() async {
        clean()
        let ticket = UUID(); generation = ticket
        guard await AVCaptureDevice.requestAccess(for: .audio) else { error = "Allow Microphone access in the Settings app to record a message."; return }
        guard generation == ticket, !Task.isCancelled else { return }
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker]); try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a"); self.url = url
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            recorder?.delegate = self
            guard recorder?.record(forDuration: 60) == true else { throw TutuFailure.message("Recording couldn't start.") }
            recording = true; hasRecording = false; error = ""
        } catch { self.error = error.localizedDescription; stop() }
    }
    func stop() { generation = UUID(); recorder?.stop(); recording = false; hasRecording = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    func listen() { guard let url else { return }; do { try AVAudioSession.sharedInstance().setCategory(.playback); try AVAudioSession.sharedInstance().setActive(true); player = try AVAudioPlayer(contentsOf: url); player?.play() } catch { self.error = "Couldn't play the recording." } }
    func clean() { generation = UUID(); recorder?.stop(); player?.stop(); if let url { try? FileManager.default.removeItem(at: url) }; recording = false; hasRecording = false; recorder = nil; player = nil; url = nil; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) { Task { @MainActor in guard self.recorder === recorder else { return }; self.recording = false; self.hasRecording = flag; if !flag { self.error = "Recording failed. Please try again." }; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } }
}
struct VoiceRecorderView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var recorder = VoiceRecorder()
    let personID: String
    var body: some View { VStack(spacing: 22) { HStack { Text("Voice message").font(.tutuHeadline); Spacer(); ArtButton(label: "Close", asset: "nav-close") { dismiss() } }; Text(recorder.recording ? "Recording · up to 60 seconds" : recorder.hasRecording ? "Ready to listen" : "Tap to record your message").font(.tutuSubheadline); ArtButton(label: recorder.recording ? "Stop recording" : "Record", asset: "icon-voice-record", size: 96) { if recorder.recording { recorder.stop() } else { Task { await recorder.start() } } }; if !recorder.error.isEmpty { Text(recorder.error).font(.tutuCaption).foregroundStyle(.red) }; if recorder.hasRecording { Button("Listen") { recorder.listen() }.foregroundStyle(Palette.pink).frame(minHeight: 44); PinkButton(title: "Send voice message") { if store.canContact(personID) { store.show("Message not sent", "Voice messaging is unavailable. You can listen to your recording and try again.") } } } }.padding(24).background(Palette.blush).presentationDetents([.medium]).overlay { NoticeOverlay() }.onDisappear { recorder.clean() }.onChange(of: phase) { _, state in if state != .active { recorder.stop() } } }
}
