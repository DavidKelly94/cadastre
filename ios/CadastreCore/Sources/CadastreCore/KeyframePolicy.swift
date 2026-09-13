import Foundation

/// Decides which ARKit frames become keyframes.
///
/// Two independent ideas, and keeping them separate is the point:
///
/// - `minDt` is a **rate cap**. At the documented 0.1 s it allows at most ten
///   keyframes a second however fast the phone moves, which is what keeps a
///   five-minute room inside the size budget in `docs/session-format.md` §10.
/// - `minTranslation` and `minRotationDegrees` are **motion gates**. Either one
///   passing is enough, because turning on the spot in a doorway reveals as much
///   new geometry as walking does.
///
/// So a frame is kept when the rate cap has elapsed *and* the phone has moved or
/// turned enough. A phone held still produces no keyframes after the first, which
/// is intended: the pipeline gains nothing from a hundred copies of one view.
public struct KeyframePolicy: Sendable {
  public let settings: KeyframePolicySettings

  /// The frame most recently kept, against which the next one is judged.
  private var lastKept: (time: Double, pose: Transform)?

  /// The thresholds in `docs/session-format.md` §4.
  public static let documentedDefault = KeyframePolicySettings(
    minDt: 0.1, minTranslation: 0.10, minRotationDegrees: 5.0)

  public init(settings: KeyframePolicySettings = KeyframePolicy.documentedDefault) {
    self.settings = settings
  }

  /// Whether `pose` at `time` should be kept, recording it as the new reference
  /// when it is.
  public mutating func shouldKeep(time: Double, pose: Transform) -> Bool {
    guard let previous = lastKept else {
      lastKept = (time, pose)
      return true
    }

    guard time - previous.time >= settings.minDt else { return false }

    let moved = Self.distance(from: previous.pose.translation, to: pose.translation)
    if moved >= settings.minTranslation {
      lastKept = (time, pose)
      return true
    }

    let turned = previous.pose.rotationAngle(to: pose) * 180.0 / .pi
    if turned >= settings.minRotationDegrees {
      lastKept = (time, pose)
      return true
    }

    return false
  }

  /// Forgets the reference frame, so the next frame offered is kept.
  ///
  /// Used after a tracking interruption, where the pose before and the pose after
  /// are not comparable.
  public mutating func reset() {
    lastKept = nil
  }

  public static func distance(from a: Vector3, to b: Vector3) -> Double {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let dz = b.z - a.z
    return (dx * dx + dy * dy + dz * dz).squareRoot()
  }
}
