import CoreGraphics
import Foundation
import SwiftUI

enum Brand {
  private(set) static var logoPath = ""
  private(set) static var logoPathReversed = ""
  private(set) static var logoViewbox: CGFloat = 512
  private(set) static var logoStrokeWidth: CGFloat = 46

  private(set) static var splashLogoScale: CGFloat = 0.35
  private(set) static var splashLogoColorLight = Color.white
  private(set) static var splashLogoColorDark = Color.black

  private static var loaded = false

  static func load() {
    if loaded { return }
    loaded = true

    guard
      let url = Bundle.main.url(forResource: "Brand", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let logo = root["logo"] as? [String: Any]
    else { return }

    logoPath = logo["path"] as? String ?? logoPath
    logoPathReversed = reversePath(logoPath)
    logoViewbox = CGFloat(logo["viewbox"] as? Double ?? Double(logoViewbox))
    logoStrokeWidth = CGFloat(logo["stroke_width"] as? Double ?? Double(logoStrokeWidth))

    if let splash = root["splash"] as? [String: Any] {
      splashLogoScale = CGFloat(splash["logo_scale"] as? Double ?? Double(splashLogoScale))
      if let hex = splash["logo_color_light"] as? String {
        splashLogoColorLight = colorFromHex(hex)
      }
      if let hex = splash["logo_color_dark"] as? String { splashLogoColorDark = colorFromHex(hex) }
    }
  }

  // MARK: - Reverse Path

  private static func reversePath(_ d: String) -> String {
    let tokens =
      d
      .replacingOccurrences(of: ",", with: " ")
      .replacingOccurrences(of: "([A-Za-z])", with: " $1 ", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
      .split(separator: " ").map(String.init)
    var i = 0

    if tokens[i] == "M" { i += 1 }
    let startX = tokens[i]
    i += 1
    let startY = tokens[i]
    i += 1

    struct Curve { let c1x: String, c1y: String, c2x: String, c2y: String, ex: String, ey: String }
    var curves: [Curve] = []

    while i < tokens.count {
      if tokens[i] == "C" || tokens[i] == "c" { i += 1 }
      curves.append(
        Curve(
          c1x: tokens[i], c1y: tokens[i + 1],
          c2x: tokens[i + 2], c2y: tokens[i + 3],
          ex: tokens[i + 4], ey: tokens[i + 5]))
      i += 6
    }

    var points = [(startX, startY)]
    curves.forEach { points.append(($0.ex, $0.ey)) }

    var result = "M\(points.last!.0) \(points.last!.1)"
    for j in stride(from: curves.count - 1, through: 0, by: -1) {
      let c = curves[j]
      let ep = points[j]
      result += "C\(c.c2x) \(c.c2y) \(c.c1x) \(c.c1y) \(ep.0) \(ep.1)"
    }
    return result
  }

  // MARK: - Hex Color

  private static func colorFromHex(_ hex: String) -> Color {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard h.count == 6, let val = UInt64(h, radix: 16) else { return .white }
    let r = Double((val >> 16) & 0xFF) / 255
    let g = Double((val >> 8) & 0xFF) / 255
    let b = Double(val & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
  }
}
