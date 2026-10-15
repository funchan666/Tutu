import Foundation

enum EditorialMedia {
    private static let aliases: [String: String] = {
        guard let url = Bundle.main.url(forResource: "EditorialMediaAliases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()

    static func resolvedReference(_ reference: String) -> String {
        aliases[reference] ?? reference
    }
}
