import SwiftUI

/// The palette from `docs/ui/design-canvas-brief.md` section 4.
///
/// Only the dark set is here. The capture HUD sits over a camera feed and is
/// always dark regardless of the system appearance; the light tokens arrive with
/// the screens that have a background of their own.
///
/// The contrast ratios in the comments are against `ground` and were computed,
/// not estimated — three tokens in the original light palette failed WCAG and
/// were corrected, so the numbers are load-bearing rather than decorative.
enum Tokens {
  static let ground = Color(hex: 0x0E151C)
  static let raised = Color(hex: 0x18222D)
  static let outline = Color(hex: 0x526B80)  // 3.30:1
  static let ink = Color(hex: 0xE6EEF6)  // 15.7:1
  static let inkSecondary = Color(hex: 0xA2B4C4)  // 8.63:1

  static let accentCool = Color(hex: 0x5AA3E8)  // 6.00:1
  static let accentWarm = Color(hex: 0xE85D22)
  /// A label on `accentWarm` goes dark: on a dark ground the accent has to be
  /// brighter than the surface to find the eye, which flips the text.
  static let onAccentWarm = Color(hex: 0x0E151C)  // 5.27:1

  static let ok = Color(hex: 0x43D17C)  // 9.32:1
  static let warn = Color(hex: 0xFFC24D)  // 11.4:1
  static let error = Color(hex: 0xFF5A5F)  // 6.02:1

  /// The scrim behind HUD chrome. 72% is the documented value; it rises to 88%
  /// over a bright scene, which is not yet implemented — see the note in
  /// `CaptureHUDView`.
  static let scrim = Color(hex: 0x0A121C).opacity(0.72)
  static let hairline = Color.white.opacity(0.12)
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1)
  }
}
