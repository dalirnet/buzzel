import SwiftUI

// MARK: - Design Tokens

enum DesignColor {
    static let text       = Color(nsColor: .labelColor)
    static let secondary  = Color(nsColor: .secondaryLabelColor)
    static let surface    = Color(nsColor: .windowBackgroundColor)
    static let background = Color(nsColor: .controlBackgroundColor)
    static let border     = Color(nsColor: .separatorColor)
    static let accent     = Color(nsColor: .controlAccentColor)
    static let green      = Color(nsColor: .systemGreen)
    static let yellow     = Color(nsColor: .systemYellow)
    static let orange     = Color(nsColor: .systemOrange)
    static let red        = Color(nsColor: .systemRed)
    static let gray       = Color(nsColor: .systemGray)
    static let onButton   = Color.white

    // Soft adaptive colors for large fills (power button)
    static let mutedGray = Color(nsColor: adaptive(
        light: NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1),
        dark:  NSColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1)
    ))
    static let mutedYellow = Color(nsColor: adaptive(
        light: NSColor(red: 0.95, green: 0.78, blue: 0.10, alpha: 1),
        dark:  NSColor(red: 0.92, green: 0.75, blue: 0.08, alpha: 1)
    ))
    static let mutedOrange = Color(nsColor: adaptive(
        light: NSColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1),
        dark:  NSColor(red: 0.92, green: 0.50, blue: 0.08, alpha: 1)
    ))
    static let mutedGreen = Color(nsColor: adaptive(
        light: NSColor(red: 0.20, green: 0.75, blue: 0.38, alpha: 1),
        dark:  NSColor(red: 0.18, green: 0.70, blue: 0.35, alpha: 1)
    ))
    static let mutedRed = Color(nsColor: adaptive(
        light: NSColor(red: 0.90, green: 0.28, blue: 0.25, alpha: 1),
        dark:  NSColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1)
    ))

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
