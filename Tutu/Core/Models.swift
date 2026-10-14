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
    static let options = ["Daily", "Streetwear", "Minimalist", "Chic"]
    static let filters = ["All"] + options
    // Older locally saved rooms did not have a fashion category. Keep them discoverable.
    static func resolved(_ value: String) -> String { options.contains(value) ? value : "Daily" }
}
enum VoiceRoomTopics {
    static let options = ["Outfit Tips", "Style Talk", "Vintage Finds"]
    static let filters = ["All"] + options
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
struct Gift: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    var image: String { "gift-" + id }
    static let all: [Gift] = [
        .init(id: "microphone", name: "Pop Star", price: 40), .init(id: "heart", name: "Heart Beat", price: 60),
        .init(id: "bear", name: "Sweet Bear", price: 100), .init(id: "castle", name: "Dream Castle", price: 1200),
        .init(id: "car", name: "Night Ride", price: 1800), .init(id: "flowers", name: "Pink Blooms", price: 160),
        .init(id: "star", name: "Lucky Star", price: 240), .init(id: "music", name: "Mix Tape", price: 320)
    ]
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
        // Old records have no kind. Recognize only the existing purchase titles.
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
    var following = Set<String>()
    var followers = Set<String>()
    // Catalog relationships never authorize real communications.
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
    // Optional additions keep existing profiles decodable.
    var roomMessages: [String: [RoomMessage]]? = nil
    var hiddenContent: Set<ModerationContent>? = nil
    var welcomeEligible: Bool? = nil
    var welcomeGranted: Bool? = nil
    var welcomeSeen: Bool? = nil
    var ownedCosmetics: Set<String>? = nil
    var equippedFrame: String? = nil
    var featuredGift: String? = nil
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
}
enum Catalog {
    static let items: [EditorialItem] = {
        guard let url = Bundle.main.url(forResource: "EditorialCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([EditorialItem].self, from: data) else { return [] }
        return items
    }()
    static let people: [Person] = items.map { item in
        Person(id: item.id, name: item.name, handle: item.handle,
               birthday: item.profile?.birthDate, country: item.profile?.country ?? "", city: item.profile?.city,
               gender: item.profile?.gender ?? "", bio: item.profile?.bio ?? "A personal edit of everyday style.",
               interests: item.profile?.interests ?? [item.style], avatar: item.avatar ?? item.image, photos: item.photos ?? [item.image])
    }
    static let rooms: [StyleRoom] = {
        // Six supplied videos, selected for readable first-frame covers.
        // Viewer counts are fixed local presentation values, not live presence statistics.
        let selections = [
            ("film-01", "Soft Tailoring", "Chic", 48),
            ("film-02", "Street Style Crew", "Streetwear", 56),
            ("film-04", "After Dark Layers", "Streetwear", 45),
            ("film-07", "A Walk in Style", "Daily", 52),
            ("film-09", "Everyday Pairings", "Minimalist", 47),
            ("film-11", "City Light Look", "Daily", 54)
        ]
        let liveRooms: [StyleRoom] = selections.compactMap { id, title, category, viewerCount in
            guard let item = items.first(where: { $0.id == id }), let video = item.video else { return nil }
            return StyleRoom(id: "room-\(id)", hostID: id, title: title, category: category,
                             voice: false, video: video, viewerCount: viewerCount, cover: item.image)
        }
        // Voice-room covers use supplied host portraits; counts are local presentation data.
        let voiceSelections: [(hostID: String, title: String, topic: String, count: Int)] = [
            ("lily", "Vintage finds & coffee", "Vintage Finds", 48),
            ("ava", "Everyday outfit chat", "Outfit Tips", 52),
            ("editorial-001", "Color stories", "Outfit Tips", 46),
            ("editorial-005", "The layering lounge", "Outfit Tips", 55),
            ("editorial-008", "Weekend wardrobe", "Style Talk", 49),
            ("noah", "City style conversations", "Style Talk", 51),
            ("editorial-011", "Vintage closet favorites", "Vintage Finds", 47),
            ("editorial-013", "Minimal mood", "Style Talk", 54),
            ("mia", "Streetwear styling session", "Outfit Tips", 53),
            ("ella", "Your capsule wardrobe", "Outfit Tips", 49),
            ("editorial-007", "Sneakers meet tailoring", "Outfit Tips", 51),
            ("editorial-009", "What are you wearing today?", "Style Talk", 48),
            ("editorial-010", "Coffee break style chat", "Style Talk", 54),
            ("editorial-024", "After-hours outfit club", "Style Talk", 50),
            ("leo", "Denim through the decades", "Vintage Finds", 52),
            ("editorial-012", "Thrift finds worth keeping", "Vintage Finds", 46),
            ("editorial-014", "Retro accessories club", "Vintage Finds", 53),
            ("editorial-025", "The secondhand style edit", "Vintage Finds", 50)
        ]
        let voiceRooms: [StyleRoom] = voiceSelections.compactMap { selection in
            guard let person = people.first(where: { $0.id == selection.hostID }) else { return nil }
            return StyleRoom(id: "room-\(selection.hostID)", hostID: selection.hostID, title: selection.title,
                             category: RoomCategories.resolved(person.interests.first ?? "Daily"),
                             voice: true, voiceTopic: selection.topic, viewerCount: selection.count, cover: person.avatar)
        }
        return liveRooms + voiceRooms
    }()
    static let looks: [Look] = items.map { item in
        Look(id: "look-\(item.id)", authorID: item.id, text: item.style + " inspiration. Find the details that feel like you.", media: [item.image], video: item.video, category: item.style)
    }
}
