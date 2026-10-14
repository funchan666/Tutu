import Foundation

struct Person: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var birthday: Date? = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))!
    var country = "United States"
    var language = "English"
    var gender = "Woman"
    var bio = "Small moments, interesting conversations. Come say hello and share your day."
    var interests = ["Style", "Music"]
    var avatar: String = "brand-mascot"
    var photos: [String] = ["wardrobe-placeholder"]
    var isOnline: Bool? = nil
    var catalog = true
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
struct StyleRoom: Codable, Identifiable, Hashable {
    var id: String
    var hostID: String
    var title: String
    var category: String
    var voice: Bool
    var isBroadcasting: Bool? = nil
    var seats = 8
    var cover = "wardrobe-placeholder"
    var localOnly = true
}
struct ConversationMessage: Codable, Identifiable {
    var id = UUID().uuidString
    var text: String
    var outgoing: Bool
    var created = Date()
    var status: String = "Not sent"
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
    var id = UUID().uuidString
    var title: String
    var amount: Int
    var date = Date()
}
struct ReportDraft: Codable, Identifiable {
    var id = UUID().uuidString
    var targetID: String
    var authorID: String
    var kind: String
    var reason: String
    var detail: String
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
    // Optional additions keep existing profiles decodable.
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
struct EditorialItem: Decodable {
    let id: String
    let name: String
    let handle: String
    let image: String
    let video: String?
    let style: String
}
enum Catalog {
    static let items: [EditorialItem] = {
        guard let url = Bundle.main.url(forResource: "EditorialCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([EditorialItem].self, from: data) else { return [] }
        return items
    }()
    static let people: [Person] = items.map { item in
        Person(id: item.id, name: item.name, handle: item.handle, birthday: nil, country: "", gender: "",
               bio: "A personal edit of everyday style.", interests: [item.style], avatar: item.image, photos: [item.image])
    }
    static let rooms: [StyleRoom] = people.prefix(18).enumerated().map { index, p in
        StyleRoom(id: "room-\(p.id)", hostID: p.id, title: p.interests[0] + " style edit", category: ["Pop", "Acoustic", "Singing", "K-Pop"][index % 4], voice: index % 2 != 0, cover: p.photos[0])
    }
    static let looks: [Look] = items.map { item in
        Look(id: "look-\(item.id)", authorID: item.id, text: item.style + " inspiration. Find the details that feel like you.", media: [item.image], video: item.video, category: item.style)
    }
}
