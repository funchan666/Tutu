import Foundation

struct Person: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var birthday: Date? = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))!
    var country = "United States"
    var city: String? = nil
    var language = "English"
    var gender = "Woman"
    var bio = "Small moments, interesting conversations. Come say hello and share your day."
    var interests = ["Style", "Music"]
    var avatar: String = "brand-mascot"
    var photos: [String] = ["wardrobe-placeholder"]
    var isOnline: Bool? = nil
    var catalog = true
    var location: String { [city ?? "", country].filter { !$0.isEmpty }.joined(separator: ", ") }
    var age: Int { birthday.flatMap { Calendar.current.dateComponents([.year], from: $0, to: Date()).year } ?? 0 }
}
struct Look: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var authorID: String
    var text: String
    var media: [String]
    var video: String? = nil
    var created = Date()
    var category = "Daily"
    var localOnly = true
}
struct LookComment: Codable, Identifiable {
    var id = UUID().uuidString
    var postID: String
    var authorID: String
    var text: String
    var created = Date()
}
enum RoomCategories {
    static var options: [String] { Catalog.snapshot?.settings.roomCategories ?? [] }
    static var filters: [String] { ["All"] + options }
    static func resolved(_ value: String) -> String { options.contains(value) ? value : "Daily" }
}
enum VoiceRoomTopics {
    static var options: [String] { Catalog.snapshot?.settings.voiceTopics ?? [] }
    static var filters: [String] { ["All"] + options }
    static func resolved(_ topic: String?) -> String {
        guard let topic, options.contains(topic) else { return "Style Talk" }
        return topic
    }
}
struct StyleRoom: Codable, Identifiable, Hashable {
    var id: String
    var hostID: String
    var title: String
    var category: String
    var voice: Bool
    var voiceTopic: String? = nil
    var isBroadcasting: Bool? = nil
    var video: String? = nil
    var viewerCount: Int? = nil
    var seats = 8
    var cover = "wardrobe-placeholder"
    var localOnly = true
    var styleCategory: String { RoomCategories.resolved(category) }
    var conversationTopic: String { VoiceRoomTopics.resolved(voiceTopic) }
}
struct RoomMessage: Codable, Identifiable {
    var id = UUID().uuidString
    let personID: String
    let text: String
    var giftID: String? = nil
}
struct ConversationMessage: Codable, Identifiable {
    var id = UUID().uuidString
    var text: String
    var outgoing: Bool
    var created = Date()
    var status: String = "Not sent"
    var replySource: String? = nil
}
struct Gift: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    var image: String { "gift-" + id }
    static var all: [Gift] { Catalog.snapshot?.settings.gifts ?? [] }
}
struct WalletEntry: Codable, Identifiable {
    enum Kind: String, Codable { case spending, credit, refund }
    var id = UUID().uuidString
    var title: String
    var amount: Int
    var date = Date()
    var kind: Kind? = nil
    var coinsSpent: Int {
        guard amount < 0, amount != Int.min else { return 0 }
        if let kind { return kind == .spending ? -amount : 0 }
        if title == "Runway Ribbon" { return -amount }
        for gift in Gift.all {
            let prefix = gift.name + " ×"
            if title.hasPrefix(prefix), let quantity = Int(title.dropFirst(prefix.count)), quantity > 0 { return -amount }
        }
        return 0
    }
}
struct ModerationContent: Codable, Hashable {
    let kind: String
    let id: String
}
struct ReportDraft: Codable, Identifiable {
    var id = UUID().uuidString
    var targetID: String
    var authorID: String
    var kind: String
    var reason: String
    var detail: String
    var context: String? = nil
    var locallyHandled: Bool? = nil
    var date = Date()
    var delivered = false
}
struct UserPreferences: Codable {
    var privateProfile = false
    var showActivity = true
    var allowInvites = true
    var notifications = false
    var language = "English"
}
struct ProfileState: Codable {
    var person: Person
    var social: [String: AtelierSocialState]? = nil
    var following = Set<String>()
    var followers = Set<String>()
    var confirmedMutual = Set<String>()
    var blocked = Set<String>()
    var likedLooks = Set<String>()
    var savedLooks = Set<String>()
    var looks: [Look] = []
    var comments: [LookComment] = []
    var rooms: [StyleRoom] = []
    var drafts: [String: String] = [:]
    var mediaDrafts: [String: String] = [:]
    var conversations: [String: [ConversationMessage]] = [:]
    var stylist: [ConversationMessage] = []
    var stylistFreeUsed: Int? = nil
    var stylistCompletedTurns: Set<String>? = nil
    var roomMessages: [String: [RoomMessage]]? = nil
    var hiddenContent: Set<ModerationContent>? = nil
    var welcomeEligible: Bool? = nil
    var welcomeGranted: Bool? = nil
    var welcomeSeen: Bool? = nil
    var ownedCosmetics: Set<String>? = nil
    var equippedFrame: String? = nil
    var featuredGift: String? = nil
    var walletInstance: UUID? = nil
    var transactionGrants: [String: Int]? = nil
    var refundDebt: Int? = nil
    var coins = 0
    var points = 0
    var inventory: [String: Int] = [:]
    var ledger: [WalletEntry] = []
    var creditedTransactions = Set<String>()
    var revokedTransactions = Set<String>()
    var checkinDates = Set<String>()
    var highestCheckinDate: Date? = nil
    var checkinStreak = 0
    var catalogArrivalIDs = Set<String>()
    var reports: [ReportDraft] = []
    var preferences = UserPreferences()
    var level: Int { 1 + points / 100 }
}
struct LocalAccount: Codable {
    var id: String
    var email: String
    var salt: Data
    var verifier: Data
    var appleUserID: String? = nil
}
enum TutuFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
enum LegalLinks {
    static let supportEmail = "pickardbonniejuled@yahoo.com"
    static let moderationEmail = "halan.peven01@hotmail.com"
    static let terms = URL(string: "https://sites.google.com/view/tutu-termsofservice/heavy")!
    static let privacy = URL(string: "https://sites.google.com/view/tutu-privacy-policy/heavy")!
}
struct EditorialProfile: Decodable {
    let birthday: String
    let gender: String
    let country: String
    let city: String
    let bio: String
    let interests: [String]
    var birthDate: Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: birthday)
    }
}
struct EditorialComment: Decodable {
    let id: String
    let authorID: String
    let text: String
    let createdAt: TimeInterval
}
struct EditorialItem: Decodable {
    let id: String
    let name: String
    let handle: String
    let image: String
    let video: String?
    let avatar: String?
    let photos: [String]?
    let profile: EditorialProfile?
    let style: String
    let caption: String?
    let likeCount: Int?
    let publishedAt: TimeInterval?
    let comments: [EditorialComment]?
    let reservedForProfile: Bool?
}
enum Catalog {
    static var snapshot: AtelierSnapshot?
    static var items: [EditorialItem] { snapshot?.editorial ?? [] }
    static var profileAvatar: String { items.first(where: { $0.reservedForProfile == true })?.image ?? "brand-mascot" }
    static var reservedProfileIDs: Set<String> { Set(items.filter { $0.reservedForProfile == true }.map(\.id)) }
    static var people: [Person] { items.filter { $0.reservedForProfile != true }.map { item in
        Person(id: item.id, name: item.name, handle: item.handle,
               birthday: item.profile?.birthDate, country: item.profile?.country ?? "", city: item.profile?.city,
               gender: item.profile?.gender ?? "", bio: item.profile?.bio ?? "A personal edit of everyday style.",
               interests: item.profile?.interests ?? [item.style], avatar: item.avatar ?? item.image, photos: item.photos ?? [item.image])
    }
    }
    static var rooms: [StyleRoom] { snapshot?.rooms ?? [] }
    static var looks: [Look] { items.filter { $0.reservedForProfile != true }.map { item in
        Look(id: "look-\(item.id)", authorID: item.id, text: item.caption ?? (item.style + " inspiration. Find the details that feel like you."), media: [item.image], video: item.video,
             created: Date(timeIntervalSince1970: item.publishedAt ?? 1791792000), category: item.style)
    }
    }
    static var discoverIDs: [String] { snapshot?.settings.discoverIDs ?? [] }
    static var comments: [LookComment] { items.flatMap { item in
        (item.comments ?? []).map {
            LookComment(id: $0.id, postID: "look-\(item.id)", authorID: $0.authorID, text: $0.text,
                        created: Date(timeIntervalSince1970: $0.createdAt))
        }
    }
    }
}
