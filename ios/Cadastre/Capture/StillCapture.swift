import ARKit
import Foundation

import CadastreCore

/// High-resolution posed stills, taken on demand during a recording.
///
/// A still is the full 12-megapixel sensor image with its own intrinsics, which
/// is what makes it worth having: the keyframes are 1920 wide and good enough for
/// geometry, but reading a label on a junction box or a stamp on a joist needs
/// the real thing. ADR-0017 makes these an answer surface, not just texture.
final class StillCapture {

  /// One in flight at a time.
  ///
  /// `captureHighResolutionFrame` interrupts the video stream while the sensor
  /// reconfigures, so firing them back to back would stall tracking. The owner
  /// tapping quickly gets one still, not a queue of them.
  private var isCapturing = false
  private var lastCapture: Date = .distantPast

  private let session: ARSession
  private let writer: FrameWriter
  private let minimumInterval: TimeInterval

  init(
    session: ARSession, writer: FrameWriter,
    minimumInterval: TimeInterval = AppConfig.minimumStillInterval
  ) {
    self.session = session
    self.writer = writer
    self.minimumInterval = minimumInterval
  }

  /// Whether a tap right now would take a still.
  var isReady: Bool {
    !isCapturing && Date().timeIntervalSince(lastCapture) >= minimumInterval
  }

  /// Take one still. `completion` runs on the writer queue.
  ///
  /// `keyframeIndex` ties the still to the most recent keyframe so the pipeline
  /// can place it in the trajectory without matching on timestamps; -1 means the
  /// still came before any keyframe, which is legal and the format expects it.
  func capture(
    stillIndex: Int,
    keyframeIndex: Int,
    completion: @escaping (FrameWriter.Outcome) -> Void
  ) {
    guard isReady else { return }
    isCapturing = true
    lastCapture = Date()

    session.captureHighResolutionFrame { [weak self] frame, error in
      guard let self else { return }
      defer { self.isCapturing = false }

      guard let frame, error == nil else {
        completion(.failed(error ?? StillFailure.noFrame))
        return
      }

      let (tracking, reason) = ARKitBridge.tracking(frame.camera.trackingState)
      let resolution = frame.camera.imageResolution
      let record = StillRecord(
        stillIndex: stillIndex,
        index: keyframeIndex,
        time: frame.timestamp,
        poseWorldFromCamera: ARKitBridge.transform(frame.camera.transform),
        // The still's own intrinsics, not the keyframe's: this image is several
        // times wider, so K differs and the format stores it per still.
        intrinsics: ARKitBridge.intrinsics(frame.camera.intrinsics),
        width: Int(resolution.width),
        height: Int(resolution.height),
        exposureDuration: frame.camera.exposureDuration,
        exposureOffset: Double(frame.camera.exposureOffset),
        tracking: tracking,
        reason: reason,
        thermal: ARKitBridge.thermal(ProcessInfo.processInfo.thermalState),
        path: StillRecord.path(forStill: stillIndex))

      self.writer.write(still: record, colour: frame.capturedImage, completion: completion)
    }
  }

  enum StillFailure: Error {
    case noFrame
  }
}
