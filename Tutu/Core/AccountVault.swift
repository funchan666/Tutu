import Foundation
import Security
import CommonCrypto

struct AccountVault {
    private static let service = "com.tutu.style.accounts"
    static func load() throws -> [LocalAccount] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "accounts", kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else { throw TutuFailure.message("Your saved account is unavailable. Please try again.") }
        return try JSONDecoder().decode([LocalAccount].self, from: data)
    }
    static func save(_ accounts: [LocalAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "accounts"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw TutuFailure.message("Your account could not be saved securely.") }
        } else if status != errSecSuccess { throw TutuFailure.message("Your account could not be saved securely.") }
    }
    static func salt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &bytes) == errSecSuccess else { throw TutuFailure.message("Please try again.") }
        return Data(bytes)
    }
    static func hash(_ password: String, salt: Data) throws -> Data {
        let pass = Array(password.utf8); let saltBytes = Array(salt)
        var result = [UInt8](repeating: 0, count: 32)
        let status = pass.withUnsafeBytes { p in
            saltBytes.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.bindMemory(to: Int8.self).baseAddress, pass.count,
                                    s.bindMemory(to: UInt8.self).baseAddress, saltBytes.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 210_000, &result, 32)
            }
        }
        guard status == kCCSuccess else { throw TutuFailure.message("Your password could not be secured.") }
        return Data(result)
    }
    static func matches(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
