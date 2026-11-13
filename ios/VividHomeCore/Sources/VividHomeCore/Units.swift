import Foundation

/// How a length is written for the owner to read.
///
/// Everything recorded is in meters, as `docs/session-format.md` fixes, and
/// every threshold is in meters. This is only the last step, the text on a
/// screen: the owner builds in feet and inches and asked on 2026-11-13 for
/// the app to speak that way, with metric still available.
///
/// The pipeline writes the same text from the same numbers
/// (`vividhome/units.py`), and the contract job compares the two, so the
/// rounding below is spelled out rather than left to a formatter.
public enum Units: String, Codable, Sendable, CaseIterable {
  case imperial
  case metric

  private static let metersPerInch = 0.0254

  /// A small distance, such as how well a capture fits its plan:
  /// `7 cm`, or `2 3/4 in` to the nearest quarter inch. A foot or more is
  /// written as a length.
  public func small(_ meters: Double) -> String {
    let value = abs(meters)
    switch self {
    case .metric:
      return "\(Int((value * 100 + 0.5).rounded(.down))) cm"
    case .imperial:
      let quarters = Int((value / Self.metersPerInch * 4 + 0.5).rounded(.down))
      if quarters >= 48 { return length(meters) }
      let whole = quarters / 4
      let part = ["", "1/4", "1/2", "3/4"][quarters % 4]
      if part.isEmpty { return "\(whole) in" }
      return whole == 0 ? "\(part) in" : "\(whole) \(part) in"
    }
  }

  /// A length along a wall or across a room: `1.2 m`, or `3 ft 11 in` to the
  /// nearest inch.
  public func length(_ meters: Double) -> String {
    let value = abs(meters)
    switch self {
    case .metric:
      let tenths = Int((value * 10 + 0.5).rounded(.down))
      return "\(tenths / 10).\(tenths % 10) m"
    case .imperial:
      let inches = Int((value / Self.metersPerInch + 0.5).rounded(.down))
      let feet = inches / 12
      let rest = inches % 12
      if feet == 0 { return "\(rest) in" }
      return rest == 0 ? "\(feet) ft" : "\(feet) ft \(rest) in"
    }
  }

  /// A floor area: `10.0 m²` or `108 sq ft`.
  public func area(_ squareMeters: Double) -> String {
    switch self {
    case .metric:
      let tenths = Int((abs(squareMeters) * 10 + 0.5).rounded(.down))
      return "\(tenths / 10).\(tenths % 10) m²"
    case .imperial:
      let feet = abs(squareMeters) / (0.3048 * 0.3048)
      return "\(Int((feet + 0.5).rounded(.down))) sq ft"
    }
  }

  /// A plan's scale: what one pixel of the drawing covers.
  /// `12.7 mm per pixel` or `0.50 in per pixel`.
  public func perPixel(_ metersPerPixel: Double) -> String {
    switch self {
    case .metric:
      let tenths = Int((abs(metersPerPixel) * 10_000 + 0.5).rounded(.down))
      return "\(tenths / 10).\(tenths % 10) mm per pixel"
    case .imperial:
      let hundredths = Int((abs(metersPerPixel) / Self.metersPerInch * 100 + 0.5).rounded(.down))
      let cents = hundredths % 100
      return "\(hundredths / 100).\(cents < 10 ? "0" : "")\(cents) in per pixel"
    }
  }
}
