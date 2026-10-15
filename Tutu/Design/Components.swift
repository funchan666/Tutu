import SwiftUI

enum Palette {
    static let pink = Color(red: 0.95, green: 0.20, blue: 0.73)
    static let blush = Color(red: 1, green: 0.94, blue: 0.99)
    static let ink = Color(red: 0.12, green: 0.08, blue: 0.16)
    static let secondary = Color(red: 0.46, green: 0.41, blue: 0.48)
}
struct Artwork: View {
    @Environment(\.locale) private var locale
    let name: String
    private var buttonTitle: String? {
        ["button-edit": "Edit Profile", "button-join": "Join", "button-profile": "Profile",
         "button-message": "Message", "button-add-photo": "Add a photo", "button-save": "Save",
         "button-generate": "Meet your style guide", "button-create-room": "Create a room"][name]
    }
    var body: some View {
        Group {
            if locale.language.languageCode?.identifier != "en", let buttonTitle {
                Text(ui: buttonTitle).font(.tutuSubheadline.bold()).foregroundStyle(.white)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.7)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Image("button-base").resizable() }
            } else { Image(name).resizable().scaledToFit() }
        }.accessibilityHidden(true)
    }
}
struct SceneBackground: View {
    var name = "screen-background"
    var body: some View { GeometryReader { geo in Image(name).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped() }.ignoresSafeArea() }
}
struct ArtButton: View {
    let label: String
    let asset: String
    var size: CGFloat = 44
    var action: () -> Void
    var body: some View { Button(action: action) { Artwork(name: asset).frame(width: size, height: size).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(Text(ui: label)) }
}
struct FollowButton: View {
    @EnvironmentObject private var store: AppStore
    let personID: String
    var size: CGFloat = 44
    var contentStyle = false
    private var following: Bool { store.state?.following.contains(personID) == true }
    private var asset: String {
        if contentStyle { return following ? "control-content-followed" : "control-content-follow" }
        return following ? "control-selected" : "control-follow"
    }
    var body: some View {
        if personID != store.me.id {
            ArtButton(label: following ? "Unfollow" : "Follow", asset: asset, size: size) {
                store.toggleFollow(personID)
            }
            .accessibilityValue(Text(ui: following ? "Following" : "Not following"))
            .accessibilityAddTraits(following ? [.isSelected] : [])
        }
    }
}
struct PinkButton: View {
    @Environment(\.locale) private var locale
    let title: String
    var asset: String? = nil
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                if let asset, !busy, locale.language.languageCode?.identifier == "en" { Image(asset).resizable().scaledToFit() }
                else { Image("button-base").resizable().scaledToFill(); Text(ui: busy ? "Please wait…" : title).font(.outfit(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8) }
            }.frame(maxWidth: .infinity).frame(height: 54).clipped().contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(busy).accessibilityLabel(Text(ui: busy ? "Please wait" : title))
    }
}
struct Pill: View {
    let title: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(ui: title).font(.outfit(size: 14, weight: selected ? .bold : .medium, design: .rounded)).lineLimit(1).fixedSize(horizontal: true, vertical: false).padding(.horizontal, 18).padding(.vertical, 12).foregroundStyle(selected ? .white : Palette.ink).background(selected ? Palette.pink : Color.white.opacity(0.8), in: Capsule()) }.buttonStyle(.plain)
    }
}
struct SectionTabs: View {
    let titles: [String]
    @Binding var selection: String
    var compact = false
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 22 : 28) {
                ForEach(titles, id: \.self) { title in
                    Button { selection = title } label: {
                        Text(ui: title)
                            .font(.outfit(size: 14, weight: selection == title ? .bold : .regular, design: .rounded))
                            .foregroundStyle(selection == title ? Palette.ink : Palette.secondary)
                            .underline(selection == title, color: Palette.ink)
                            .fixedSize().frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == title ? [.isSelected] : [])
                }
            }.padding(.horizontal, 16)
        }
    }
}
struct SoftChoices: View {
    let titles: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 10) {
            ForEach(titles, id: \.self) { title in
                Button { selection = title } label: {
                    Text(ui: title).font(.outfit(size: 13, design: .rounded))
                        .frame(maxWidth: .infinity).frame(minHeight: 46)
                        .background(selection == title ? Palette.blush : Color(white: 0.98), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selection == title ? Palette.pink.opacity(0.45) : .clear, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == title ? [.isSelected] : [])
            }
        }
    }
}
struct Page<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View { VStack(spacing: 0) { PageHeader(title: title); content.frame(maxWidth: .infinity, maxHeight: .infinity) }.background(SceneBackground()).toolbar(.hidden, for: .navigationBar).foregroundStyle(Palette.ink) }
}
struct PageHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View { HStack { ArtButton(label: "Back", asset: "nav-back") { dismiss() }; Spacer(); Text(ui: title).font(.outfit(size: 18, weight: .semibold, design: .rounded)); Spacer(); Color.clear.frame(width: 44, height: 44) }.padding(.horizontal, 12).padding(.bottom, 6) }
}
struct MainHeading<Trailing: View>: View {
    @Environment(\.locale) private var locale
    private var title: String { ["heading-profile": "Profile", "heading-style-live": "Style Live", "heading-party": "Party", "heading-studio": "Create Your Look", "heading-discover": "Discover"][asset] ?? "Tutu" }
    let asset: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 0) {
            if locale.language.languageCode?.identifier == "en" {
                Artwork(name: asset).frame(maxWidth: asset == "heading-studio" ? 219 : 128, maxHeight: 34, alignment: .leading)
            } else {
                Text(ui: title).font(.outfit(size: 26, weight: .bold)).foregroundStyle(Palette.pink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6); trailing
        }.frame(height: 44).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
    }
}
/// A shared inbox destination for all five tabs, separate from member profiles.
struct InboxEntryButton: View {
    var body: some View {
        NavigationLink(value: Route.inbox) {
            Artwork(name: "icon-room-chat")
                .frame(width: 30, height: 30).allowsHitTesting(false)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.92), in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Messages")
            .accessibilityHint("Open your conversations and system messages")
            .accessibilityIdentifier("inbox-entry")
    }
}
struct MediaArtwork: View {
    @EnvironmentObject private var store: AppStore
    let reference: String
    var mode: ContentMode = .fill
    var alignment: Alignment = .center
    var body: some View {
        GeometryReader { geo in
            Group {
                if let url = store.mediaURL(reference), let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable() }
                else { Image(reference.isEmpty || reference.hasPrefix("media/") ? "wardrobe-placeholder" : reference).resizable() }
            }.aspectRatio(contentMode: mode).frame(width: geo.size.width, height: geo.size.height, alignment: alignment).clipped()
        }.accessibilityLabel(reference == "wardrobe-placeholder" ? "Wardrobe illustration" : "Photo")
    }
}
struct Avatar: View {
    @EnvironmentObject private var store: AppStore
    let person: Person
    var size: CGFloat = 50
    var body: some View {
        MediaArtwork(reference: person.avatar).frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay {
                if person.id == store.me.id, store.state?.equippedFrame == CoinEconomy.runwayFrame {
                    Artwork(name: "runway-frame").frame(width: size * 1.25, height: size * 1.25).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if person.id == store.me.id, let gift = store.state?.featuredGift, (store.state?.inventory[gift] ?? 0) > 0 {
                    Artwork(name: "gift-" + gift).frame(width: size * 0.38, height: size * 0.38).offset(x: 4, y: 4).allowsHitTesting(false)
                }
            }.accessibilityLabel(person.name)
    }
}
struct EmptyState: View {
    let title: String
    var message = ""
    var body: some View { VStack(spacing: 12) { Artwork(name: "empty-state").frame(width: 130, height: 140); Text(ui: title).font(.tutuHeadline); if !message.isEmpty { Text(ui: message).font(.tutuSubheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center) } }.padding(28).frame(maxWidth: .infinity) }
}
struct Field: View {
    let title: String
    @Binding var text: String
    var secure = false
    var body: some View { VStack(alignment: .leading, spacing: 10) { Text(ui: title).font(.outfit(size: 15, weight: .bold, design: .rounded)); Group { if secure { SecureField(LocalizedStringKey(title), text: $text) } else { TextField(LocalizedStringKey(title), text: $text) } }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 17)).tint(Palette.pink).textInputAutocapitalization(secure || title.contains("Email") ? .never : .sentences).autocorrectionDisabled(secure || title.contains("Email")) }.padding(.vertical, 5) }
}
struct MenuRow: View {
    let title: String
    var value = ""
    var destructive = false
    var action: () -> Void
    var body: some View { Button(action: action) { HStack { Text(ui: title).fontWeight(.semibold); Spacer(); if !value.isEmpty { Text(ui: value).foregroundStyle(Palette.secondary).lineLimit(1) }; Artwork(name: "nav-back").rotationEffect(.degrees(180)).frame(width: 15, height: 15) }.font(.outfit(size: 15, design: .rounded)).foregroundStyle(destructive ? .red : Palette.ink).padding(.vertical, 20).padding(.horizontal, 18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) }
}
struct ArtToggle: View {
    let title: String
    @Binding var value: Bool
    var body: some View { Button { value.toggle() } label: { HStack { Text(ui: title).fontWeight(.semibold).foregroundStyle(Palette.ink); Spacer(); Artwork(name: value ? "control-on" : "control-off").frame(width: 56, height: 32) }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).accessibilityLabel(Text(ui: title)).accessibilityValue(Text(ui: value ? "On" : "Off")).accessibilityAddTraits(.isButton) }
}
struct CoinLabel: View {
    let amount: Int
    var body: some View { HStack(spacing: 5) { Artwork(name: "icon-coin").frame(width: 22, height: 22); Text(amount.formatted()).font(.outfit(size: 16, weight: .bold, design: .rounded)).monospacedDigit() } }
}
struct NoticeOverlay: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if let notice = store.notice {
            ZStack { Color.black.opacity(0.35).ignoresSafeArea(); VStack(spacing: 18) { Artwork(name: notice.success ? "control-selected" : "brand-mascot").frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 18)); Text(ui: notice.title).font(.tutuTitle3.bold()); Text(ui: notice.message).font(.tutuSubheadline).multilineTextAlignment(.center).foregroundStyle(Palette.secondary); PinkButton(title: notice.success ? "Done" : "Got it") { store.notice = nil } }.padding(24).background(Palette.blush, in: RoundedRectangle(cornerRadius: 26)).padding(28).frame(maxWidth: 440) }.accessibilityAddTraits(.isModal).zIndex(100)
        }
    }
}
extension View {
    func panel() -> some View { padding(16).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20)) }
}


