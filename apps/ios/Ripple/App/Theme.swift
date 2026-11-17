import SwiftUI

/// Pond's default dark theme. Values are fixed in CLAUDE.md; add none here.
enum Theme {
    static let background = Color("Background")
    static let foreground = Color(red: 0.933, green: 0.933, blue: 0.933)
    static let muted = foreground.opacity(0.55)
    static let surface = foreground.opacity(0.07)
    static let border = foreground.opacity(0.12)
    static let accent = Color("AccentColor")

    static let radiusCard: CGFloat = 6
    static let radiusControl: CGFloat = 8
    static let unit: CGFloat = 4

    static let gutter = unit * 4
    static let rowHeight: CGFloat = 44
    static let iconColumn: CGFloat = 22
}

extension Font {
    static let small = inter(12, .regular)
    static let text = inter(14, .regular)
    static let textStrong = inter(14, .medium)
    static let heading = inter(16, .medium)
    static let display = inter(26, .semibold)

    private static func inter(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom("InterVariable", size: size).weight(weight)
    }
}

/// UIKit mirrors of the Font tokens, for system chrome SwiftUI can't style.
extension UIFont {
    static let small = inter(12, .regular)
    static let heading = inter(16, .medium)
    static let display = inter(26, .semibold)

    private static func inter(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Inter Variable",
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}
