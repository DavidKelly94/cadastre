import ARKit
import Foundation

import CadastreCore

/// Recording printed-marker sightings to `markers.jsonl`.
///
/// A marker sighting is the most valuable line in a session: it is the only thing
/// that ties two sessions of the same room, captured weeks apart, into one frame
/// (ADR-0006). Everything else is relative to a world origin that ARKit picks
/// afresh each run.
///
/// What is written is the ARKit **image-anchor** transform, not the canonical
/// marker frame. The two differ by a fixed rotation, and `docs/session-format.md`
/// §8 puts that conversion on the pipeline side deliberately: storing the raw
/// anchor means a wrong `R_am` can be corrected later by reprocessing, where
/// baking it in at capture time would corrupt the record permanently.
final class MarkerLogger: ARAnchorObserver {

  private let writer: JSONLWriter
  private let physicalWidth: Double
  private let throttle: Double

  /// Last write time per marker, so a marker held in view does not fill the file.
  private var lastWrite: [String: Double] = [:]

  /// Called for each observation actually written, so the recorder can count it.
  var onObservation: (() -> Void)?
  /// Called the first time each marker is seen, for the HUD.
  var onFirstSighting: ((String) -> Void)?

  private(set) var seen: Set<String> = []

  init(
    writer: JSONLWriter,
    physicalWidth: Double = AppConfig.markerPhysicalWidth,
    throttleSeconds: Double = AppConfig.markerThrottleSeconds
  ) {
    self.writer = writer
    self.physicalWidth = physicalWidth
    self.throttle = throttleSeconds
  }

  /// The keyframe index to stamp on an observation, supplied by the recorder.
  var currentKeyframeIndex: () -> Int = { -1 }

  func session(didObserve anchors: [ARAnchor], time: Double) {
    for anchor in anchors {
      guard let image = anchor as? ARImageAnchor else { continue }
      guard let name = image.referenceImage.name, MarkerID.isValid(name) else { continue }

      // Five a second per marker. ARKit updates a tracked image anchor every
      // frame, and thirty near-identical lines a second would bury the sighting
      // that matters in noise the pipeline then has to average away.
      if let previous = lastWrite[name], time - previous < throttle { continue }
      lastWrite[name] = time

      if seen.insert(name).inserted {
        onFirstSighting?(name)
      }

      let observation = MarkerObservation(
        time: time,
        index: currentKeyframeIndex(),
        markerID: name,
        poseWorldFromAnchor: ARKitBridge.transform(image.transform),
        tracked: image.isTracked,
        physicalWidth: physicalWidth)

      // A failed line is not worth stopping a capture for: the pipeline finds the
      // same tag offline in the colour frames, so this file is a shortcut rather
      // than the only record.
      try? writer.append(observation)
      onObservation?()
    }
  }
}
