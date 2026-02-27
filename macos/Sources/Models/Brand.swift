import CoreGraphics
import CoreText
import Foundation
import SwiftUI

enum Brand {
    private(set) static var logoPath = ""
    private(set) static var logoViewbox: CGFloat = 512

    static let fontName = "SofiaSans-Regular"

    static let splashLogoScale: CGFloat = 0.35
    static let splashLogoColorLight = Color.white
    static let splashLogoColorDark = Color(red: 0.1, green: 0.1, blue: 0.1)

    private static var loaded = false

    static func load() {
        guard !loaded else { return }
        loaded = true

        if let fontURL = Bundle.main.url(forResource: "SofiaSans", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }

        guard
            let url = Bundle.main.url(forResource: "Brand", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let logo = root["logo"] as? [String: Any]
        else { return }

        logoPath = logo["path"] as? String ?? logoPath
        logoViewbox = CGFloat(logo["viewbox"] as? Double ?? Double(logoViewbox))
    }

    // MARK: - Font

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(fontName, size: size).weight(weight)
    }
}
