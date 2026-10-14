import SwiftUI

extension Font {
    static func outfit(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo style: Font.TextStyle = .body) -> Font {
        let face: String
        switch weight {
        case .bold, .heavy, .black: face = "Bold"
        case .semibold: face = "SemiBold"
        case .medium: face = "Medium"
        default: face = "Regular"
        }
        return .custom("TutuOutfit-" + face, size: size, relativeTo: style)
    }
    static var tutuBody: Font { .outfit(size: 16, relativeTo: .body) }
    static var tutuHeadline: Font { .outfit(size: 16, weight: .semibold, relativeTo: .headline) }
    static var tutuSubheadline: Font { .outfit(size: 14, relativeTo: .subheadline) }
    static var tutuCaption: Font { .outfit(size: 12, relativeTo: .caption) }
    static var tutuCaption2: Font { .outfit(size: 10, relativeTo: .caption2) }
    static var tutuTitle: Font { .outfit(size: 28, weight: .bold, relativeTo: .title) }
    static var tutuTitle2: Font { .outfit(size: 23, weight: .bold, relativeTo: .title2) }
    static var tutuTitle3: Font { .outfit(size: 20, weight: .semibold, relativeTo: .title3) }
}
