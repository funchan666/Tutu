import SwiftUI

struct StyleStudioView: View {
    @EnvironmentObject private var store: AppStore
    @State private var style = "Minimalist"
    @State private var occasion = "Daily"
    @State private var photo: String?
    @State private var media = false
    let styles = ["Minimalist", "Streetwear", "Vintage"]
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-studio") { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 6) {
                        if let photo { MediaArtwork(reference: photo).frame(height: 148).clipShape(RoundedRectangle(cornerRadius: 12)) }
                        Text("Upload Your Photo").font(.system(size: 14, design: .rounded))
                        Text("Get personalized outfit ideas with AI").font(.system(size: 13, design: .rounded)).multilineTextAlignment(.center)
                        PinkButton(title: "Add Photo", asset: "button-add-photo") { media = true }
                            .frame(width: 200).padding(.top, 8)
                    }.foregroundStyle(Palette.secondary).padding(.vertical, 30).padding(.horizontal, 18)
                        .frame(maxWidth: .infinity).background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(red: 0.91, green: 0.78, blue: 0.87), style: StrokeStyle(lineWidth: 1, dash: [1, 3])))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose Your Style").font(.system(size: 16, weight: .bold, design: .rounded))
                        HStack(spacing: 14) {
                            ForEach(styles, id: \.self) { item in
                                Button { style = item } label: {
                                    VStack(spacing: 10) {
                                        Image("style-" + item.lowercased()).resizable().scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style == item ? Palette.pink.opacity(0.55) : .clear, lineWidth: 1.5))
                                        Text(item).font(.system(size: 12, design: .rounded)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.8)
                                    }.frame(maxWidth: .infinity)
                                }.buttonStyle(.plain).accessibilityAddTraits(style == item ? [.isSelected] : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Occasion").font(.system(size: 16, weight: .bold, design: .rounded))
                        SoftChoices(titles: ["Daily", "Work", "Travel"], selection: $occasion)
                    }
                    NavigationLink(value: Route.stylist(style, occasion)) {
                        Artwork(name: "button-generate").frame(height: 64).frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("Get outfit advice")
                }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
            }
        }.onAppear { photo = store.state?.mediaDrafts["stylist-photo"] }
            .sheet(isPresented: $media) {
                MediaSourceView { selection in
                    do { let reference = try store.importMedia(selection).reference; if store.commit({ $0.mediaDrafts["stylist-photo"] = reference }) { photo = reference } }
                    catch { store.show("Photo not added", error.localizedDescription) }
                }
            }
    }
}
struct StylistChatView: View {
    @EnvironmentObject private var store: AppStore
    let style: String
    let occasion: String
    @State private var text = ""
    @State private var busy = false
    @State private var error = ""
    @State private var activeTask: Task<Void, Never>?
    @State private var sessionID: String?
    var body: some View {
        Page(title: "AI Stylist") {
            VStack(spacing: 0) {
                HStack { Text(style + " · " + occasion).font(.caption.bold()).foregroundStyle(Palette.pink); Spacer(); Button("Clear chat") { store.commit { $0.stylist = [] } }.font(.caption).foregroundStyle(Palette.secondary).disabled(busy).frame(minHeight: 44) }.padding(.horizontal, 18)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(spacing: 18) {
                            HStack { Text("Hello! Tell me what you're wearing and what you'd like to try. I can help with outfit ideas from your description.").font(.subheadline).padding(16).foregroundStyle(.white).background(Color(red: 0.22, green: 0.65, blue: 0.95), in: RoundedRectangle(cornerRadius: 18)); Spacer(minLength: 20) }
                            ForEach(store.state?.stylist ?? []) { message in MessageBubble(message: message) }
                            if busy { Text("Finding your next look…").font(.subheadline).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                            if !error.isEmpty { VStack(alignment: .leading, spacing: 12) { Text(error).font(.subheadline); Button("Try again") { send() }.font(.headline).foregroundStyle(Palette.pink) }.panel() }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(18)
                    }.scrollDismissesKeyboard(.interactively).onChange(of: store.state?.stylist.count) { _, _ in withAnimation { reader.scrollTo("bottom", anchor: .bottom) } }
                }
                if store.state?.stylist.isEmpty != false {
                    ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(["Help me style a white shirt", "A relaxed \(occasion.lowercased()) outfit", "Which colours work together?"], id: \.self) { suggestion in Pill(title: suggestion) { text = suggestion } } }.padding(.horizontal, 16) }
                }
                HStack { TextField("Describe your look or ask a question…", text: $text, axis: .vertical).lineLimit(1...5).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 24)); ArtButton(label: "Send to AI Stylist", asset: "icon-send") { send() }.disabled(busy) }.padding(14).background(Palette.blush)
            }
        }.onAppear { text = store.state?.drafts["stylist"] ?? ""; sessionID = store.sessionID }
            .onDisappear { activeTask?.cancel(); if sessionID == store.sessionID { store.commit { $0.drafts["stylist"] = text } } }
    }
    func send() {
        let submittedText = text
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !question.isEmpty else { return }
        guard question.count <= 2000 else { error = "Keep your question under 2000 characters."; return }
        busy = true; error = ""; let id = store.sessionID; let history = store.state?.stylist ?? []
        activeTask = Task { @MainActor in
            defer { busy = false }
            do {
                let reply = try await StylistService.reply(to: question, style: style, occasion: occasion, history: history)
                guard !Task.isCancelled, id == store.sessionID else { return }
                if store.commit({ $0.stylist.append(ConversationMessage(text: question, outgoing: true, status: "Complete")); $0.stylist.append(ConversationMessage(text: reply, outgoing: false, status: "Complete")); $0.drafts["stylist"] = text == submittedText ? nil : text }) { if text == submittedText { text = "" } }
            } catch { guard !Task.isCancelled, id == store.sessionID else { return }; self.error = error.localizedDescription; store.commit { $0.drafts["stylist"] = text } }
        }
    }
}
