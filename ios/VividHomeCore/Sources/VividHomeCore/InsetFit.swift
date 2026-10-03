import Foundation

/// Fitting house-frame points into a small box on screen, for the plan inset
/// the HUD shows while a guided room is captured (ADR-0031, design §3).
///
/// House `x` goes right and house `z` goes down the page, the way the plan is
/// read (`planToHouse` maps the drawing's `v` down to `+z`), so the inset is
/// the drawing, not a mirror of it. The fit is uniform: one scale for both
/// axes, the shape centred, with a margin so corner dots are not clipped.
public struct InsetFit: Equatable, Sendable {
  public var scale: Double
  public var offsetX: Double
  public var offsetY: Double

  /// A fit of `points` (house `x`, `z`) into `width` by `height` with `margin`
  /// on every side. Nil with no points or a box with no room in it.
  public init?(points: [(x: Double, z: Double)], width: Double, height: Double, margin: Double) {
    guard !points.isEmpty, width > 2 * margin, height > 2 * margin else { return nil }
    let minX = points.map { $0.x }.min()!, maxX = points.map { $0.x }.max()!
    let minZ = points.map { $0.z }.min()!, maxZ = points.map { $0.z }.max()!
    let spanX = maxX - minX, spanZ = maxZ - minZ
    // An axis with no extent sets no scale: a single point, or points on one
    // line, take the other axis's scale and sit centred on this one.
    var limits: [Double] = []
    if spanX > 1e-9 { limits.append((width - 2 * margin) / spanX) }
    if spanZ > 1e-9 { limits.append((height - 2 * margin) / spanZ) }
    scale = limits.min() ?? 1
    offsetX = (width - spanX * scale) / 2 - minX * scale
    offsetY = (height - spanZ * scale) / 2 - minZ * scale
  }

  /// House metres to inset points.
  public func point(x: Double, z: Double) -> (x: Double, y: Double) {
    (x * scale + offsetX, z * scale + offsetY)
  }
}
