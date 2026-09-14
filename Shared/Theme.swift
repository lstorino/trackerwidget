import SwiftUI

/// Master theme for the unified tracker panel. Each tab tints the same
/// layout with its own navy/gray palette; structure and metrics stay
/// identical across tabs.
enum Theme {
  // Shared structural metrics — same on every tab.
  static let corner: CGFloat = 12
  static let monoFont = Font.system(size: 12, weight: .semibold, design: .monospaced)
  static let rowFont = Font.system(size: 12, weight: .regular)
  static let obsFont = Font.system(size: 10, weight: .regular)
  static let sectionFont = Font.system(size: 10, weight: .semibold)
  static let tabFont = Font.system(size: 11, weight: .semibold)

  static let up = Color(red: 0.37, green: 0.84, blue: 0.48)    // green
  static let down = Color(red: 1.0, green: 0.42, blue: 0.38)   // red

  /// Per-tab palette: navy-blue family and gray family, contrasting data.
  struct Palette {
    let background: Color   // panel bg
    let surface: Color      // tab bar / footer bg
    let border: Color
    let text: Color
    let dim: Color
    let faint: Color
    let accent: Color       // tab underline / highlights
    let activeTabBg: Color
    let inactiveTabBg: Color
  }

  static let pig = Palette(
    background: Color(nsColor: NSColor(red: 0.09, green: 0.13, blue: 0.24, alpha: 1)),  // navy
    surface:   Color(nsColor: NSColor(red: 0.07, green: 0.10, blue: 0.19, alpha: 1)),
    border: Color.white.opacity(0.10),
    text: Color.white.opacity(0.94),
    dim: Color.white.opacity(0.50),
    faint: Color.white.opacity(0.28),
    accent: Color(red: 0.36, green: 0.56, blue: 0.94),   // steel blue
    activeTabBg: Color.white.opacity(0.10),
    inactiveTabBg: Color.white.opacity(0.03)
  )

  static let shrimp = Palette(
    background: Color(nsColor: NSColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1)),  // slate gray
    surface:   Color(nsColor: NSColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1)),
    border: Color.white.opacity(0.10),
    text: Color.white.opacity(0.94),
    dim: Color.white.opacity(0.50),
    faint: Color.white.opacity(0.28),
    accent: Color(red: 0.55, green: 0.62, blue: 0.75),   // cool gray-blue
    activeTabBg: Color.white.opacity(0.10),
    inactiveTabBg: Color.white.opacity(0.03)
  )

  static let grains = Palette(
    background: Color(nsColor: NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1)),  // charcoal gray
    surface:   Color(nsColor: NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)),
    border: Color.white.opacity(0.10),
    text: Color.white.opacity(0.94),
    dim: Color.white.opacity(0.50),
    faint: Color.white.opacity(0.28),
    accent: Color(red: 0.83, green: 0.63, blue: 0.09),   // grain gold
    activeTabBg: Color.white.opacity(0.10),
    inactiveTabBg: Color.white.opacity(0.03)
  )

  /// Maps an ISO country code to an emoji flag.
  /// Regional Indicator A..Z = U+1F1E6..U+1F1FF, i.e. 0x1F1E6 + (letter - 'A').
  static func flagEmoji(_ code: String) -> String {
    let upper = code.uppercased()
    guard upper.count == 2,
          let first = upper.first?.unicodeScalars.first,
          let last = upper.last?.unicodeScalars.first,
          (65...90).contains(first.value), (65...90).contains(last.value),
          let s1 = UnicodeScalar(0x1F1E6 + first.value - 65),
          let s2 = UnicodeScalar(0x1F1E6 + last.value - 65) else { return "🏳️" }
    return String(String.UnicodeScalarView([s1, s2]))
  }
}
