import SwiftUI

enum Palette {
    static let pink = Color(red: 0.95, green: 0.20, blue: 0.73)
    static let blush = Color(red: 1, green: 0.94, blue: 0.99)
    static let ink = Color(red: 0.12, green: 0.08, blue: 0.16)
    static let secondary = Color(red: 0.46, green: 0.41, blue: 0.48)
}
struct Artwork: View {
    let name: String
    var body: some View { Image(name).resizable().scaledToFit().accessibilityHidden(true) }
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
    var body: some View { Button(action: action) { Artwork(name: asset).frame(width: size, height: size).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(label) }
}
struct PinkButton: View {
    let title: String
    var asset: String? = nil
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                if let asset, !busy { Image(asset).resizable().scaledToFit() }
                else { Image("button-base").resizable().scaledToFill(); Text(busy ? "Please wait…" : title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8) }
            }.frame(maxWidth: .infinity).frame(height: 54).clipped().contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(busy).accessibilityLabel(busy ? "Please wait" : title)
    }
}
struct Pill: View {
    let title: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.system(size: 14, weight: selected ? .bold : .medium, design: .rounded)).lineLimit(1).fixedSize(horizontal: true, vertical: false).padding(.horizontal, 18).padding(.vertical, 12).foregroundStyle(selected ? .white : Palette.ink).background(selected ? Palette.pink : Color.white.opacity(0.8), in: Capsule()) }.buttonStyle(.plain)
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
                        Text(title)
                            .font(.system(size: 14, weight: selection == title ? .bold : .regular, design: .rounded))
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
                    Text(title).font(.system(size: 13, design: .rounded))
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
    var body: some View { HStack { ArtButton(label: "Back", asset: "nav-back") { dismiss() }; Spacer(); Text(title).font(.system(size: 18, weight: .semibold, design: .rounded)); Spacer(); Color.clear.frame(width: 44, height: 44) }.padding(.horizontal, 12).padding(.bottom, 6) }
}
struct MainHeading<Trailing: View>: View {
    let asset: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 0) {
            Artwork(name: asset).frame(maxWidth: asset == "heading-studio" ? 219 : 128, maxHeight: 34, alignment: .leading)
            Spacer(minLength: 6); trailing
        }.frame(height: 44).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
    }
}
struct MediaArtwork: View {
    @EnvironmentObject private var store: AppStore
    let reference: String
    var mode: ContentMode = .fill
    var body: some View {
        GeometryReader { geo in
            Group {
                if let url = store.mediaURL(reference), let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable() }
                else { Image(reference.isEmpty || reference.hasPrefix("media/") ? "wardrobe-placeholder" : reference).resizable() }
            }.aspectRatio(contentMode: mode).frame(width: geo.size.width, height: geo.size.height).clipped()
        }.accessibilityLabel(reference == "wardrobe-placeholder" ? "Wardrobe illustration" : "Photo")
    }
}
struct Avatar: View {
    let person: Person
    var size: CGFloat = 50
    var body: some View { MediaArtwork(reference: person.avatar).frame(width: size, height: size).clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 2)).accessibilityLabel(person.name) }
}
struct EmptyState: View {
    let title: String
    var message = ""
    var body: some View { VStack(spacing: 12) { Artwork(name: "empty-state").frame(width: 130, height: 140); Text(title).font(.headline); if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center) } }.padding(28).frame(maxWidth: .infinity) }
}
struct Field: View {
    let title: String
    @Binding var text: String
    var secure = false
    var body: some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 15, weight: .bold, design: .rounded)); Group { if secure { SecureField(title, text: $text) } else { TextField(title, text: $text) } }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 17)).tint(Palette.pink).textInputAutocapitalization(secure || title.contains("Email") ? .never : .sentences).autocorrectionDisabled(secure || title.contains("Email")) }.padding(.vertical, 5) }
}
struct MenuRow: View {
    let title: String
    var value = ""
    var destructive = false
    var action: () -> Void
    var body: some View { Button(action: action) { HStack { Text(title).fontWeight(.semibold); Spacer(); if !value.isEmpty { Text(value).foregroundStyle(Palette.secondary).lineLimit(1) }; Artwork(name: "nav-back").rotationEffect(.degrees(180)).frame(width: 15, height: 15) }.font(.system(size: 15, design: .rounded)).foregroundStyle(destructive ? .red : Palette.ink).padding(.vertical, 20).padding(.horizontal, 18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) }
}
struct ArtToggle: View {
    let title: String
    @Binding var value: Bool
    var body: some View { Button { value.toggle() } label: { HStack { Text(title).fontWeight(.semibold).foregroundStyle(Palette.ink); Spacer(); Artwork(name: value ? "control-on" : "control-off").frame(width: 56, height: 32) }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value ? "On" : "Off").accessibilityAddTraits(.isButton) }
}
struct CoinLabel: View {
    let amount: Int
    var body: some View { HStack(spacing: 5) { Artwork(name: "icon-coin").frame(width: 22, height: 22); Text(amount.formatted()).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit() } }
}
struct NoticeOverlay: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if let notice = store.notice {
            ZStack { Color.black.opacity(0.35).ignoresSafeArea(); VStack(spacing: 18) { Artwork(name: "brand-mascot").frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 18)); Text(notice.title).font(.title3.bold()); Text(notice.message).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Palette.secondary); PinkButton(title: "Got it") { store.notice = nil } }.padding(24).background(Palette.blush, in: RoundedRectangle(cornerRadius: 26)).padding(28).frame(maxWidth: 440) }.accessibilityAddTraits(.isModal).zIndex(100)
        }
    }
}
extension View {
    func panel() -> some View { padding(16).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20)) }
}
