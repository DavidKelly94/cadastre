import ARKit
import Foundation

import VividHomeCore

/// Converting ARKit's types into the plain values VividHomeCore and the session
/// format use.
///
/// This is the whole of the boundary ADR-0016 draws: ARKit types stop here, and
/// nothing past this file imports ARKit. Every conversion is a few lines, but
/// each one is a place the contract could quietly be broken — a transposed
/// matrix, a dropped tracking reason — so they live together where they can be
/// read side by side against `docs/session-format.md`.
enum ARKitBridge {

  /// A 4x4 as the format stores it: column-major, translation at 12, 13, 14.
  ///
  /// `simd_float4x4` already has that memory layout — `columns.3` is the
  /// translation — so this is a flatten, not a transpose. Getting this wrong is
  /// the single most expensive mistake available here, because every pose in
  /// every session would be wrong in a way that still looks like a valid matrix,
  /// which is why `docs/session-format.md` §3 states the order and
  /// `Transform.hasOrthonormalRotation()` exists to catch it in tests.
  static func transform(_ m: simd_float4x4) -> Transform {
    let columns = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
    var elements = [Double]()
    elements.reserveCapacity(Transform.elementCount)
    for column in columns {
      elements.append(Double(column.x))
      elements.append(Double(column.y))
      elements.append(Double(column.z))
      elements.append(Double(column.w))
    }
    // The count is 16 by construction; the failable initialiser guards callers
    // who build one from a file, not this one.
    return Transform(elements: elements) ?? .identity
  }

  /// Camera intrinsics as the format's row-major `K`.
  ///
  /// ARKit hands these as a column-major `simd_float3x3`, and the format wants
  /// row-major, so unlike the pose this one really does transpose. `Intrinsics`
  /// takes the four numbers that matter rather than nine, which sidesteps the
  /// question for everything but this line.
  static func intrinsics(_ k: simd_float3x3) -> Intrinsics {
    Intrinsics(
      fx: Double(k.columns.0.x),
      fy: Double(k.columns.1.y),
      cx: Double(k.columns.2.x),
      cy: Double(k.columns.2.y))
  }

  /// Tracking state, flattened to the two enumerations the format stores.
  ///
  /// ARKit nests the reason inside `.limited`; the format keeps them in separate
  /// fields so a reader can filter on state without parsing a case.
  static func tracking(_ state: ARCamera.TrackingState) -> (TrackingState, TrackingReason) {
    switch state {
    case .normal:
      return (.normal, TrackingReason.none)
    case .notAvailable:
      return (.notAvailable, TrackingReason.none)
    case .limited(let reason):
      switch reason {
      case .initializing: return (.limited, .initializing)
      case .excessiveMotion: return (.limited, .excessiveMotion)
      case .insufficientFeatures: return (.limited, .insufficientFeatures)
      case .relocalizing: return (.limited, .relocalizing)
      @unknown default: return (.limited, TrackingReason.none)
      }
    }
  }

  /// Thermal state. `.critical` is the one that stops a recording (HealthPolicy).
  static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalState {
    switch state {
    case .nominal: return .nominal
    case .fair: return .fair
    case .serious: return .serious
    case .critical: return .critical
    @unknown default: return .critical
    }
  }

  /// The translation column of a world transform, for a landmark position.
  static func position(_ m: simd_float4x4) -> Vector3 {
    Vector3(Double(m.columns.3.x), Double(m.columns.3.y), Double(m.columns.3.z))
  }
}
