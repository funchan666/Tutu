import SwiftUI
import UserNotifications

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var state: ProfileState?
    @Published var notice: Notice?
    @Published var tab = 0
    @Published var socialScope: String?
    var socialState: AtelierSocialState { socialScope.flatMap { state?.social?[$0] } ?? AtelierSocialState() }
    @Published var returnToLogin = false
    @Published private(set) var appLanguage = AppLanguage.saved
    @Published private(set) var accountExit: AccountExitProgress?

    func selectLanguage(_ language: AppLanguage) {
        guard language != appLanguage else { return }
        if state != nil, !commit({ $0.preferences.language = language.rawValue }) { return }
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
        appLanguage = language
        syncReminder()
    }
    @Published var minimizedRoom: StyleRoom?
    @Published var coinPrompt: CoinSpend?
    @Published var walletRequest = 0
    private let files = FileManager.default
    let root: URL
    var sessionID: String? { state?.person.id }
    var me: Person { state?.person ?? Person(id: "", name: "Your name", handle: "you", photos: [], catalog: false) }
    var followerIDs: Set<String> {
        guard let state else { return [] }
        return Set(state.followers.subtracting(state.catalogArrivalIDs).filter { !isPersonHidden($0) })
    }
    func isContentHidden(_ kind: String, _ id: String) -> Bool {
        state?.hiddenContent?.contains(ModerationContent(kind: kind, id: id)) == true
    }
    func isPersonHidden(_ id: String) -> Bool {
        Catalog.reservedProfileIDs.contains(id) || state?.blocked.contains(id) == true || isContentHidden("member", id)
    }
    func isRoomHidden(_ room: StyleRoom) -> Bool {
        isPersonHidden(room.hostID) || isContentHidden("room", room.id) || isContentHidden("photo", room.cover)
    }
    func isMessageHidden(_ item: RoomMessage) -> Bool {
        isPersonHidden(item.personID) || isContentHidden("message", item.id)
    }
    var people: [Person] { Catalog.people.filter { !isPersonHidden($0.id) }.map { person($0.id) } }
    var looks: [Look] {
        ((state?.looks ?? []) + socialState.posts + Catalog.looks).filter {
            !isPersonHidden($0.authorID) && !isContentHidden("post", $0.id)
                && !$0.media.contains(where: { isContentHidden("photo", $0) })
        }
    }
    var likedLooks: [Look] {
        looks.filter { state?.likedLooks.contains($0.id) == true }
    }
    var rooms: [StyleRoom] { ((state?.rooms ?? []) + Catalog.rooms).filter { !isRoomHidden($0) } }
    var comments: [LookComment] {
        (Catalog.comments + (state?.comments ?? [])).filter { !isPersonHidden($0.authorID) && !isContentHidden("comment", $0.id) }
    }
    var discoverLooks: [Look] {
        let visible = looks
        let ownVideos = visible.filter { $0.authorID == me.id && $0.video != nil }
        return ownVideos + Catalog.discoverIDs.compactMap { id in visible.first { $0.id == id && $0.video != nil } }
    }
    func likeCount(for look: Look) -> Int {
        let baseline = Catalog.items.first { "look-" + $0.id == look.id }?.likeCount ?? 0
        return baseline + (state?.likedLooks.contains(look.id) == true ? 1 : 0)
    }
    @discardableResult func setLookLiked(_ id: String, liked: Bool) -> Bool {
        guard looks.contains(where: { $0.id == id }) else { return false }
        return commit { value in
            if liked { value.likedLooks.insert(id) } else { value.likedLooks.remove(id) }
        }
    }
    @discardableResult func addComment(to postID: String, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, looks.contains(where: { $0.id == postID }) else { return false }
        let comment = LookComment(postID: postID, authorID: me.id, text: String(trimmed.prefix(1000)))
        return commit { $0.comments.append(comment); $0.drafts["comment-" + postID] = nil }
    }
    func conversation(_ personID: String) -> [ConversationMessage] {
        guard !isPersonHidden(personID) else { return [] }
        return (state?.conversations[personID] ?? []).filter { !isContentHidden("chat message", $0.id) }
    }
    init() {
        root = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tutu", isDirectory: true)
        do { try files.createDirectory(at: root, withIntermediateDirectories: true); try recoverDeletionJournal() }
        catch { notice = Notice(title: "Storage unavailable", message: "Changes cannot be saved on this device right now.") }
    }
    func restoreSession(isCurrent: @MainActor () -> Bool) async {
        guard state == nil, let id = UserDefaults.standard.string(forKey: "activeProfile"), UUID(uuidString: id) != nil else { return }
        let profileURL = location(id)
        do {
            let restored = try await Task.detached(priority: .userInitiated) { () throws -> ProfileState? in
                let accounts = try AccountVault.load()
                guard accounts.contains(where: { $0.id == id }) else { return nil }
                return try JSONDecoder().decode(ProfileState.self, from: Data(contentsOf: profileURL))
            }.value
            guard !Task.isCancelled, isCurrent(), UserDefaults.standard.string(forKey: "activeProfile") == id else { return }
            state = try restored.map { try profileWithDefaultAvatar($0) }
            if restored != nil { syncReminder() }
        } catch {
            guard isCurrent(), !Task.isCancelled else { return }
            notice = Notice(title: "Could not open your profile", message: "Your saved data was left unchanged. Please sign in again.")
        }
    }
    func person(_ id: String) -> Person {
        var value = id == me.id ? me : Catalog.people.first(where: { $0.id == id }) ?? Person(id: id, name: "Member", handle: "member")
        if let presence = socialState.presence[id] { value.isOnline = presence.expires > Date().timeIntervalSince1970 * 1000 && presence.online }
        value.photos.removeAll { isContentHidden("photo", $0) }
        if isContentHidden("photo", value.avatar) { value.avatar = "brand-mascot" }
        return value
    }
    private func location(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("profile.json") }
    private func recoverDeletionJournal() throws {
        let ids = Set(try AccountVault.load().map(\.id))
        for staged in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where staged.lastPathComponent.hasSuffix(".deleting") {
            let id = String(staged.lastPathComponent.dropLast(".deleting".count))
            guard UUID(uuidString: id) != nil else { continue }
            if ids.contains(id) {
                let destination = root.appendingPathComponent(id, isDirectory: true)
                if !files.fileExists(atPath: destination.path) { try files.moveItem(at: staged, to: destination) }
            } else { try files.removeItem(at: staged) }
        }
    }
    private func read(_ id: String) throws -> ProfileState {
        try profileWithDefaultAvatar(JSONDecoder().decode(ProfileState.self, from: Data(contentsOf: location(id))))
    }
    private func profileWithDefaultAvatar(_ profile: ProfileState) throws -> ProfileState {
        var updated = profile
        if updated.walletInstance == nil { updated.walletInstance = UUID() }
        if (profile.person.avatar.isEmpty || profile.person.avatar == "brand-mascot"), Catalog.profileAvatar != "brand-mascot" {
            updated.person.avatar = Catalog.profileAvatar
        }
        try write(updated)
        return updated
    }
    private func write(_ value: ProfileState) throws {
        try files.createDirectory(at: location(value.person.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: location(value.person.id), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    @discardableResult func commit(_ operation: (inout ProfileState) throws -> Void) -> Bool {
        guard accountExit == nil else { return false }
        guard var next = state else { show("Sign in required", "Sign in to keep your changes."); return false }
        do { try operation(&next); try write(next); state = next; return true }
        catch { show("Could not save", error.localizedDescription); return false }
    }
    func contentDidChange() {
        objectWillChange.send()
        if let profile = state, let updated = try? profileWithDefaultAvatar(profile) { state = updated }
    }
    func installAuthenticatedProfile(email: String, name: String, appleID: String?) throws {
        var accounts = try AccountVault.load()
        let existing = accounts.first { account in
            if let appleID { return account.appleUserID == appleID }
            return account.appleUserID == nil && account.email == email
        }
        if let existing { state = try read(existing.id) }
        else {
            let id = UUID().uuidString
            var profile = ProfileState(person: Person(id: id, name: String(name.prefix(40)), handle: "style" + id.prefix(6).lowercased(), birthday: nil, avatar: Catalog.profileAvatar, photos: [], catalog: false))
            profile.walletInstance = UUID(); profile.welcomeEligible = true
            try write(profile)
            accounts.append(LocalAccount(id: id, email: email, salt: Data(), verifier: Data(), appleUserID: appleID))
            do { try AccountVault.save(accounts) } catch { try? files.removeItem(at: location(id)); throw error }
            state = profile
        }
        UserDefaults.standard.set(sessionID, forKey: "activeProfile"); returnToLogin = false; tab = 0; syncReminder()
    }
    func signOut() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]); coinPrompt = nil; notice = nil; state = nil; minimizedRoom = nil; tab = 0; returnToLogin = false; UserDefaults.standard.removeObject(forKey: "activeProfile") }
    func finishAccountSession(deleting: Bool) {
        guard accountExit == nil, let profile = state else { return }
        let id = profile.person.id
        notice = nil
        accountExit = AccountExitProgress(deleting: deleting, succeeded: false)
        let accountRoot = root
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
                if deleting {
                    try await Task.detached(priority: .userInitiated) {
                        try Self.removeAccountData(id: id, root: accountRoot, profile: profile)
                    }.value
                } else {
                    UserDefaults.standard.removeObject(forKey: "activeProfile")
                }
                guard sessionID == id else { accountExit = nil; return }
                accountExit = AccountExitProgress(deleting: deleting, succeeded: true)
                try await Task.sleep(for: .milliseconds(1300))
                guard sessionID == id else { accountExit = nil; return }
                signOut()
                accountExit = nil
            } catch {
                accountExit = nil
                show(deleting ? "Could not delete account" : "Could not log out", error.localizedDescription)
            }
        }
    }

    nonisolated private static func removeAccountData(id: String, root: URL, profile: ProfileState) throws {
        let files = FileManager.default
        let accounts = try AccountVault.load()
        let source = root.appendingPathComponent(id, isDirectory: true)
        let staged = root.appendingPathComponent(id + ".deleting", isDirectory: true)
        if files.fileExists(atPath: staged.path), !files.fileExists(atPath: source.path) { try files.moveItem(at: staged, to: source) }
        if files.fileExists(atPath: source.path) { try files.moveItem(at: source, to: staged) }
        do { try AccountVault.save(accounts.filter { $0.id != id }) }
        catch {
            if files.fileExists(atPath: staged.path) { try? files.moveItem(at: staged, to: source) }
            throw error
        }
        do {
            if files.fileExists(atPath: staged.path) { try files.removeItem(at: staged) }
        } catch {
            try? AccountVault.save(accounts)
            if files.fileExists(atPath: staged.path) { try? files.moveItem(at: staged, to: source) }
            try? files.createDirectory(at: source, withIntermediateDirectories: true)
            try? JSONEncoder().encode(profile).write(to: source.appendingPathComponent("profile.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
            throw error
        }
        UserDefaults.standard.removeObject(forKey: "activeProfile")
    }
    func show(_ title: String, _ message: String) { notice = Notice(title: title, message: message) }
    func toggleFollow(_ id: String) {
        guard id != me.id else { return }
        commit { value in
            guard !self.isPersonHidden(id) else { throw TutuFailure.message("Unblock this member before following.") }
            if value.following.contains(id) { value.following.remove(id); value.confirmedMutual.remove(id) } else { value.following.insert(id) }
        }
    }
    @discardableResult func submitReport(targetID: String, authorID: String, kind: String, reason: String, detail: String, context: String?) -> Bool {
        guard authorID != me.id else { return false }
        guard !reason.isEmpty else { show("Choose a reason", "Select a report type to continue."); return false }
        let report = ReportDraft(targetID: targetID, authorID: authorID, kind: kind, reason: reason,
                                 detail: String(detail.prefix(1000)), context: context, locallyHandled: true)
        guard commit({ value in
            value.reports.removeAll { $0.targetID == targetID && $0.kind == kind && $0.locallyHandled == true }
            value.reports.append(report)
            var hidden = value.hiddenContent ?? []
            hidden.insert(ModerationContent(kind: kind, id: targetID)); value.hiddenContent = hidden
        }) else { return false }
        finishModeration("Report saved", "Your report is saved on this device. This content is now hidden.")
        return true
    }
    @discardableResult func hideContent(targetID: String, authorID: String, kind: String) -> Bool {
        guard authorID != me.id else { return false }
        guard commit({ value in
            var hidden = value.hiddenContent ?? []
            hidden.insert(ModerationContent(kind: kind, id: targetID)); value.hiddenContent = hidden
        }) else { return false }
        finishModeration("Content blocked", "Your choice is saved. This content will no longer appear.")
        return true
    }
    @discardableResult func block(_ id: String) -> Bool {
        guard id != me.id else { return false }
        guard commit({ value in
            value.blocked.insert(id); value.following.remove(id); value.followers.remove(id)
            value.confirmedMutual.remove(id); value.drafts[id] = nil; value.mediaDrafts[id] = nil
        }) else { return false }
        finishModeration("Member blocked", "Their profile, rooms, posts and chats are now hidden. You can manage blocked members in Privacy.")
        return true
    }
    @discardableResult func unblock(_ id: String) -> Bool {
        guard commit({ $0.blocked.remove(id) }) else { return false }
        finishModeration("Member unblocked", "Your block list has been updated. Reported or blocked content stays hidden.")
        return true
    }
    private func finishModeration(_ title: String, _ message: String) {
        if let room = minimizedRoom, isRoomHidden(room) { minimizedRoom = nil }
        notice = Notice(title: title, message: message, success: true)
    }
    func canContact(_ id: String) -> Bool {
        guard let s = state, !isPersonHidden(id) else { show("Member blocked", "Unblock this member in Privacy settings to continue."); return false }
        guard s.following.contains(id), followerIDs.contains(id) else { show("A little connection first", "Follow each other before sending a message or starting a call. Your message will stay here."); return false }
        guard s.confirmedMutual.contains(id) else { show("Connection unavailable", "We couldn't verify this connection. Please try again later. Your message has been kept."); return false }
        return true
    }
    func checkIn() {
        commit { s in
            let calendar = Calendar.current; let today = calendar.startOfDay(for: Date())
            let key = Self.dayKey(today)
            guard !s.checkinDates.contains(key) else { throw TutuFailure.message("You have already checked in today.") }
            if let last = s.highestCheckinDate, today <= last { throw TutuFailure.message("Check your device date and try again tomorrow.") }
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let consecutive = s.highestCheckinDate.map { calendar.isDate($0, inSameDayAs: yesterday) } ?? false
            s.checkinStreak = consecutive ? s.checkinStreak % 7 + 1 : 1
            let reward = [10,20,10,20,10,20,100][s.checkinStreak-1]
            s.checkinDates.insert(key); s.highestCheckinDate = today; s.creditCoins(reward, title: "Daily check-in"); s.points += 10
        }
    }
    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    func saveMedia(_ data: Data, extension ext: String) throws -> String {
        guard let id = sessionID else { throw TutuFailure.message("Please sign in again.") }
        let dir = root.appendingPathComponent(id, isDirectory: true); try files.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = UUID().uuidString + "." + ext; try data.write(to: dir.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUnlessOpen])
        return "media/" + file
    }
    func mediaURL(_ ref: String) -> URL? {
        let ref = EditorialMedia.resolvedReference(ref)
        if let url = URL(string: ref), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return url }
        if ref.hasPrefix("bundle/"), !ref.contains("..") {
            let name = String(ref.dropFirst(7)) as NSString
            return Bundle.main.url(forResource: name.deletingPathExtension, withExtension: name.pathExtension)
        }
        guard ref.hasPrefix("media/"), let id = sessionID, !ref.contains("..") else { return nil }
        return root.appendingPathComponent(id).appendingPathComponent(String(ref.dropFirst(6)))
    }

    private func syncReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-checkin"])
        guard state?.preferences.notifications == true, let accountID = sessionID else { return }
        Task {
            let settings = await center.notificationSettings()
            guard sessionID == accountID, state?.preferences.notifications == true,
                  settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = appLanguage.text("A little reward awaits"); content.body = appLanguage.text("Visit Daily Check for today's coins and activity points."); content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: "daily-checkin", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 18), repeats: true)))
                if sessionID != accountID { center.removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]) }
            } catch { show("Reminder unavailable", "Your daily reminder couldn't be scheduled. Turn it on again in Settings to retry.") }
        }
    }
}
struct Notice: Identifiable { let id = UUID(); let title: String; let message: String; var success = false }

struct AccountExitProgress { let deleting: Bool; let succeeded: Bool }
