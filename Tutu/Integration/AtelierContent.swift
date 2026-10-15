import Foundation
import UIKit

struct AtelierSettings: Decodable {
    struct Ranking: Decodable { let id: String; let daily: Int; let weekly: Int; let total: Int }
    struct Counter: Decodable { let followers: Int; let following: Int }
    let gifts: [Gift]
    let packs: [CoinPack]
    let styles: [StyleDirection]
    let topics: [StylistGuides.Topic]
    let formulas: [String: String]
    let finishes: [String]
    let roomCaptions: [String]
    let rankings: [Ranking]
    let roomCategories: [String]
    let voiceTopics: [String]
    let reportReasons: [String]
    let discoverIDs: [String]
    let counters: [String: Counter]
}
struct AtelierSnapshot {
    let editorial: [EditorialItem]
    let rooms: [StyleRoom]
    let settings: AtelierSettings
    func validate() throws {
        let ids = Set(editorial.map(\.id))
        guard !editorial.isEmpty, ids.count == editorial.count, Set(rooms.map(\.id)).count == rooms.count,
              settings.gifts.count >= 2, settings.styles.count > 0,
              !settings.packs.isEmpty, !settings.roomCategories.isEmpty, !settings.voiceTopics.isEmpty,
              !settings.finishes.isEmpty, !settings.roomCaptions.isEmpty,
              settings.topics.allSatisfy({ !$0.keys.isEmpty && !$0.answers.isEmpty }),
              settings.formulas["Minimalist"] != nil,
              Set(settings.styles.map(\.name)).count == settings.styles.count,
              Set(settings.gifts.map(\.id)).count == settings.gifts.count,
              Set(settings.packs.map(\.id)).count == settings.packs.count,
              settings.gifts.allSatisfy({ $0.price > 0 }), settings.packs.allSatisfy({ $0.coins > 0 && Decimal(string: $0.referenceUSD) != nil }),
              rooms.allSatisfy({ ids.contains($0.hostID) && (1...8).contains($0.seats) && ($0.viewerCount.map { $0 >= 0 } ?? true) }),
              settings.rankings.allSatisfy({ ids.contains($0.id) }),
              settings.counters.keys.allSatisfy({ ids.contains($0) }),
              settings.discoverIDs.allSatisfy({ id in editorial.contains { "look-" + $0.id == id && $0.video != nil } }) else {
            throw TutuFailure.message("The style collection could not be loaded. Please try again.")
        }
        var commentIDs = Set<String>()
        for item in editorial {
            guard !item.id.isEmpty, !item.name.isEmpty else { throw AtelierHTTP.Failure.invalidResponse }
            for comment in item.comments ?? [] {
                guard ids.contains(comment.authorID), commentIDs.insert(comment.id).inserted else { throw AtelierHTTP.Failure.invalidResponse }
            }
            for ref in [item.image, item.avatar, item.video].compactMap({ $0 }) + (item.photos ?? []) { try Self.validateMedia(ref) }
        }
        for room in rooms { try Self.validateMedia(room.cover); if let video = room.video { try Self.validateMedia(video) } }
        for style in settings.styles { try Self.validateMedia(style.image) }
        for gift in settings.gifts { try Self.validateMedia(gift.image) }
    }
    static func validateMedia(_ ref: String) throws {
        let ref = EditorialMedia.resolvedReference(ref)
        guard !ref.contains("#{") else { throw AtelierHTTP.Failure.invalidResponse }
        if let url = URL(string: ref), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return }
        if ref.hasPrefix("bundle/"), !ref.contains("..") {
            let path = String(ref.dropFirst(7)) as NSString
            if Bundle.main.url(forResource: path.deletingPathExtension, withExtension: path.pathExtension) != nil { return }
        } else if !ref.contains("/"), !ref.isEmpty, UIImage(named: ref) != nil { return }
        throw AtelierHTTP.Failure.invalidResponse
    }
}
