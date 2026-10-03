import Foundation

/// Calibrating a plan on the phone (ADR-0030): the scale from two points a
/// known distance apart, the origin, and the two projections between house
/// metres and plan pixels.
///
/// Every formula here mirrors `plan.py` exactly, and the tests pin the Swift to
/// numbers the Python produced for the same inputs, because a plan calibrated
/// on the phone is read by the PC and the two must agree to the pixel.
extension PlanFile {
  /// This plan with a scale and origin set.
  ///
  /// `a` and `b` are two plan pixels a known distance apart, `distanceMetres`
  /// that distance, `origin` the pixel that is house (0, 0). Nil when the two
  /// points are the same pixel or the distance is not positive: a scale of
  /// zero or infinity is not a calibration.
  public func calibrated(
    scaleFrom a: (x: Double, y: Double),
    to b: (x: Double, y: Double),
    distanceMetres: Double,
    origin: (x: Double, y: Double),
    rotationDegrees: Double = 0,
    floorHeight: Double = 0
  ) -> PlanFile? {
    let pixels = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    guard pixels > 0, distanceMetres > 0 else { return nil }
    var plan = self
    plan.metresPerPixel = distanceMetres / pixels
    plan.originPx = [origin.x, origin.y]
    plan.rotationDegrees = rotationDegrees
    plan.floorHeight = floorHeight
    return plan
  }

  /// House metres to plan pixels, or nil when uncalibrated.
  public func houseToPlan(x: Double, z: Double) -> (u: Double, v: Double)? {
    guard let metresPerPixel, let originPx, originPx.count == 2 else { return nil }
    let angle = rotationDegrees * .pi / 180
    let c = cos(angle), s = sin(angle)
    let rx = c * x - s * z
    let rz = s * x + c * z
    return (originPx[0] + rx / metresPerPixel, originPx[1] + rz / metresPerPixel)
  }

  /// Plan pixels to house metres, or nil when uncalibrated.
  public func planToHouse(u: Double, v: Double) -> (x: Double, z: Double)? {
    guard let metresPerPixel, let originPx, originPx.count == 2 else { return nil }
    let du = (u - originPx[0]) * metresPerPixel
    let dv = (v - originPx[1]) * metresPerPixel
    let angle = -rotationDegrees * .pi / 180
    let c = cos(angle), s = sin(angle)
    return (c * du - s * dv, s * du + c * dv)
  }

  /// How wide the drawing is in metres at this scale: the sanity check the
  /// owner makes after calibrating, shown rather than left to arithmetic.
  public func widthMetres(imageWidth: Double) -> Double? {
    metresPerPixel.map { $0 * imageWidth }
  }
}

/// A real-world distance as the owner types it: `3.81m`, `381cm`, `12' 6"`,
/// `11'-6"`, `6 1/2"`, or a bare number in metres.
///
/// The same rules as `parse_distance` in `plan.py`: a bare number is metres
/// because the rest of the system is metric and a silent unit change would be
/// worse than a rejected input; a dash between feet and inches separates, as
/// architects print it, and never negates; inches may carry a fraction.
public enum PlanDistance {
  public static func metres(from value: String) -> Double? {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for (fancy, plain) in [("’", "'"), ("′", "'"), ("”", "\""), ("″", "\"")] {
      text = text.replacingOccurrences(of: fancy, with: plain)
    }
    guard !text.isEmpty else { return nil }

    if text.hasSuffix("mm") {
      return number(String(text.dropLast(2))).map { $0 / 1000 }
    }
    if text.hasSuffix("cm") {
      return number(String(text.dropLast(2))).map { $0 / 100 }
    }
    if text.hasSuffix("m") {
      return number(String(text.dropLast()))
    }

    if text.contains("'") || text.contains("\"") {
      var feet = 0.0
      var rest = text
      if let apostrophe = text.firstIndex(of: "'") {
        let head = text[..<apostrophe].trimmingCharacters(in: .whitespaces)
        if !head.isEmpty {
          guard let value = number(head) else { return nil }
          feet = value
        }
        rest = String(text[text.index(after: apostrophe)...])
      }
      rest = rest.replacingOccurrences(of: "\"", with: "")
        .trimmingCharacters(in: .whitespaces)
      while rest.hasPrefix("-") { rest.removeFirst() }
      rest = rest.trimmingCharacters(in: .whitespaces)
      var inches = 0.0
      if !rest.isEmpty {
        guard let value = inchesValue(rest) else { return nil }
        inches = value
      }
      return feet * 0.3048 + inches * 0.0254
    }

    return number(text)
  }

  /// `6`, `6 1/2` or `5/8`.
  private static func inchesValue(_ text: String) -> Double? {
    var total = 0.0
    for part in text.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
      if let slash = part.firstIndex(of: "/") {
        guard let numerator = number(String(part[..<slash])),
          let denominator = number(String(part[part.index(after: slash)...])),
          denominator != 0
        else { return nil }
        total += numerator / denominator
      } else {
        guard let value = number(String(part)) else { return nil }
        total += value
      }
    }
    return total
  }

  private static func number(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces))
  }
}
