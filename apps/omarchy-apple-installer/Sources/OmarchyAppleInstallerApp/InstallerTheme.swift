import AppKit
import SwiftUI

/// Design tokens for the approved installer look: native macOS shapes and
/// spacing, omarchy.org's Tokyo Night colours (blue accent), light and dark
/// palettes that follow the system appearance.
enum OmarchyTheme {
  // MARK: Palette

  // Dark palette: omarchy.org's Tokyo Night tokens (background night/storm,
  // terminal white/blue/black, red and yellow from the same scheme). Light
  // palette: the Tokyo Night "Day" counterparts.
  static let window = dynamic(light: 0xE1_E2E7, dark: 0x1A_1B26)
  static let sidebar = dynamic(light: 0xD0_D5E3, dark: 0x24_283B)
  static let content = dynamic(light: 0xE9_EAF0, dark: 0x1A_1B26)
  static let card = dynamic(light: 0xFF_FFFF, dark: 0x24_283B)
  static let text = dynamic(light: 0x24_283B, dark: 0xC0_CAF5)
  static let secondaryText = dynamic(light: 0x61_72B0, dark: 0x9A_A5CE)
  static let separator = dynamic(light: 0xC4_C8DA, dark: 0x41_4868)
  static let track = dynamic(light: 0xD0_D5E3, dark: 0x2F_334D)
  static let accent = dynamic(light: 0x2E_7DE9, dark: 0x7A_A2F7)
  static let accentText = dynamic(light: 0xFF_FFFF, dark: 0x1A_1B26)
  static let danger = dynamic(light: 0xF5_2A65, dark: 0xF7_768E)
  static let caution = dynamic(light: 0x8C_6C3E, dark: 0xE0_AF68)

  static var accentSoft: Color { accent.opacity(0.14) }

  // MARK: Metrics

  static let railWidth: CGFloat = 208
  static let contentPadding: CGFloat = 28
  static let cardRadius: CGFloat = 10
  static let contentMaxWidth: CGFloat = 640

  // MARK: Type

  static let headline = Font.system(size: 22, weight: .semibold)
  static let subheadline = Font.system(size: 13)
  static let panelTitle = Font.system(size: 11, weight: .semibold)
  static let body = Font.system(size: 12.5)
  static let caption = Font.system(size: 11)
  static let monospaceSmall = Font.system(size: 10.5, design: .monospaced)

  private static func dynamic(light: Int, dark: Int) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark =
          appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex: isDark ? dark : light)
      }
    )
  }
}

extension NSColor {
  fileprivate convenience init(hex: Int) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
