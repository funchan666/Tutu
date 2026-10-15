import SwiftUI

struct StyleStudioView: View {
    @EnvironmentObject private var store: AppStore
    @State private var style = "Minimalist"
    @State private var occasion = "Daily"
    @State private var photo: String?
    @State private var media = false
    private let occasions = ["Daily", "Work", "Travel", "Dinner", "Weekend", "Party"]
    var body: some View {
        VStack(spacing: 0) {
            MainHeading(asset: "heading-studio") { InboxEntryButton() }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your next look starts here.").font(.outfit(size: 23, weight: .bold))
                        Text("Pick a direction. Make it your own.").font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                    }
                    Button { media = true } label: {
                        HStack(spacing: 14) {
                            if let photo {
                                MediaArtwork(reference: photo).frame(width: 72, height: 84).clipShape(RoundedRectangle(cornerRadius: 12)).allowsHitTesting(false)
                            } else { Artwork(name: "icon-photo").frame(width: 46, height: 46).allowsHitTesting(false) }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ui: photo == nil ? "Add a little inspiration" : "Your inspiration board").font(.tutuHeadline)
                                Text("Optional photo · describe it in chat").font(.tutuCaption).foregroundStyle(Palette.secondary)
                                Text(ui: photo == nil ? "Add photo" : "Change photo").font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink)
                            }
                            Spacer(minLength: 0)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20)).contentShape(RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Choose your direction").font(.tutuHeadline)
                            Spacer()
                            Text("8 styles").font(.tutuCaption).foregroundStyle(Palette.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                            ForEach(StyleDirection.all) { direction in styleCard(direction) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What's the occasion?").font(.tutuHeadline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(occasions, id: \.self) { value in
                                Button { occasion = value } label: {
                                    Text(ui: value).font(.outfit(size: 13, weight: occasion == value ? .semibold : .regular))
                                        .foregroundStyle(occasion == value ? .white : Palette.ink)
                                        .frame(maxWidth: .infinity).frame(height: 44)
                                        .background { if occasion == value { Image("button-base").resizable() } else { Color.white } }
                                        .clipShape(Capsule()).contentShape(Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(occasion == value ? [.isSelected] : [])
                            }
                        }
                    }
                    NavigationLink(value: Route.stylist(style, occasion)) {
                        Text("Meet your style guide").font(.outfit(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 54).background { Image("button-base").resizable() }
                            .clipShape(Capsule()).contentShape(Capsule())
                    }.buttonStyle(.plain)
                    Text("\(store.stylistFreeRemaining) starter replies left · then \(CoinEconomy.stylistReplyPrice) coins per reply")
                        .font(.tutuCaption).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
                }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 24)
            }
        }.onAppear { photo = store.state?.mediaDrafts["stylist-photo"] }
            .sheet(isPresented: $media) {
                MediaSourceView(title: "Your inspiration", subtitle: "Keep a photo alongside your style ideas.") { selection in
                    do { let reference = try store.importMedia(selection).reference; if store.commit({ $0.mediaDrafts["stylist-photo"] = reference }) { photo = reference } }
                    catch { store.show("Photo not added", error.localizedDescription) }
                }
            }
    }
    private func styleCard(_ direction: StyleDirection) -> some View {
        let selected = style == direction.name
        return Button { style = direction.name } label: {
            VStack(alignment: .leading, spacing: 8) {
                MediaArtwork(reference: direction.image, mode: .fit)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16)).allowsHitTesting(false)
                    .overlay(alignment: .topTrailing) {
                        if selected { Artwork(name: "control-selected").frame(width: 28, height: 28).padding(9).allowsHitTesting(false) }
                    }
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Palette.pink : .clear, lineWidth: 2) }
                Text(ui: direction.name).font(.outfit(size: 15, weight: selected ? .bold : .medium)).foregroundStyle(selected ? Palette.pink : Palette.ink)
                Text(ui: direction.detail).font(.outfit(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(Text(ui: direction.name)).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct StylistRequest: Identifiable {
    let id = UUID().uuidString
    let question: String
    let accountID: String
    let cost: Int
}
struct StylistChatView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let style: String
    let occasion: String
    @State private var text = ""
    @State private var busy = false
    @State private var submittedQuestion: String?
    @State private var error = ""
    @State private var activeTask: Task<Void, Never>?
    @State private var activeTurn: String?
    @State private var sessionID: String?
    @State private var pending: StylistRequest?
    @State private var clearing = false
    @FocusState private var composing: Bool
    private var direction: StyleDirection { StyleDirection.all.first { $0.name == style } ?? StyleDirection.all[0] }
    private var sourceLabel: String { StylistService.modelAvailable ? "On-device AI + style guides" : "Curated style guides" }
    private var suggestions: [String] { ["Help me style a white shirt", "A men's casual look", "Which colors work together?", "Shoes for this outfit", "Easy layers for travel", "A \(style.lowercased()) look for \(occasion.lowercased())"] }
    var body: some View {
        Page(title: "AI Stylist") {
            VStack(spacing: 0) {
                consultationHeader
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if store.state?.stylist.isEmpty != false { welcomeNote }
                            ForEach(store.state?.stylist ?? []) { message in messageRow(message) }
                            if let submittedQuestion { questionRow(submittedQuestion) }
                            if busy { waitingNote }
                            if !error.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(ui: error).font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                                    Button("Try again") { send() }.font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44)
                                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(18)
                    }.scrollDismissesKeyboard(.interactively)
                        .onChange(of: store.state?.stylist.count) { _, _ in scroll(reader) }
                        .onChange(of: busy) { _, _ in scroll(reader) }
                }
                composer
            }
        }.onAppear { text = store.state?.drafts["stylist"] ?? ""; sessionID = store.sessionID }
            .onDisappear {
                cancelReply()
                if sessionID == store.sessionID { store.commit { $0.drafts["stylist"] = text.isEmpty ? nil : text } }
            }
            .onChange(of: phase) { _, newPhase in if newPhase != .active { cancelReply() } }
            .sheet(item: $pending) { request in paymentSheet(request) }
            .sheet(isPresented: $clearing) { clearSheet }
    }
    private var consultationHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MediaArtwork(reference: direction.image, mode: .fit).frame(width: 42, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    (Text(ui: style) + Text(" / ") + Text(ui: occasion)).font(.outfit(size: 15, weight: .semibold))
                    Text(ui: sourceLabel).font(.outfit(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
                Button("Clear") { composing = false; clearing = true }.font(.tutuCaption).foregroundStyle(Palette.secondary).frame(minWidth: 44, minHeight: 44).disabled(busy)
            }
            HStack(spacing: 6) {
                (store.stylistFreeRemaining > 0 ? Text("\(store.stylistFreeRemaining) free replies left") : Text("\(CoinEconomy.stylistReplyPrice) coins / reply"))
                    .font(.outfit(size: 12, weight: .semibold)).foregroundStyle(Palette.pink)
                Spacer()
                NavigationLink(value: Route.wallet) { CoinLabel(amount: store.state?.coins ?? 0) }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 18).padding(.vertical, 12).background(.white.opacity(0.65))
    }
    private var welcomeNote: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LET'S PUT A LOOK TOGETHER").font(.outfit(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.pink)
            Text("A fresh perspective\non what you already own.").font(.outfit(size: 25, weight: .semibold))
            Text("Tell me about a piece, a color or a plan. We'll start with a combination and refine the details.")
                .font(.tutuSubheadline).foregroundStyle(Palette.secondary).lineSpacing(4)
            Text("AI when available, with prepared style guides as a fallback. Photos are kept for inspiration; advice uses your words.")
                .font(.tutuCaption).foregroundStyle(Palette.secondary).lineSpacing(3)
            if let photo = store.state?.mediaDrafts["stylist-photo"] {
                HStack(spacing: 12) {
                    MediaArtwork(reference: photo).frame(width: 54, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Your inspiration\nDescribe the pieces you'd like to style.").font(.tutuCaption).foregroundStyle(Palette.secondary)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 22))
    }
    @ViewBuilder private func messageRow(_ message: ConversationMessage) -> some View {
        if message.outgoing { questionRow(message.text) }
        else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Artwork(name: "tab-studio-active").frame(width: 22, height: 22)
                    Text(ui: message.replySource ?? "Style notes").font(.outfit(size: 11, weight: .semibold)).foregroundStyle(Palette.pink)
                }
                Text(message.text).font(.outfit(size: 15)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 20)).padding(.trailing, 12)
                .transition(.opacity)
        }
    }
    private func questionRow(_ question: String) -> some View {
        HStack {
            Spacer(minLength: 36)
            Text(question).font(.outfit(size: 15)).lineSpacing(3).padding(16)
                .background(Palette.blush, in: RoundedRectangle(cornerRadius: 20))
        }
    }
    private var waitingNote: some View {
        HStack(spacing: 10) {
            Artwork(name: "tab-studio-active").frame(width: 24, height: 24)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let dots = reduceMotion ? 3 : Int(context.date.timeIntervalSinceReferenceDate * 2) % 3 + 1
                Text("Preparing style notes" + String(repeating: ".", count: dots)).font(.tutuSubheadline).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
            Button("Cancel") { cancelReply() }.font(.tutuCaption).foregroundStyle(Palette.pink).frame(minHeight: 44)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Preparing style notes. You can cancel without being charged.")
    }
    private var composer: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { text = suggestion; composing = true } label: {
                            Text(suggestion).font(.outfit(size: 12)).padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.white, in: Capsule()).frame(minHeight: 44)
                        }.buttonStyle(.plain).disabled(busy)
                    }
                }.padding(.horizontal, 16)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your next look…", text: $text, axis: .vertical).font(.tutuSubheadline).lineLimit(1...4)
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 22)).focused($composing).disabled(busy)
                ArtButton(label: "Send style question", asset: "icon-send") { send() }.disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.horizontal, 16)
            (busy ? Text("No charge until your reply is saved.") : Text("\(CoinEconomy.stylistFreeReplies) starter replies per account · then \(CoinEconomy.stylistReplyPrice) coins each"))
                .font(.outfit(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(.top, 8).padding(.bottom, 10).background(Palette.blush)
    }
    private func paymentSheet(_ request: StylistRequest) -> some View {
        VStack(spacing: 16) {
            HStack { Spacer(); ArtButton(label: "Cancel consultation", asset: "nav-close", size: 28) { pending = nil } }
            Artwork(name: "tab-studio-active").frame(width: 42, height: 42)
            Text("One more style idea").font(.outfit(size: 23, weight: .semibold))
            Text("\(request.cost) coins for this reply. AI is used when available; otherwise you'll receive a prepared style guide. Coins are used only after the reply is saved.")
                .font(.tutuSubheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            CoinLabel(amount: store.state?.coins ?? 0)
            PinkButton(title: store.appLanguage.format("Continue · %lld coins", request.cost)) { pending = nil; start(request) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.blush).presentationBackground(Palette.blush).presentationCornerRadius(28)
            .presentationDragIndicator(.hidden).presentationDetents([.height(380), .large])
    }
    private var clearSheet: some View {
        VStack(spacing: 18) {
            Text("A fresh page?").font(.outfit(size: 23, weight: .semibold))
            Text("Clear your conversation on this device. Your remaining free replies and coin balance stay the same.")
                .font(.tutuSubheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            PinkButton(title: "Clear conversation") { if store.commit({ $0.stylist = [] }) { clearing = false } }
            Button("Keep chatting") { clearing = false }.font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.blush)
            .presentationBackground(Palette.blush).presentationCornerRadius(28).presentationDetents([.height(300)])
            .overlay { NoticeOverlay() }
    }
    private func scroll(_ reader: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { reader.scrollTo("bottom", anchor: .bottom) }
    }
    private func send() {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, pending == nil, !question.isEmpty, let account = store.sessionID else { return }
        guard question.count <= 2000 else { error = "Keep your question under 2000 characters."; return }
        composing = false; error = ""
        let request = StylistRequest(question: question, accountID: account, cost: store.stylistReplyCost)
        guard (store.state?.coins ?? 0) >= request.cost else { recharge(request); return }
        if request.cost > 0 { pending = request } else { start(request) }
    }
    private func recharge(_ request: StylistRequest) {
        guard request.accountID == store.sessionID else { return }
        guard store.commit({ $0.drafts["stylist"] = request.question }) else { return }
        store.walletRequest += 1
        store.show("A few more coins", "A style reply costs \(request.cost) coins. Your question is saved; choose a coin pack to continue. Nothing has been deducted.")
    }
    private func start(_ request: StylistRequest) {
        guard !busy, request.accountID == store.sessionID else { return }
        guard (store.state?.coins ?? 0) >= request.cost else { recharge(request); return }
        guard store.commit({ $0.drafts["stylist"] = request.question }) else { return }
        busy = true; error = ""; submittedQuestion = request.question; activeTurn = request.id
        let history = store.state?.stylist ?? []
        activeTask = Task { @MainActor in
            defer { if activeTurn == request.id { busy = false; submittedQuestion = nil; activeTurn = nil } }
            do {
                try await Task.sleep(for: .milliseconds(Int.random(in: 900...1600)))
                let reply = try await StylistService.reply(to: request.question, style: style, occasion: occasion, history: history)
                try Task.checkCancellation()
                guard activeTurn == request.id, request.accountID == store.sessionID else { return }
                if store.stylistReplyCost > 0, (store.state?.coins ?? 0) < store.stylistReplyCost {
                    recharge(request); return
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    if store.saveStylistReply(turnID: request.id, accountID: request.accountID, question: request.question, reply: reply, approvedCost: request.cost) {
                        if text.trimmingCharacters(in: .whitespacesAndNewlines) == request.question { text = "" }
                    } else { error = "Your reply wasn't saved. Your question is still here; no coins were used." }
                }
            } catch {
                guard !Task.isCancelled, activeTurn == request.id, request.accountID == store.sessionID else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private func cancelReply() {
        activeTask?.cancel(); activeTask = nil; activeTurn = nil; busy = false; submittedQuestion = nil
    }
}
