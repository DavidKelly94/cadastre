import Foundation

/// A point or direction in the session (ARKit world) frame: metres, `+y` up.
public struct Vector3: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var z: Double

  public init(_ x: Double, _ y: Double, _ z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }
}

/// A 4x4 transform in the storage the session format specifies.
///
/// Sixteen numbers in **column-major** order, the memory layout of
/// `simd_float4x4`: the element at row `r`, column `c` is index `c * 4 + r`, and
/// the translation is at indices 12, 13 and 14. See `docs/session-format.md` §3.
///
/// Doubles rather than floats: the file format carries whatever precision the
/// JSON has, and accumulating products in single precision is not worth the
/// memory here.
public struct Transform: Equatable, Sendable {
  /// Number of elements in the column-major representation.
  public static let elementCount = 16

  /// The transform in column-major order, always exactly ``elementCount`` long.
  public let elements: [Double]

  /// Creates a transform, or returns nil if `elements` is not 16 numbers long.
  public init?(elements: [Double]) {
    guard elements.count == Self.elementCount else { return nil }
    self.elements = elements
  }

  private init(unchecked elements: [Double]) {
    self.elements = elements
  }

  /// The identity transform.
  public static let identity = Transform(
    unchecked: [
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ])

  /// A pure translation.
  public static func translation(_ t: Vector3) -> Transform {
    Transform(
      unchecked: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        t.x, t.y, t.z, 1,
      ])
  }

  /// The element at `row` and `column`, both 0-based.
  public subscript(row: Int, column: Int) -> Double {
    precondition((0..<4).contains(row) && (0..<4).contains(column), "index out of range")
    return elements[column * 4 + row]
  }

  /// The translation component, at indices 12, 13 and 14.
  public var translation: Vector3 {
    Vector3(elements[12], elements[13], elements[14])
  }

  /// Matrix product, so `(a * b)` applies `b` first and then `a`.
  public static func * (lhs: Transform, rhs: Transform) -> Transform {
    var out = [Double](repeating: 0, count: elementCount)
    for column in 0..<4 {
      for row in 0..<4 {
        var sum = 0.0
        for k in 0..<4 {
          sum += lhs[row, k] * rhs[k, column]
        }
        out[column * 4 + row] = sum
      }
    }
    return Transform(unchecked: out)
  }

  /// The inverse, or nil when the transform is singular.
  ///
  /// Gauss-Jordan elimination with partial pivoting rather than a rigid-body
  /// shortcut, because the same type carries plan and alignment transforms that
  /// are not guaranteed to be rigid.
  public func inverted() -> Transform? {
    // Row-major working copy, augmented with the identity.
    var a = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 4)
    for row in 0..<4 {
      for column in 0..<4 {
        a[row][column] = self[row, column]
      }
      a[row][4 + row] = 1
    }

    for column in 0..<4 {
      var pivot = column
      for row in (column + 1)..<4 where abs(a[row][column]) > abs(a[pivot][column]) {
        pivot = row
      }
      guard abs(a[pivot][column]) > 1e-12 else { return nil }
      if pivot != column {
        a.swapAt(pivot, column)
      }

      let divisor = a[column][column]
      for k in 0..<8 {
        a[column][k] /= divisor
      }
      for row in 0..<4 where row != column {
        let factor = a[row][column]
        guard factor != 0 else { continue }
        for k in 0..<8 {
          a[row][k] -= factor * a[column][k]
        }
      }
    }

    var out = [Double](repeating: 0, count: Self.elementCount)
    for row in 0..<4 {
      for column in 0..<4 {
        out[column * 4 + row] = a[row][4 + column]
      }
    }
    return Transform(unchecked: out)
  }

  /// The angle in radians of the rotation taking this transform's orientation to
  /// `other`'s, ignoring translation.
  ///
  /// This is the keyframe policy's rotation gate, so it must stay cheap: the
  /// angle comes from `trace(Rᵀ R')`, which is the elementwise product of the two
  /// rotation blocks, with no matrix product built.
  public func rotationAngle(to other: Transform) -> Double {
    var trace = 0.0
    for column in 0..<3 {
      for row in 0..<3 {
        trace += self[row, column] * other[row, column]
      }
    }
    let cosine = min(1.0, max(-1.0, (trace - 1.0) / 2.0))
    return acos(cosine)
  }

  /// Whether the rotation block is orthonormal with a positive determinant.
  ///
  /// Validation rule 4 in `docs/session-format.md` §11, available on both sides
  /// of the contract so the app can refuse to write a pose the pipeline would
  /// reject.
  public func hasOrthonormalRotation(tolerance: Double = 1e-3) -> Bool {
    for i in 0..<3 {
      for j in 0..<3 {
        var dot = 0.0
        for k in 0..<3 {
          dot += self[k, i] * self[k, j]
        }
        let expected = i == j ? 1.0 : 0.0
        guard abs(dot - expected) < tolerance else { return false }
      }
    }
    return determinant3x3 > 0
  }

  private var determinant3x3: Double {
    self[0, 0] * (self[1, 1] * self[2, 2] - self[1, 2] * self[2, 1])
      - self[0, 1] * (self[1, 0] * self[2, 2] - self[1, 2] * self[2, 0])
      + self[0, 2] * (self[1, 0] * self[2, 1] - self[1, 1] * self[2, 0])
  }
}
