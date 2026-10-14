import SwiftUI
import UserNotifications

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var state: ProfileState?
    @Published var notice: Notice?
    @Published var tab = 0
    @Published var returnToLogin = false
    @Published var minimizedRoom: StyleRoom?
    private var arrivals: Task<Void, Never>?
    private let files = FileManager.default
    let root: URL
    var sessionID: String? { state?.person.id }
    var me: Person { state?.person ?? Person(id: "", name: "Your name", handle: "you", photos: [], catalog: false) }
    var people: [Person] { Catalog.people.filter { !(state?.blocked.contains($0.id) ?? false) } }
    var looks: [Look] { ((state?.looks ?? []) + Catalog.looks).filter { !(state?.blocked.contains($0.authorID) ?? false) } }
    var rooms: [StyleRoom] { ((state?.rooms ?? []) + Catalog.rooms).filter { !(state?.blocked.contains($0.hostID) ?? false) } }
    init() {
        root = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tutu", isDirectory: true)
        do { try files.createDirectory(at: root, withIntermediateDirectories: true); try recoverDeletionJournal() }
        catch { notice = Notice(title: "Storage unavailable", message: "Changes cannot be saved on this device right now.") }
        if let id = UserDefaults.standard.string(forKey: "activeProfile") {
            do {
                let accounts = try AccountVault.load()
                if accounts.contains(where: { $0.id == id }) { state = try read(id); scheduleArrivals() }
            } catch { notice = Notice(title: "Could not open your profile", message: "Your saved data was left unchanged. Please sign in again.") }
        }
    }
    func person(_ id: String) -> Person { id == me.id ? me : Catalog.people.first(where: { $0.id == id }) ?? Person(id: id, name: "Member", handle: "member") }
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
        guard email.contains("@"), email.split(separator: "@").count == 2, email.split(separator: "@").last?.contains(".") == true else { throw TutuFailure.message("Enter a valid email address.") }
        guard password.count >= 8 else { throw TutuFailure.message("Use a password with at least 8 characters.") }
        var accounts = try AccountVault.load()
        if creating {
            guard !accounts.contains(where: { $0.email == email }) else { throw TutuFailure.message("An account with this email already exists on this device. Please log in.") }
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TutuFailure.message("Add your name.") }
            let salt = try AccountVault.salt()
            let verifier = try await Task.detached(priority: .userInitiated) { try AccountVault.hash(password, salt: salt) }.value
            let id = UUID().uuidString
            let account = LocalAccount(id: id, email: email, salt: salt, verifier: verifier)
            let profile = ProfileState(person: Person(id: id, name: String(name.prefix(40)), handle: "style" + id.prefix(6).lowercased(), birthday: nil, photos: [], catalog: false))
            try write(profile)
            accounts.append(account)
            do { try AccountVault.save(accounts) } catch { try? files.removeItem(at: location(id)); throw error }
            state = profile
        } else {
            guard let account = accounts.first(where: { $0.email == email && $0.appleUserID == nil }) else { throw TutuFailure.message("No matching account was found on this device.") }
            let hash = try await Task.detached(priority: .userInitiated) { try AccountVault.hash(password, salt: account.salt) }.value
            guard AccountVault.matches(hash, account.verifier) else { throw TutuFailure.message("The email or password is incorrect.") }
            state = try read(account.id)
        }
        UserDefaults.standard.set(sessionID, forKey: "activeProfile"); returnToLogin = false; tab = 0; scheduleArrivals()
    }
    func acceptAppleIdentity(userID: String, name: String?, email: String?) throws {
        var accounts = try AccountVault.load()
        if let account = accounts.first(where: { $0.appleUserID == userID }) { state = try read(account.id) }
        else {
            let id = UUID().uuidString
            let profile = ProfileState(person: Person(id: id, name: name?.isEmpty == false ? name! : "Style Friend", handle: "style" + id.prefix(6).lowercased(), birthday: nil, photos: [], catalog: false))
            try write(profile)
            accounts.append(LocalAccount(id: id, email: email ?? "", salt: Data(), verifier: Data(), appleUserID: userID))
            do { try AccountVault.save(accounts) } catch { try? files.removeItem(at: location(id)); throw error }
            state = profile
        }
        UserDefaults.standard.set(sessionID, forKey: "activeProfile"); tab = 0; scheduleArrivals()
    }
    func signOut() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-checkin"]); arrivals?.cancel(); state = nil; minimizedRoom = nil; tab = 0; returnToLogin = true; UserDefaults.standard.removeObject(forKey: "activeProfile") }
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
            guard !value.blocked.contains(id) else { throw TutuFailure.message("Unblock this member before following.") }
            if value.following.contains(id) { value.following.remove(id); value.confirmedMutual.remove(id) } else { value.following.insert(id) }
        }
    }
    func block(_ id: String) {
        guard id != me.id else { return }
        commit { $0.blocked.insert(id); $0.following.remove(id); $0.followers.remove(id); $0.confirmedMutual.remove(id); $0.drafts[id] = nil }
    }
    func canContact(_ id: String) -> Bool {
        guard let s = state, !s.blocked.contains(id) else { show("Member blocked", "Unblock this member in Privacy settings to continue."); return false }
        guard s.following.contains(id), s.followers.contains(id) else { show("A little connection first", "Follow each other before sending a message or starting a call. Your message will stay here."); return false }
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
            s.checkinDates.insert(key); s.highestCheckinDate = today; s.coins += reward; s.points += 10
            s.ledger.insert(WalletEntry(title: "Daily check-in", amount: reward), at: 0)
        }
    }
    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    func buy(_ gift: Gift, quantity: Int) -> Bool {
        commit { s in
            guard (1...99).contains(quantity) else { throw TutuFailure.message("Choose a quantity from 1 to 99.") }
            let total = gift.price * quantity
            guard s.coins >= total else { throw TutuFailure.message("You need \(total - s.coins) more coins. Visit Get Coins or Daily Check.") }
            s.coins -= total; s.inventory[gift.id, default: 0] += quantity
            s.ledger.insert(WalletEntry(title: "\(gift.name) × \(quantity)", amount: -total), at: 0)
        }
    }
    func saveMedia(_ data: Data, extension ext: String) throws -> String {
        guard let id = sessionID else { throw TutuFailure.message("Please sign in again.") }
        let dir = root.appendingPathComponent(id, isDirectory: true); try files.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = UUID().uuidString + "." + ext; try data.write(to: dir.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUnlessOpen])
        return "media/" + file
    }
    func mediaURL(_ ref: String) -> URL? {
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
    private func scheduleArrivals() {
        syncReminder()
        arrivals?.cancel()
        guard let accountID = sessionID else { return }
        arrivals = Task { [weak self] in
            for (index, id) in ["mia", "lily"].enumerated() {
                try? await Task.sleep(for: .seconds(index == 0 ? 25 : 50))
                guard !Task.isCancelled, let self, self.sessionID == accountID else { return }
                if self.state?.catalogArrivalIDs.contains(id) == false {
                    self.commit { s in
                        s.catalogArrivalIDs.insert(id)
                        if !s.blocked.contains(id) { s.followers.insert(id) }
                        // Intentionally never adds to following or confirmedMutual.
                    }
                }
            }
        }
    }
}
struct Notice: Identifiable { let id = UUID(); let title: String; let message: String }
