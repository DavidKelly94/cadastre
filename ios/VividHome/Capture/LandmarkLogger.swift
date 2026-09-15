import ARKit
import Foundation

import VividHomeCore

/// Resolving taps to room landmarks, and writing them once at the end.
///
/// These are what the pipeline fits the floor plan against (ADR-0007): the owner
/// taps the same wall corners the plan draws, and a 2D similarity from tapped
/// points to plan points puts the session on the drawing. Since [ADR-0026]
/// markers are optional, this is the *only* thing that places a capture on the
/// plan, which is why the capture screen counts them and refuses to finish a
/// room with too few.
///
/// **Nothing is written until the session stops.** A landmark is a small set the
/// owner curates — a handful per room, each one correctable — not a stream to be
/// logged. Appending on every tap made them permanent the instant a raycast
/// landed, so a misjudged tap stayed in the record forever and the file needed
/// correction entries to undo. Holding them in memory makes move and delete free
/// and changes nothing about the file: still one line per landmark, exactly as
/// section 8 specifies.
///
/// The cost is that a crash mid-session loses them. That is the right trade for
/// this data and not for any other: landmarks are four to eight taps and can be
/// redone, where a lost frame stream cannot. A session is one room (ADR-0022), so
/// "written at the end" and "written at the end of the room" are the same moment.
final class LandmarkLogger {

  enum Failure: Error {
    case noSurface
  }

  private let writer: JSONLWriter

  init(writer: JSONLWriter) {
    self.writer = writer
  }

  /// Resolve a screen point to a world position, without recording anything.
  ///
  /// Raycasting against `.estimatedPlane` rather than an existing detected plane:
  /// plane detection is off (it costs frame time and nothing else needs it), and
  /// an estimated plane is what a bare stud wall or an unfinished floor gives you
  /// anyway. The method is recorded in the line so the pipeline can weigh a point
  /// by how it was obtained.
  func resolve(tapAt point: CGPoint, in view: ARSCNView) throws -> Vector3 {
    guard
      let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
      let result = view.session.raycast(query).first
    else {
      throw Failure.noSurface
    }
    return ARKitBridge.position(result.worldTransform)
  }

  /// Write every landmark the owner settled on, in the order they were placed.
  func write(_ landmarks: [PlacedLandmark]) throws {
    for landmark in landmarks {
      try writer.append(
        LandmarkRecord(
          time: landmark.time,
          index: landmark.keyframeIndex,
          label: landmark.label,
          kind: landmark.kind,
          position: landmark.position,
          method: "raycast_estimated_plane"))
    }
  }
}

/// A landmark the owner has placed and can still change.
struct PlacedLandmark: Identifiable, Equatable {
  let id: UUID
  var label: String
  var kind: LandmarkKind
  var position: Vector3
  /// The session time and keyframe it was first placed at. Moving a landmark
  /// keeps both: the record is of a feature noticed at that moment, and a
  /// corrected position does not make it a different observation.
  let time: Double
  let keyframeIndex: Int

  init(
    id: UUID = UUID(), label: String, kind: LandmarkKind, position: Vector3, time: Double,
    keyframeIndex: Int
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.position = position
    self.time = time
    self.keyframeIndex = keyframeIndex
  }
}
