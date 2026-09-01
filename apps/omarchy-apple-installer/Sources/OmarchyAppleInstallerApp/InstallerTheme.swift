import AppKit
import SwiftUI

/// Design tokens for the approved installer look: native macOS shapes and
/// spacing, Omarchy green accent, light and dark palettes that follow the
/// system appearance.
enum OmarchyTheme {
  // MARK: Palette

  static let window = dynamic(light: 0xF1_F3EC, dark: 0x23_261E)
  static let sidebar = dynamic(light: 0xEA_EDE2, dark: 0x27_2B21)
  static let content = dynamic(light: 0xF5_F7F1, dark: 0x19_1C14)
  static let card = dynamic(light: 0xFF_FFFF, dark: 0x24_2820)
  static let text = dynamic(light: 0x1C_2117, dark: 0xE8_EBE2)
  static let secondaryText = dynamic(light: 0x6A_7261, dark: 0xA3_AB97)
  static let separator = dynamic(light: 0xDD_E2D2, dark: 0x34_3A2B)
  static let track = dynamic(light: 0xE3_E7D9, dark: 0x2E_3326)
  static let accent = dynamic(light: 0x4E_8A22, dark: 0x90_D05A)
  static let accentText = dynamic(light: 0xFF_FFFF, dark: 0x0A_0C08)
  static let danger = dynamic(light: 0xC4_372B, dark: 0xFF_6B5E)
  static let caution = dynamic(light: 0x8A_6D1B, dark: 0xF3_C96B)

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
