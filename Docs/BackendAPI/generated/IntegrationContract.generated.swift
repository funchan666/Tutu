// Generated runtime v2; use the paired ConfiguredEventDecoder template.
// Deployment mappings belong in Docs, never in App resources.
import Foundation

enum IntegrationContract {
    static let realtimeTransport: String = "rtLink"
    static let namespace: String = "tutu"
    static let baseURLString: String? = "https://fjnvs.fdhewhf.top"
    static let ablyClientID: String = "app"
    static let serverClientIDs: [String] = ["serve"]
    static let allowsMissingSender: Bool = true
    static let acceptsSerializedExpiry: Bool = true
    static let continuationMode: Int = 2
    static let apiMethod: String = "POST"
    static let optionsPath: String = "/tutu/arrival/entry"
    static let entryPath: String = "/tutu/passport/fitting-pass"
    static let settlementPath: String = "/tutu/wallet/settlement"
    static let pageSignal: String = "RunwayDoorReady"
    static let pageDiscriminator: [String] = ["stitch"]
    static let purchaseSignal: String = "WardrobeCheckout"
    static let purchaseDiscriminator: [String] = ["stitch"]
    static let expirySignal: String = "AtelierSessionEnded"
    static let expiryDiscriminator: [String] = ["stitch"]
    static let externalSignal: String = "OpenStyleDestination"
    static let externalDiscriminator: [String] = ["stitch"]
    static let pageAddressPath: [String] = ["runway", "destination"]
    static let purchaseItemPath: [String] = ["checkout", "product"]
    static let purchaseReferencePath: [String] = ["checkout", "thread"]
    static let externalAddressPath: [String] = ["destination", "address"]
}

enum ConfiguredContentPaths {
    static let `editorial`: String = "/tutu/catalog/editorial"
    static let `rooms`: String = "/tutu/catalog/rooms"
    static let `atelier`: String = "/tutu/catalog/atelier"
}

enum ConfiguredWireFields {
    static let `apple_exchange`: String = "apple_exchange"
    static let `apple_identity`: String = "apple_identity"
    static let `apple_member`: String = "apple_member"
    static let `apple_stitch`: String = "apple_stitch"
    static let `arrival_kind`: String = "arrival_kind"
    static let `arrival_scene`: String = "arrival_scene"
    static let `atelier_passage`: String = "atelier_passage"
    static let `atelier_stamp`: String = "atelier_stamp"
    static let `checkout_thread`: String = "checkout_thread"
    static let `code`: String = "code"
    static let `data`: String = "data"
    static let `look_edition`: String = "look_edition"
    static let `message`: String = "message"
    static let `receipt_fabric`: String = "receipt_fabric"
    static let `ribbon_signal`: String = "ribbon_signal"
    static let `runway_delivery`: String = "runway_delivery"
    static let `style_mailbox`: String = "style_mailbox"
    static let `style_secret`: String = "style_secret"
    static let `token`: String = "token"
}

enum ConfiguredLoginEntryMode: Equatable {
    case standard, guestOnly

    // Call only for a successful login-methods response, never authentication data.
    // nil means invalid configuration; UI falls back to standard and logs the failure.
    static func parse(data: Any?) -> Self? {
        guard let fields = data as? [String: Any],
              let raw = fields[ConfiguredWireFields.`atelier_passage`] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains("#{") else { return nil }
        return value.isEmpty ? .standard : .guestOnly
    }
}
