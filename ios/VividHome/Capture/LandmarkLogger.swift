import ARKit
import Foundation

import VividHomeCore

/// Recording tapped room landmarks to `landmarks.jsonl`.
///
/// These are what the pipeline fits the floor plan against (ADR-0007): the owner
/// taps the same wall corners the plan draws, and a 2D similarity from tapped
/// points to plan points puts the session on the drawing. A session with fewer
/// than three good landmarks cannot be aligned, which is why the capture screen
/// counts them.
final class LandmarkLogger {

  enum Failure: Error {
    case noSurface
  }

  private let writer: JSONLWriter

  /// Called for each landmark written, so the recorder can count it.
  var onLandmark: (() -> Void)?

  /// The keyframe index to stamp, supplied by the recorder.
  var currentKeyframeIndex: () -> Int = { -1 }

  init(writer: JSONLWriter) {
    self.writer = writer
  }

  /// Resolve a screen tap to a world position and append it.
  ///
  /// Raycasting against `.estimatedPlane` rather than an existing detected plane:
  /// plane detection is off (it costs frame time and nothing else needs it), and
  /// an estimated plane is what a bare stud wall or an unfinished floor gives you
  /// anyway. The method is recorded in the line so the pipeline can weigh a point
  /// by how it was obtained.
  @discardableResult
  func record(
    tapAt point: CGPoint,
    in view: ARSCNView,
    label: String,
    kind: LandmarkKind,
    time: Double
  ) throws -> Vector3 {
    guard
      let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
      let result = view.session.raycast(query).first
    else {
      throw Failure.noSurface
    }

    let position = ARKitBridge.position(result.worldTransform)
    let record = LandmarkRecord(
      time: time,
      index: currentKeyframeIndex(),
      label: label,
      kind: kind,
      position: position,
      method: "raycast_estimated_plane")

    try writer.append(record)
    onLandmark?()
    return position
  }
}
