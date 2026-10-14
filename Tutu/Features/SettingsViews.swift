import SwiftUI
import UserNotifications
import MessageUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var legal: LegalPage?
    @State private var confirm: String?
    @State private var busy = false
    var body: some View {
        Page(title: "Settings") {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink(value: Route.security) { row("Account & Security") }.buttonStyle(.plain)
                    NavigationLink(value: Route.privacy) { row("Privacy") }.buttonStyle(.plain)
                    ArtToggle(title: "Daily check-in reminder", value: Binding(get: { store.state?.preferences.notifications ?? false }, set: { enabled in toggleNotifications(enabled) }))
                    NavigationLink(value: Route.language) { row("Language", value: "English") }.buttonStyle(.plain)
                    NavigationLink(value: Route.info("Help & Support")) { row("Help & Support") }.buttonStyle(.plain)
                    NavigationLink(value: Route.info("Community Guidelines")) { row("Community Guidelines") }.buttonStyle(.plain)
                    MenuRow(title: "User Agreement") { legal = .terms }
                    MenuRow(title: "Privacy Policy") { legal = .privacy }
                    MenuRow(title: "Clear cache") { clearCache() }
                    MenuRow(title: "Log out", destructive: true) { confirm = "Log out" }
                    MenuRow(title: "Delete account", destructive: true) { confirm = "Delete account" }
                    Text("Tutu · 1.0.0").font(.caption).foregroundStyle(Palette.secondary).padding(16)
                }.padding(16)
            }
        }.sheet(item: $legal) { LegalWebView(page: $0) }
            .sheet(isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) { confirmation }
    }
    func row(_ title: String, value: String = "") -> some View { HStack { Text(title).font(.subheadline.bold()); Spacer(); Text(value).font(.caption).foregroundStyle(Palette.secondary); Artwork(name: "nav-back").rotationEffect(.degrees(180)).frame(width: 14, height: 14) }.padding(20).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16)) }
    var confirmation: some View {
        VStack(spacing: 20) {
            Text(confirm == "Log out" ? "See you soon?" : "Delete your account?").font(.title2.bold())
            Text(confirm == "Log out" ? "Your profile and saved looks will be here when you log back in." : "This deletes this device's account, profile, photos, looks, conversations, and wallet records. This cannot be undone. No remote account is connected.").font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            PinkButton(title: confirm ?? "Continue", busy: busy) {
                busy = true
                Task { @MainActor in
                    await Task.yield()
                    do {
                        if confirm == "Delete account" { try store.deleteAccount(); store.show("Account deleted", "Your account and its saved data have been removed from this device.") }
                        else { store.signOut(); store.show("Logged out", "You have been signed out.") }
                        confirm = nil
                    } catch { store.show("Could not delete account", error.localizedDescription) }
                    busy = false
                }
            }
            Button("Keep my account") { confirm = nil }.font(.headline).foregroundStyle(Palette.pink).disabled(busy).frame(minHeight: 44)
        }.padding(24).background(Palette.blush).presentationDetents([.medium]).interactiveDismissDisabled(busy).overlay { NoticeOverlay() }
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
                content.title = "A little reward awaits"; content.body = "Visit Daily Check for today's coins and activity points."; content.sound = .default
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
                    Text("Your space, your choice").font(.title2.bold())
                    ArtToggle(title: "Private profile", value: preference(\.privateProfile))
                    ArtToggle(title: "Show activity", value: preference(\.showActivity))
                    ArtToggle(title: "Allow room invitations", value: preference(\.allowInvites))
                    Text("These preferences are saved with your profile. Sharing is unavailable until a service is connected.").font(.caption).foregroundStyle(Palette.secondary)
                    Text("Blocked members").font(.title3.bold()).padding(.top, 16)
                    let blocked = store.state?.blocked ?? []
                    if blocked.isEmpty { EmptyState(title: "Your block list is empty") }
                    ForEach(blocked.sorted(), id: \.self) { id in HStack { Avatar(person: store.person(id)); Text(store.person(id).name).font(.headline); Spacer(); Button("Unblock") { store.commit { $0.blocked.remove(id) } }.font(.subheadline.bold()).foregroundStyle(Palette.pink).frame(minHeight: 44) }.panel() }
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
                Text("Your account").font(.title2.bold())
                Text(account?.appleUserID == nil ? account?.email ?? "" : "Signed in with Apple").font(.headline)
                Text("Your profile is saved on this device. No cloud account is connected.").font(.subheadline).foregroundStyle(Palette.secondary)
                if account?.appleUserID == nil {
                    Field(title: "Current password", text: $current, secure: true)
                    Field(title: "New password", text: $new, secure: true)
                    Field(title: "Confirm new password", text: $repeated, secure: true)
                    if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.red) }
                    PinkButton(title: "Update password", busy: busy) { changePassword() }
                }
                NavigationLink(value: Route.info("Account data")) { Text("About your saved data").font(.subheadline.bold()).foregroundStyle(Palette.pink).padding(.vertical, 16) }
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
    var body: some View { Page(title: "Language") { VStack(spacing: 18) { HStack { Text("English").font(.headline); Spacer(); Artwork(name: "control-check").frame(width: 24, height: 24) }.panel(); Text("English is currently available.").font(.subheadline).foregroundStyle(Palette.secondary); Spacer() }.padding(20) } }
}
struct InformationView: View {
    @EnvironmentObject private var store: AppStore
    let kind: String
    @State private var legal: LegalPage?
    var sections: [(String, String)] {
        switch kind {
        case "Coins": return [("A little appreciation", "Coins let you add gifts to your backpack. Choose the recipient from a profile, chat, or room."), ("Clear pricing", "Each item shows its coin cost. A quantity of three costs three times the displayed price. Bonus coins are included in the total shown on each pack."), ("Safe delivery", "Items are deducted only when gift delivery succeeds. If delivery is unavailable, your gift stays in your backpack."), ("Apple purchases", "The amount displayed by Apple is the final local price. Pending or unverified transactions never add coins. Consumable coin purchases are not restored like subscriptions.")]
        case "Daily Check": return [("One visit, one reward", "Check in once each calendar day using your device's current time zone. Reopening the app doesn't reset the daily limit."), ("Seven days together", "Rewards are 10, 20, 10, 20, 10, 20, then 100 coins. A missed day starts a new streak. After day seven, a new seven-day cycle begins."), ("A little progress", "Each check-in adds 10 activity points. Every 100 points adds one level. Your balance and level update across the app.")]
        case "My Level": return [("Level \(store.state?.level ?? 1)", "You have \(store.state?.points ?? 0) activity points. Your next level starts at \((store.state?.level ?? 1) * 100) points."), ("Keep showing up", "Daily Check adds 10 activity points. Levels recognise participation and do not unlock private communication.")]
        case "Community Guidelines": return [("A community for adults", "Tutu is for people aged 18 and older. Share style, music, and conversation with kindness."), ("Respect every person", "No harassment, hate, threats, impersonation, scams, or sharing another person's private information. Respect boundaries and consent."), ("Share responsibly", "Only share media you have permission to use. Sexual exploitation, nudity, graphic violence, dangerous activity, and illegal material are not permitted."), ("Keep rooms welcoming", "Hosts should remove disruptive participants. Never record or share another person's voice or image without permission."), ("Report and block", "Open the more menu on a profile, post, photo, or comment to report the exact item or block its author. A report that fails to send remains a draft; it has not reached moderators."), ("Gifts are optional", "Do not pressure anyone to buy or send gifts. Gifts do not grant a right to attention, a reply, or a private call.")]
        case "Account data": return [("Stored on your device", "Your profile, preferences, relationships, looks, comments, and wallet records are stored in this app's private storage. Password verification data is protected by Keychain."), ("Leaving or deleting", "Logging out keeps your saved account. Deleting your account removes its credentials and associated saved content. It does not cancel an Apple transaction or delete your Apple ID."), ("Your original files", "Media selected from Photos is copied into the app. Deleting an in-app photo or account never deletes your original Photos library items.")]
        default: return [("Make yourself at home", "Explore Style Live and Party, collect inspiration in Discover, and shape your profile in your own way."), ("Keep your circle comfortable", "Follow from profiles and search. To send a private message or call, both people must follow each other and the connection must be verified."), ("Something went wrong?", "Retry a failed action after checking your connection. Unsent messages remain in the conversation. Gift delivery failures leave your inventory intact."), ("Policies and support", "For app support, email \(LegalLinks.supportEmail). For content safety, email \(LegalLinks.moderationEmail). Both contacts are listed in the linked policies.")]
        }
    }
    var body: some View { Page(title: kind) { ScrollView { VStack(alignment: .leading, spacing: 18) { ForEach(Array(sections.enumerated()), id: \.offset) { index, section in VStack(alignment: .leading, spacing: 12) { Text(String(format: "%02d", index + 1)).font(.caption.bold()).foregroundStyle(Palette.pink); Text(section.0).font(.title3.bold()); Text(section.1).font(.subheadline).lineSpacing(5).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading).panel() }; if kind == "Help & Support" { MenuRow(title: "User Agreement") { legal = .terms }; MenuRow(title: "Privacy Policy") { legal = .privacy } } }.padding(20) } }.sheet(item: $legal) { LegalWebView(page: $0) } }
}
struct MemberActions: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let targetID: String
    let authorID: String
    let kind: String
    @State private var reporting = false
    @State private var reason = "Harassment or bullying"
    @State private var detail = ""
    @State private var result = ""
    @State private var mail: MailDraft?
    var body: some View {
        VStack(spacing: 18) {
            HStack { Text(reporting ? "Report \(kind)" : "More options").font(.headline); Spacer(); ArtButton(label: "Close", asset: "nav-close") { dismiss() } }
            if reporting {
                ScrollView { VStack(spacing: 10) { ForEach(["Harassment or bullying", "Sexual or unsafe content", "Spam or scam", "Privacy violation", "Underage user", "Other"], id: \.self) { option in Button { reason = option } label: { HStack { Text(option).font(.subheadline); Spacer(); if reason == option { Artwork(name: "control-check").frame(width: 22, height: 22) } }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain) }; Field(title: "Additional details", text: $detail) } }
                if !result.isEmpty { Text(result).font(.subheadline).foregroundStyle(Palette.secondary) }
                PinkButton(title: "Submit report") {
                    let draft = ReportDraft(targetID: targetID, authorID: authorID, kind: kind, reason: reason, detail: String(detail.prefix(1000)))
                    if store.commit({ $0.reports.removeAll { $0.targetID == targetID && !$0.delivered }; $0.reports.append(draft) }) {
                        if MFMailComposeViewController.canSendMail() {
                            mail = MailDraft(recipient: LegalLinks.moderationEmail, subject: "Tutu safety report · " + kind,
                                             body: "Report ID: \(draft.id)\nType: \(kind)\nContent ID: \(targetID)\nAuthor ID: \(authorID)\nReason: \(reason)\n\n\(detail)")
                        } else {
                            result = "Your report is saved but hasn't been submitted. Set up Mail on this device, or email " + LegalLinks.moderationEmail + "."
                        }
                    }
                }
            } else if authorID == store.me.id {
                if kind == "post" {
                    MenuRow(title: "Delete this look", destructive: true) {
                        if store.commit({ value in
                            value.looks.removeAll { $0.id == targetID }
                            value.comments.removeAll { $0.postID == targetID }
                            value.likedLooks.remove(targetID); value.savedLooks.remove(targetID)
                        }) { dismiss() }
                    }
                } else { Text("This is your content.").font(.subheadline) }
            } else {
                MenuRow(title: "Report") { reporting = true }
                MenuRow(title: store.state?.blocked.contains(authorID) == true ? "Unblock" : "Block", destructive: true) { if store.state?.blocked.contains(authorID) == true { store.commit { $0.blocked.remove(authorID) } } else { store.block(authorID) }; dismiss() }
            }
        }.padding(24).background(Palette.blush).presentationDetents(reporting ? [.large] : [.height(270)]).overlay { NoticeOverlay() }
            .onAppear { if let draft = store.state?.reports.last(where: { $0.targetID == targetID && !$0.delivered }) { reason = draft.reason; detail = draft.detail } }
            .sheet(item: $mail) { draft in MailComposer(draft: draft) { response in
                mail = nil
                result = response == .sent ? "Your report was handed to Mail for delivery. Delivery confirmation isn't available here." : "Your report hasn't been sent. Your details are saved."
            } }
    }
}
