import SwiftUI
import UserNotifications

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var state: ProfileState?
    @Published var notice: Notice?
    @Published var tab = 0
    @Published var returnToLogin = false
    @Published var minimizedRoom: StyleRoom?
    @Published var welcomeVisible = false
    @Published var coinPrompt: CoinSpend?
    @Published var walletRequest = 0
    private let files = FileManager.default
    let root: URL
    var sessionID: String? { state?.person.id }
    var me: Person { state?.person ?? Person(id: "", name: "Your name", handle: "you", photos: [], catalog: false) }
    /// Legacy scripted arrivals are not actual follower relationships.
    var followerIDs: Set<String> {
        guard let state else { return [] }
        return Set(state.followers.subtracting(state.catalogArrivalIDs).filter { !isPersonHidden($0) })
    }
    func isContentHidden(_ kind: String, _ id: String) -> Bool {
        state?.hiddenContent?.contains(ModerationContent(kind: kind, id: id)) == true
    }
    func isPersonHidden(_ id: String) -> Bool {
        state?.blocked.contains(id) == true || isContentHidden("member", id)
    }
    func isRoomHidden(_ room: StyleRoom) -> Bool {
        isPersonHidden(room.hostID) || isContentHidden("room", room.id) || isContentHidden("photo", room.cover)
    }
    func isMessageHidden(_ item: RoomMessage) -> Bool {
        isPersonHidden(item.personID) || isContentHidden("message", item.id)
    }
    var people: [Person] { Catalog.people.filter { !isPersonHidden($0.id) }.map { person($0.id) } }
    var looks: [Look] {
        ((state?.looks ?? []) + Catalog.looks).filter {
            !isPersonHidden($0.authorID) && !isContentHidden("post", $0.id)
                && !$0.media.contains(where: { isContentHidden("photo", $0) })
        }
    }
    var rooms: [StyleRoom] { ((state?.rooms ?? []) + Catalog.rooms).filter { !isRoomHidden($0) } }
    var comments: [LookComment] {
        (state?.comments ?? []).filter { !isPersonHidden($0.authorID) && !isContentHidden("comment", $0.id) }
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
    /// Restore off the main actor so the in-app launch artwork can remain responsive.
    func restoreSession() async {
        guard state == nil, let id = UserDefaults.standard.string(forKey: "activeProfile"), UUID(uuidString: id) != nil else { return }
        let profileURL = location(id)
        do {
            let restored = try await Task.detached(priority: .userInitiated) { () throws -> ProfileState? in
                let accounts = try AccountVault.load()
                guard accounts.contains(where: { $0.id == id }) else { return nil }
                return try JSONDecoder().decode(ProfileState.self, from: Data(contentsOf: profileURL))
            }.value
            guard !Task.isCancelled else { return }
            state = restored
            if restored != nil { syncReminder() }
        } catch {
            notice = Notice(title: "Could not open your profile", message: "Your saved data was left unchanged. Please sign in again.")
        }
    }
    func person(_ id: String) -> Person {
        var value = id == me.id ? me : Catalog.people.first(where: { $0.id == id }) ?? Person(id: id, name: "Member", handle: "member")
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
    private func read(_ id: String) throws -> ProfileState { try JSONDecoder().decode(ProfileState.self, from: Data(contentsOf: location(id))) }
    private func write(_ value: ProfileState) throws {
        try files.createDirectory(at: location(value.person.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: location(value.person.id), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    @discardableResult func commit(_ operation: (inout ProfileState) throws -> Void) -> Bool {
        guard var next = state else { show("Sign in required", "Sign in to keep your changes."); return false }
        do { try operation(&next); try write(next); state = next; return true }
        catch { show("Could not save", error.localizedDescription); return false }
    }
    func authenticate(email: String, password: String, creating: Bool, name: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let emailPattern = #"^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#
        guard email.utf8.count <= 254,
              (email.split(separator: "@").first?.utf8.count ?? 0) <= 64,
              email.range(of: emailPattern, options: .regularExpression) != nil else {
            throw TutuFailure.message("Enter a valid email address.")
        }
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TutuFailure.message("Enter your password to continue.")
        }
        var accounts = try AccountVault.load()
        if !creating, let account = accounts.first(where: { $0.email == email && $0.appleUserID == nil }) {
            // Email entry selects a local profile; it does not verify ownership or a password.
            // Keep existing profile IDs, wallet balances and credentials unchanged.
            state = try read(account.id)
        } else {
            if creating {
                guard password.count >= 8 else { throw TutuFailure.message("Use a password with at least 8 characters.") }
                guard !accounts.contains(where: { $0.email == email }) else { throw TutuFailure.message("An account with this email already exists on this device. Please log in.") }
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TutuFailure.message("Add your name.") }
            }
            let salt: Data
            let verifier: Data
            if creating {
                salt = try AccountVault.salt()
                verifier = try await Task.detached(priority: .userInitiated) { try AccountVault.hash(password, salt: salt) }.value
            } else {
                // Format-only entry never stores the supplied password.
                salt = Data()
                verifier = Data()
            }
            let id = UUID().uuidString
            let account = LocalAccount(id: id, email: email, salt: salt, verifier: verifier)
            let displayName = creating ? String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) : "Style Friend"
            var profile = ProfileState(person: Person(id: id, name: displayName, handle: "style" + id.prefix(6).lowercased(), birthday: nil, photos: [], catalog: false))
            profile.welcomeEligible = true
            try write(profile)
            accounts.append(account)
            do { try AccountVault.save(accounts) } catch { try? files.removeItem(at: location(id)); throw error }
            state = profile
        }
        UserDefaults.standard.set(sessionID, forKey: "activeProfile"); returnToLogin = false; tab = 0; syncReminder()
    }
    func acceptAppleIdentity(userID: String, name: String?, email: String?) throws {
        var accounts = try AccountVault.load()
        if let account = accounts.first(where: { $0.appleUserID == userID }) { state = try read(account.id) }
        else {
            let id = UUID().uuidString
            var profile = ProfileState(person: Person(id: id, name: name?.isEmpty == false ? name! : "Style Friend", handle: "style" + id.prefix(6).lowercased(), birthday: nil, photos: [], catalog: false))
            profile.welcomeEligible = true
            try write(profile)
            accounts.append(LocalAccount(id: id, email: email ?? "", salt: Data(), verifier: Data(), appleUserID: userID))
            do { try AccountVault.save(accounts) } catch { try? files.removeItem(at: location(id)); throw error }
            state = profile
        }
        UserDefaults.standard.set(sessionID, forKey: "activeProfile"); tab = 0; syncReminder()
    }
    func signOut() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]); welcomeVisible = false; coinPrompt = nil; notice = nil; state = nil; minimizedRoom = nil; tab = 0; returnToLogin = true; UserDefaults.standard.removeObject(forKey: "activeProfile") }
    func deleteAccount() throws {
        guard let id = sessionID else { return }
        let accounts = try AccountVault.load()
        // Stage files for rollback; never claim deletion while Keychain data remains.
        let source = root.appendingPathComponent(id, isDirectory: true)
        let staged = root.appendingPathComponent(id + ".deleting", isDirectory: true)
        if files.fileExists(atPath: staged.path), !files.fileExists(atPath: source.path) { try files.moveItem(at: staged, to: source) }
        if files.fileExists(atPath: source.path) { try files.moveItem(at: source, to: staged) }
        do { try AccountVault.save(accounts.filter { $0.id != id }) }
        catch { if files.fileExists(atPath: staged.path) { try? files.moveItem(at: staged, to: source) }; throw error }
        do {
            if files.fileExists(atPath: staged.path) { try files.removeItem(at: staged) }
        } catch {
            try? AccountVault.save(accounts)
            if files.fileExists(atPath: staged.path) { try? files.moveItem(at: staged, to: source) }
            if let state { try? write(state) }
            throw error
        }
        signOut(); returnToLogin = false
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
            content.title = "A little reward awaits"; content.body = "Visit Daily Check for today's coins and activity points."; content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: "daily-checkin", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 18), repeats: true)))
                if sessionID != accountID { center.removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]) }
            } catch { show("Reminder unavailable", "Your daily reminder couldn't be scheduled. Turn it on again in Settings to retry.") }
        }
    }
}
struct Notice: Identifiable { let id = UUID(); let title: String; let message: String; var success = false }
