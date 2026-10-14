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
        .init(id: "microphone", name: "Pop Star", price: 10), .init(id: "heart", name: "Heart Beat", price: 20),
        .init(id: "bear", name: "Sweet Bear", price: 30), .init(id: "castle", name: "Dream Castle", price: 100),
        .init(id: "car", name: "Night Ride", price: 150), .init(id: "flowers", name: "Pink Blooms", price: 40),
        .init(id: "star", name: "Lucky Star", price: 50), .init(id: "music", name: "Mix Tape", price: 60)
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
enum Catalog {
    static let people: [Person] = [
        .init(id: "mia", name: "Mia", handle: "miastyle", country: "United States", interests: ["Streetwear", "Pop"]),
        .init(id: "lily", name: "Lily", handle: "lilylooks", country: "United Kingdom", interests: ["Vintage", "Acoustic"]),
        .init(id: "ella", name: "Ella", handle: "ellaeveryday", country: "Canada", interests: ["Minimalist", "Singing"]),
        .init(id: "noah", name: "Noah", handle: "noahnotes", country: "Australia", gender: "Man", interests: ["Streetwear", "K-Pop"]),
        .init(id: "ava", name: "Ava", handle: "avacloset", country: "France", language: "French", interests: ["Vintage", "Pop"]),
        .init(id: "leo", name: "Leo", handle: "leodaily", country: "Germany", language: "German", gender: "Man", interests: ["Minimalist", "Acoustic"])
    ]
    static let rooms: [StyleRoom] = people.enumerated().map { index, p in
        StyleRoom(id: "room-\(p.id)", hostID: p.id, title: ["NYC Street Look", "Vintage afternoons", "The everyday edit", "Tonight's playlist", "A little pink", "Less is more"][index], category: ["Pop", "Acoustic", "Singing", "K-Pop", "Pop", "Acoustic"][index], voice: index % 2 != 0)
    }
    static let looks: [Look] = people.enumerated().map { i, p in
        Look(id: "look-\(p.id)", authorID: p.id, text: ["A new way to wear your everyday favourites.", "Soft layers, a little colour, and room to be yourself.", "Small moments, interesting conversations.", "Finding a rhythm for the week.", "One favourite piece. Three new possibilities.", "A calmer kind of daily style."][i], media: ["wardrobe-placeholder"], category: ["Daily", "Vintage", "Minimalist", "Streetwear", "Daily", "Minimalist"][i])
    }
}
