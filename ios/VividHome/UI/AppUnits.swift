import Foundation
import VividHomeCore

/// How this phone writes lengths: feet and inches unless the owner picks
/// metric on the project screen. Everything recorded stays in meters; this
/// is only what is shown.
enum AppUnits {
  /// The `UserDefaults` key the picker writes.
  static let key = "units"

  static var current: Units {
    Units(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .imperial
  }
}