/// Covers every pushed content surface, including destinations opened before a safety action.
private struct ModerationVisibility: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        Group {
            if hidden {
                Page(title: "Content hidden") { EmptyState(title: "This content is hidden") }
            } else { content }
        }
    }
}
extension View {
    func moderationVisibility(hidden: Bool) -> some View { modifier(ModerationVisibility(hidden: hidden)) }
}

/// Only app-owned labels use this initializer; member names, posts and chat text stay verbatim.
extension Text {
    init(ui value: String) { self.init(LocalizedStringKey(value)) }
}

struct AccountExitOverlay: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false
    var body: some View {
        if let progress = store.accountExit {
            ZStack {
                Color.black.opacity(0.34).ignoresSafeArea()
                VStack(spacing: 18) {
                    Artwork(name: progress.succeeded ? "control-selected" : "tab-party-active")
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(progress.succeeded || reduceMotion ? 0 : (rotating ? 360 : 0)))
                        .animation(progress.succeeded || reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false), value: rotating)
                    Text(ui: progress.succeeded
                         ? (progress.deleting ? "Account deleted" : "Logged out")
                         : (progress.deleting ? "Deleting your account…" : "Logging out…"))
                        .font(.tutuTitle3.bold())
                    Text(ui: progress.succeeded ? "Returning to welcome…" : "Please wait while we finish.")
                        .font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                }
                .multilineTextAlignment(.center).padding(30).frame(maxWidth: 330)
                .background(Palette.blush, in: RoundedRectangle(cornerRadius: 28)).padding(24)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits([.isModal, .updatesFrequently])
            .onAppear { rotating = true }.onDisappear { rotating = false }.zIndex(200)
        }
    }
}


/// Shared live status artwork. Motion is decorative, never an audio-level meter.
struct RoomLiveBadge: View {
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    var title = "Live"
    var animated = true
    private var moves: Bool { visible && animated && scene == .active && !reduceMotion }

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if moves {
                    signal.phaseAnimator([CGFloat(0.78), 1.06, 0.88, 1.0]) { content, phase in
                        content.scaleEffect(x: 1, y: phase)
                            .opacity(phase < 0.85 ? 0.82 : 1)
                    } animation: { _ in .easeInOut(duration: 0.45) }
                } else { signal }
            }.frame(width: 17, height: 17)
            Text(ui: title).font(.outfit(size: 11, weight: .bold))
                .foregroundStyle(.white).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Palette.ink.opacity(0.96), in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.pink.opacity(0.72), lineWidth: 0.8) }
        .fixedSize().allowsHitTesting(false)
        .accessibilityElement(children: .ignore).accessibilityLabel(Text(ui: title))
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private var signal: some View {
        Image("live-signal").resizable().scaledToFit().accessibilityHidden(true)
    }
}
