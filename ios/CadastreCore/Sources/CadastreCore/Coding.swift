import Foundation

/// Camera intrinsics: 9 numbers in **row-major** order, `[fx, 0, cx, 0, fy, cy, 0, 0, 1]`,
/// in pixels of the image they accompany. See `docs/session-format.md` §3.
///
/// Row-major, unlike ``Transform``, because that is what the format says. The two
/// orders sitting side by side in the same JSON line is exactly the kind of detail
/// a named type should carry rather than a bare array.
public struct Intrinsics: Equatable, Sendable {
  public static let elementCount = 9

  public let elements: [Double]

  public init?(elements: [Double]) {
    guard elements.count == Self.elementCount else { return nil }
    self.elements = elements
  }

  public init(fx: Double, fy: Double, cx: Double, cy: Double) {
    self.elements = [fx, 0, cx, 0, fy, cy, 0, 0, 1]
  }

  public var fx: Double { elements[0] }
  public var cx: Double { elements[2] }
  public var fy: Double { elements[4] }
  public var cy: Double { elements[5] }

  /// Intrinsics for the depth map, which covers the same field of view at a
  /// lower resolution: `fx_d = fx * dw/w`, `cx_d = cx * dw/w`, and likewise for y.
  ///
  /// From `docs/session-format.md` §3, "Depth registration".
  public func scaled(fromWidth: Int, height: Int, toWidth: Int, height depthHeight: Int)
    -> Intrinsics
  {
    let sx = Double(toWidth) / Double(fromWidth)
    let sy = Double(depthHeight) / Double(height)
    return Intrinsics(fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy)
  }

  /// Validation rule 5: `fx, fy > 0`, and the principal point inside the image.
  public func isPlausible(width: Int, height: Int) -> Bool {
    fx > 0 && fy > 0 && (0...Double(width)).contains(cx) && (0...Double(height)).contains(cy)
  }
}

// MARK: - Codable conformances matching the on-disk shapes

/// Encodes as the flat 16-number column-major array the format specifies, so a
/// record holding a `Transform` round-trips to exactly the documented JSON.
extension Transform: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let values = try container.decode([Double].self)
    guard let transform = Transform(elements: values) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription:
          "expected \(Transform.elementCount) numbers in column-major order, got \(values.count)")
    }
    self = transform
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(elements)
  }
}

extension Intrinsics: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let values = try container.decode([Double].self)
    guard let intrinsics = Intrinsics(elements: values) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription:
          "expected \(Intrinsics.elementCount) numbers in row-major order, got \(values.count)")
    }
    self = intrinsics
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(elements)
  }
}

/// Encodes as `[x, y, z]`, the shape `p_w` uses in `landmarks.jsonl`.
extension Vector3: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let values = try container.decode([Double].self)
    guard values.count == 3 else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "expected 3 numbers, got \(values.count)")
    }
    self.init(values[0], values[1], values[2])
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode([x, y, z])
  }

  /// Whether every component is finite, for validation rule 8.
  public var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite
  }
}
