import SwiftUI

/// UI language is device-wide so it also applies to the welcome screen after logout.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", simplifiedChinese = "zh-Hans", spanish = "es", french = "fr", japanese = "ja"
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .spanish: return "Español"
        case .french: return "Français"
        case .japanese: return "日本語"
        }
    }
    static let preferenceKey = "tutu.interfaceLanguage"
    static var saved: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "en") ?? .english
    }
    var locale: Locale { Locale(identifier: rawValue) }
    // For notifications and attributed strings outside SwiftUI's localized Text rendering.
    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}
