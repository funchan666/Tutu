import SwiftUI
import UserNotifications

private enum AccountSessionAction: String, Identifiable {
    case logOut = "Log out", deleteAccount = "Delete account"
    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var legal: LegalPage?
    @State private var confirm: AccountSessionAction?
    @State private var pendingExit: AccountSessionAction?
    var body: some View {
        Page(title: "Settings") {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink(value: Route.security) { row("Account & Security") }.buttonStyle(.plain)
                    NavigationLink(value: Route.privacy) { row("Privacy") }.buttonStyle(.plain)
                    ArtToggle(title: "Daily check-in reminder", value: Binding(get: { store.state?.preferences.notifications ?? false }, set: { enabled in toggleNotifications(enabled) }))
                    NavigationLink(value: Route.language) { row("Language", value: store.appLanguage.nativeName) }.buttonStyle(.plain)
                    NavigationLink(value: Route.info("Help & Support")) { row("Help & Support") }.buttonStyle(.plain)
                    NavigationLink(value: Route.info("Community Guidelines")) { row("Community Guidelines") }.buttonStyle(.plain)
                    MenuRow(title: "User Agreement") { legal = .terms }
                    MenuRow(title: "Privacy Policy") { legal = .privacy }
                    MenuRow(title: "Clear cache") { clearCache() }
                    MenuRow(title: "Log out", destructive: true) { confirm = .logOut }
                    MenuRow(title: "Delete account", destructive: true) { confirm = .deleteAccount }
                    Text("Tutu · 1.0.0").font(.tutuCaption).foregroundStyle(Palette.secondary).padding(16)
                }.padding(16)
            }
        }.sheet(item: $legal) { LegalWebView(page: $0) }
            .sheet(item: $confirm, onDismiss: {
                guard let action = pendingExit else { return }
                pendingExit = nil
                store.finishAccountSession(deleting: action == .deleteAccount)
            }) { action in confirmation(action) }
    }
    func row(_ title: String, value: String = "") -> some View { HStack { Text(ui: title).font(.tutuSubheadline.bold()); Spacer(); Text(value).font(.tutuCaption).foregroundStyle(Palette.secondary); Artwork(name: "nav-back").rotationEffect(.degrees(180)).frame(width: 14, height: 14) }.padding(20).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16)) }
    private func confirmation(_ action: AccountSessionAction) -> some View {
        VStack(spacing: 20) {
            Text(ui: action == .logOut ? "See you soon?" : "Delete your account?").font(.tutuTitle2.bold())
            Text(ui: action == .logOut ? "Your profile and saved looks will be here when you log back in." : "This deletes this device's account, profile, photos, looks, conversations, and wallet records. This cannot be undone. No remote account is connected.").font(.tutuSubheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            PinkButton(title: action.rawValue, busy: store.accountExit != nil) {
                pendingExit = action
                confirm = nil
            }
            Button(LocalizedStringKey(action == .logOut ? "Cancel" : "Keep my account")) { confirm = nil }.font(.tutuHeadline).foregroundStyle(Palette.pink).disabled(store.accountExit != nil).frame(minHeight: 44)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.blush).presentationBackground(Palette.blush).presentationDetents([.medium, .large]).overlay { NoticeOverlay() }
    }
    func toggleNotifications(_ enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        if !enabled {
            if store.commit({ $0.preferences.notifications = false }) { center.removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]) }
            return
        }
        let session = store.sessionID
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard store.sessionID == session else { return }
                guard granted else { store.commit { $0.preferences.notifications = false }; store.show("Notifications are off", "You can allow notifications for Tutu in the Settings app."); return }
                let content = UNMutableNotificationContent()
                content.title = store.appLanguage.text("A little reward awaits"); content.body = store.appLanguage.text("Visit Daily Check for today's coins and activity points."); content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 18), repeats: true)
                try await center.add(UNNotificationRequest(identifier: "daily-checkin", content: content, trigger: trigger))
                guard store.sessionID == session else { center.removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]); return }
                if !store.commit({ $0.preferences.notifications = true }) { center.removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]) }
            } catch { store.show("Notifications unavailable", "Please try again later.") }
        }
    }
    func clearCache() {
        do {
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Tutu")
            if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
            URLCache.shared.removeAllCachedResponses(); store.show("Cache cleared", "Your profile, photos, messages, and wallet are safe.")
        } catch { store.show("Cache not cleared", "Please try again.") }
    }
}
struct PrivacyView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Page(title: "Privacy") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your space, your choice").font(.tutuTitle2.bold())
                    ArtToggle(title: "Private profile", value: preference(\.privateProfile))
                    ArtToggle(title: "Show activity", value: preference(\.showActivity))
                    ArtToggle(title: "Allow room invitations", value: preference(\.allowInvites))
                    Text("These preferences are saved with your profile. Sharing is unavailable until a service is connected.").font(.tutuCaption).foregroundStyle(Palette.secondary)
                    Text("Blocked members").font(.tutuTitle3.bold()).padding(.top, 16)
                    let blocked = store.state?.blocked ?? []
                    if blocked.isEmpty { EmptyState(title: "Your block list is empty") }
                    ForEach(blocked.sorted(), id: \.self) { id in HStack { Avatar(person: store.person(id)); Text(store.person(id).name).font(.tutuHeadline); Spacer(); Button("Unblock") { store.unblock(id) }.font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44) }.panel() }
                }.padding(20)
            }
        }
    }
    func preference(_ path: WritableKeyPath<UserPreferences, Bool>) -> Binding<Bool> { Binding(get: { store.state?.preferences[keyPath: path] ?? false }, set: { value in store.commit { $0.preferences[keyPath: path] = value } }) }
}
struct SecurityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var busy = false
    @State private var error = ""
    @State private var account: LocalAccount?
    var body: some View {
        Page(title: "Account & Security") {
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                Text("Your account").font(.tutuTitle2.bold())
                Text(account?.appleUserID == nil ? account?.email ?? "" : "Signed in with Apple").font(.tutuHeadline)
                Text("Your profile is saved on this device. No cloud account is connected.").font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                if account?.appleUserID == nil {
                    Field(title: "Current password", text: $current, secure: true)
                    Field(title: "New password", text: $new, secure: true)
                    Field(title: "Confirm new password", text: $repeated, secure: true)
                    if !error.isEmpty { Text(ui: error).font(.tutuSubheadline).foregroundStyle(.red) }
                    PinkButton(title: "Update password", busy: busy) { changePassword() }
                }
                NavigationLink(value: Route.info("Account data")) { Text("About your saved data").font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).padding(.vertical, 16) }
            }.padding(20) }.scrollDismissesKeyboard(.interactively)
        }.onAppear { do { account = try AccountVault.load().first { $0.id == store.sessionID } } catch { self.error = error.localizedDescription } }
    }
    func changePassword() {
        guard let account, account.appleUserID == nil, new.count >= 8, new == repeated else { error = "Use matching passwords with at least 8 characters."; return }
        busy = true; error = ""; let oldPassword = current; let password = new; let accountID = store.sessionID
        Task {
            defer { busy = false }
            do {
                let pair = try await Task.detached { () -> (Data, Data) in
                    guard AccountVault.matches(try AccountVault.hash(oldPassword, salt: account.salt), account.verifier) else { throw TutuFailure.message("Your current password is incorrect.") }
                    let salt = try AccountVault.salt(); return (salt, try AccountVault.hash(password, salt: salt))
                }.value
                guard store.sessionID == accountID else { return }
                var accounts = try AccountVault.load()
                guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
                accounts[index].salt = pair.0; accounts[index].verifier = pair.1; try AccountVault.save(accounts)
                self.account = accounts[index]; current = ""; new = ""; repeated = ""; store.show("Password updated", "Your new password has been saved securely.")
            } catch { self.error = error.localizedDescription }
        }
    }
}
struct LanguageView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Page(title: "Language") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Make Tutu feel like you").font(.tutuTitle2.bold())
                    Text("Choose your app language. Changes apply immediately and stay saved on this device.")
                        .font(.tutuSubheadline).foregroundStyle(Palette.secondary).padding(.bottom, 12)
                    ForEach(AppLanguage.allCases) { language in
                        Button { store.selectLanguage(language) } label: {
                            HStack {
                                Text(verbatim: language.nativeName).font(.tutuHeadline)
                                Spacer()
                                if store.appLanguage == language {
                                    Artwork(name: "control-check").frame(width: 24, height: 24)
                                }
                            }.padding(20).frame(maxWidth: .infinity, minHeight: 64)
                                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(store.appLanguage == language ? Palette.pink : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).accessibilityAddTraits(store.appLanguage == language ? [.isSelected] : [])
                    }
                    Text("Member posts, messages and original media stay in their original language.")
                        .font(.tutuCaption).foregroundStyle(Palette.secondary).padding(.top, 8)
                }.padding(20)
            }
        }
    }
}
struct InformationView: View {
    @EnvironmentObject private var store: AppStore
    let kind: String
    @State private var legal: LegalPage?
    var sections: [(String, String)] {
        switch kind {
        case "Coins": return [("Your style fund", "Unlock the Runway Ribbon avatar frame for 240 coins, or collect gifts for 40–1,800 coins each. Wear an owned gift as your profile charm at no additional cost."), ("Always free", "Member messages, voice and video chats, browsing, likes, comments and posting never cost coins."), ("Style consultations", "Each account gets 5 starter replies, then each reply costs 20 coins. AI is used when available; otherwise replies come from prepared style guides. You confirm each paid reply. Failed or canceled replies cost nothing, and clearing chat does not reset the allowance."), ("Before you spend", "Every coin purchase shows a confirmation and your remaining balance. If you need more coins, Get Coins opens without deducting anything. Gift delivery is currently unavailable; collectibles remain yours to wear."), ("Apple purchases", "Tap a pack to get that product from Apple. The Apple purchase sheet shows the final local price. Only verified transactions add coins. Your wallet is saved on this device, and consumable coins are not restored like subscriptions."), ("Your welcome drop", "New accounts receive 360 coins once, after completing their profile and entering the home screen. Coins never expire.")]
        case "Daily Check": return [("One visit, one reward", "Check in once each calendar day using your device's current time zone. Reopening the app doesn't reset the daily limit."), ("Seven days together", "Rewards are 10, 20, 10, 20, 10, 20, then 100 coins. A missed day starts a new streak. After day seven, a new seven-day cycle begins."), ("A little progress", "Each check-in adds 10 activity points. Every 100 points adds one level. Your balance and level update across the app.")]
        case "My Level": return [(store.appLanguage.format("Level %lld", store.state?.level ?? 1), store.appLanguage.format("You have %lld activity points. Your next level starts at %lld points.", store.state?.points ?? 0, (store.state?.level ?? 1) * 100)), ("Keep showing up", "Daily Check adds 10 activity points. Levels recognise participation and do not unlock private communication.")]
        case "Community Guidelines": return [("A community for adults", "Tutu is for people aged 18 and older. Share style, music, and conversation with kindness."), ("Respect every person", "No harassment, hate, threats, impersonation, scams, or sharing another person's private information. Respect boundaries and consent."), ("Share responsibly", "Only share media you have permission to use. Sexual exploitation, nudity, graphic violence, dangerous activity, and illegal material are not permitted."), ("Keep rooms welcoming", "Hosts should remove disruptive participants. Never record or share another person's voice or image without permission."), ("Report and block", "Open the more menu on a profile, post, photo, or comment to report the exact item or block its author. Reports and block choices are saved on this device. Reported content is hidden immediately; blocking a member also hides their rooms, posts and chats."), ("Gifts are optional", "Do not pressure anyone to buy or send gifts. Gifts do not grant a right to attention, a reply, or a private call.")]
        case "Account data": return [("Stored on your device", "Your profile, preferences, relationships, looks, comments, and wallet records are stored in this app's private storage. Password verification data is protected by Keychain."), ("Leaving or deleting", "Logging out keeps your saved account. Deleting your account removes its credentials and associated saved content. It does not cancel an Apple transaction or delete your Apple ID."), ("Your original files", "Media selected from Photos is copied into the app. Deleting an in-app photo or account never deletes your original Photos library items.")]
        default: return [("Make yourself at home", "Explore Style Live and Party, collect inspiration in Discover, and shape your profile in your own way."), ("Keep your circle comfortable", "Follow from profiles and search. To send a private message or call, both people must follow each other and the connection must be verified."), ("Something went wrong?", "Retry a failed action after checking your connection. Unsent messages remain in the conversation. Gift delivery failures leave your inventory intact."), ("Policies and support", store.appLanguage.format("For app support, email %@. For content safety, email %@. Both contacts are listed in the linked policies.", LegalLinks.supportEmail, LegalLinks.moderationEmail))]
        }
    }
    var body: some View { Page(title: kind) { ScrollView { VStack(alignment: .leading, spacing: 18) { ForEach(Array(sections.enumerated()), id: \.offset) { index, section in VStack(alignment: .leading, spacing: 12) { Text(String(format: "%02d", index + 1)).font(.tutuCaption.bold()).foregroundStyle(Palette.pink); Text(ui: section.0).font(.tutuTitle3.bold()); Text(ui: section.1).font(.tutuSubheadline).lineSpacing(5).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading).panel() }; if kind == "Help & Support" { MenuRow(title: "User Agreement") { legal = .terms }; MenuRow(title: "Privacy Policy") { legal = .privacy } } }.padding(20) } }.sheet(item: $legal) { LegalWebView(page: $0) } }
}
struct MemberActions: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let targetID: String
    let authorID: String
    let kind: String
    var contentPreview: String? = nil
    var contentContext: String? = nil
    @State private var reporting = false
    @State private var reason = ""
    @State private var detail = ""
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(verbatim: reporting ? store.appLanguage.format("Report %@", store.appLanguage.text(contentName)) : store.appLanguage.format("%@ options", store.appLanguage.text(contentName))).font(.outfit(size: 23, weight: .bold, design: .rounded))
                Spacer()
                ArtButton(label: "Close", asset: "nav-close", size: 32) { dismiss() }
            }
            if !reporting {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(person: store.person(authorID), size: 42).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.person(authorID).name).font(.tutuSubheadline.bold())
                        Text(contentPreview ?? ("@" + store.person(authorID).handle))
                            .font(.tutuCaption).foregroundStyle(Palette.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 8)
            }
            if reporting {
                Text("Choose a reason").font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(["Harassment or bullying", "Sexual or unsafe content", "Spam or scam", "Privacy violation", "Underage user", "Other"], id: \.self) { option in
                            Button { reason = option } label: {
                                HStack {
                                    Text(ui: option).font(.tutuSubheadline)
                                    Spacer()
                                    if reason == option { Artwork(name: "control-check").frame(width: 22, height: 22) }
                                }.padding(14).frame(minHeight: 48)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay { if reason == option { RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.pink.opacity(0.5), lineWidth: 1) } }
                            }.buttonStyle(.plain).accessibilityAddTraits(reason == option ? [.isSelected] : [])
                        }
                        Field(title: "Additional details", text: $detail)
                            .onChange(of: detail) { _, value in if value.count > 1000 { detail = String(value.prefix(1000)) } }
                    }
                }.scrollDismissesKeyboard(.interactively)
                PinkButton(title: "Report") {
                    if store.submitReport(targetID: targetID, authorID: authorID, kind: kind, reason: reason, detail: detail, context: contentContext) { dismiss() }
                }.disabled(reason.isEmpty).opacity(reason.isEmpty ? 0.45 : 1)
            } else if authorID == store.me.id {
                if kind == "post" {
                    MenuRow(title: "Delete this look", destructive: true) {
                        if store.commit({ value in
                            value.looks.removeAll { $0.id == targetID }
                            value.comments.removeAll { $0.postID == targetID }
                            value.likedLooks.remove(targetID); value.savedLooks.remove(targetID)
                        }) { dismiss() }
                    }
                } else { Text("This is your content.").font(.tutuSubheadline) }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        safetyRow("Report \(contentName)", detail: "Choose a reason. This content will be hidden.") { reporting = true }
                        if kind != "member" {
                            safetyRow("Hide this \(contentName)", detail: "Remove it from your view on this device.") {
                                if store.hideContent(targetID: targetID, authorID: authorID, kind: kind) { dismiss() }
                            }
                        }
                        safetyRow(store.state?.blocked.contains(authorID) == true ? "Unblock member" : "Block member",
                                  detail: "Hide their posts, rooms and conversations.", destructive: true) {
                            let saved = store.state?.blocked.contains(authorID) == true ? store.unblock(authorID) : store.block(authorID)
                            if saved { dismiss() }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(Palette.ink).background(Palette.blush)
            .presentationDetents(reporting ? [.large] : [.height(kind == "member" ? 400 : 490), .large])
            .presentationCornerRadius(30).presentationDragIndicator(.hidden).presentationBackground(Palette.blush)
            .overlay { NoticeOverlay() }
    }
    private var contentName: String { kind == "post" ? "look" : kind }
    private func safetyRow(_ title: String, detail: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ui: title).font(.tutuSubheadline.bold()).foregroundStyle(destructive ? Color.red : Palette.ink)
                    Text(ui: detail).font(.tutuCaption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Artwork(name: "nav-back").rotationEffect(.degrees(180)).frame(width: 13, height: 16)
            }.padding(17).frame(minHeight: 74).background(.white, in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
