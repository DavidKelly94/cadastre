import ARKit
import Foundation
import UIKit

import VividHomeCore

/// Something that wants each frame. The recorder is the only implementer; the
/// protocol exists so the controller need not know about it.
protocol ARFrameObserver: AnyObject {
  func session(didUpdate frame: ARFrame, thermal: ThermalState)
}

/// Something that wants anchor changes. The marker logger is the only implementer.
protocol ARAnchorObserver: AnyObject {
  func session(didObserve anchors: [ARAnchor], time: Double)
}

/// Owning the `ARSession`: configuration, capability guards, and fanning the
/// delegate callbacks out to whatever is listening.
///
/// Deliberately thin, because none of it can be tested here (ADR-0016). It holds
/// no policy — what counts as a keyframe, when to refuse to start, how to pack a
/// depth buffer all live in VividHomeCore or the recorder. What is left is Apple's
/// documented setup and a fan-out.
///
/// Not marked `@MainActor` on purpose. `ARSessionDelegate`'s methods are not
/// actor-isolated, and `ARSession` calls them on the main queue when
/// `delegateQueue` is nil, which it is here. Annotating the class would mean
/// either isolation warnings on every delegate method or an `assumeIsolated`
/// wrapper asserting what is already true. Rule 5 keeps this on Swift 5 language
/// mode, so the plain version is the honest one.
final class ARSessionController: NSObject, ObservableObject {

  /// Why this phone cannot record, in the owner's words rather than Apple's.
  enum Unsupported: Equatable {
    case noWorldTracking
    case noSceneDepth
    case noSceneReconstruction

    var message: String {
      switch self {
      case .noWorldTracking:
        return "This iPhone cannot run world tracking, which VividHome needs to record."
      case .noSceneDepth:
        return "This iPhone has no LiDAR scanner. VividHome needs one: an iPhone 15 Pro or newer."
      case .noSceneReconstruction:
        return "This iPhone cannot build a scene mesh. VividHome needs an iPhone Pro with LiDAR."
      }
    }
  }

  /// Everything the HUD shows, republished each frame it changes.
  struct Status: Equatable {
    var tracking: TrackingState = .notAvailable
    var reason: TrackingReason = .none
    var thermal: ThermalState = .nominal
    var isInterrupted = false
  }

  let session = ARSession()
  @Published private(set) var status = Status()

  /// Listeners. Weak, so a screen going away does not keep a recorder alive.
  private weak var recorder: ARFrameObserver?
  private weak var anchorObserver: ARAnchorObserver?

  /// Reference images are built once: decoding sixty PNGs and validating them
  /// takes long enough that doing it per session would be visible when starting
  /// a recording.
  private var referenceImages: Set<ARReferenceImage> = []
  private(set) var referenceImageFailures: [String] = []

  override init() {
    super.init()
    session.delegate = self
  }

  // MARK: - Capability

  /// The first reason this phone cannot record, or nil if it can.
  ///
  /// Checked before anything else is built: the answer decides whether Onboarding
  /// shows a wall or a start button, and it cannot change at runtime.
  static var unsupportedReason: Unsupported? {
    guard ARWorldTrackingConfiguration.isSupported else { return .noWorldTracking }
    guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
      return .noSceneDepth
    }
    guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
      return .noSceneReconstruction
    }
    return nil
  }

  // MARK: - Listeners

  func setRecorder(_ observer: ARFrameObserver?) {
    recorder = observer
  }

  func setAnchorObserver(_ observer: ARAnchorObserver?) {
    anchorObserver = observer
  }

  // MARK: - Running

  /// The configuration described in `docs/design/ios-app-design.md` §4.
  ///
  /// `automaticImageScaleEstimationEnabled` is off on purpose: the markers are
  /// printed at a known size and verified with a tape, so ARKit's estimate can
  /// only make a good number worse.
  func configuration(preferredFrameRate: Int = 30) -> ARWorldTrackingConfiguration {
    let config = ARWorldTrackingConfiguration()
    config.worldAlignment = .gravity
    config.frameSemantics = [.sceneDepth]
    config.sceneReconstruction = .meshWithClassification
    config.environmentTexturing = .none
    // Raycasts against estimated planes still work with detection off, and plane
    // detection is not free; landmarks are the only thing that needs a surface.
    config.planeDetection = []
    config.isAutoFocusEnabled = true

    if let format = Self.videoFormat(framesPerSecond: preferredFrameRate) {
      config.videoFormat = format
    }

    config.detectionImages = referenceImages
    config.maximumNumberOfTrackedImages = 4
    config.automaticImageScaleEstimationEnabled = false
    return config
  }

  /// The 1920-wide format at the requested rate, falling back to any 1920-wide
  /// one, then to ARKit's default.
  ///
  /// Thirty rather than sixty by default, for thermal headroom: a long capture
  /// that throttles produces worse data than a slower one that does not.
  private static func videoFormat(framesPerSecond: Int) -> ARConfiguration.VideoFormat? {
    let formats = ARWorldTrackingConfiguration.supportedVideoFormats
    if let exact = formats.first(where: {
      Int($0.imageResolution.width) == AppConfig.colourWidth
        && $0.framesPerSecond == framesPerSecond
    }) {
      return exact
    }
    return formats.first(where: { Int($0.imageResolution.width) == AppConfig.colourWidth })
  }

  func start(preferredFrameRate: Int = 30) {
    session.run(
      configuration(preferredFrameRate: preferredFrameRate),
      options: [.resetTracking, .removeExistingAnchors])
  }

  func pause() {
    session.pause()
  }

  // MARK: - Reference images

  /// Build `ARReferenceImage`s from the bundled marker PNGs.
  ///
  /// A marker that fails `validate` is kept anyway. ARKit's complaint is about
  /// on-device detection, and the pipeline finds the same tag offline with
  /// AprilTag, so dropping it would lose a sighting the pipeline could have
  /// used. The failures are surfaced instead: one marker failing is a curiosity,
  /// a whole sheet failing means the print is bad, and that is worth knowing
  /// before a capture rather than after.
  ///
  /// Sequential rather than concurrent. `ARReferenceImage` is not `Sendable`, the
  /// work happens once at launch off the critical path, and sixty validations
  /// that finish a moment later cost nothing worth a concurrency argument.
  func loadReferenceImages(width: Double = AppConfig.markerPhysicalWidth) async {
    var images: Set<ARReferenceImage> = []
    var failures: [String] = []

    for number in 0..<AppConfig.markerCount {
      let name = MarkerID.string(for: number)
      guard let cgImage = Self.bundledMarker(named: name) else {
        failures.append(name)
        continue
      }
      let image = ARReferenceImage(cgImage, orientation: .up, physicalWidth: CGFloat(width))
      image.name = name
      if await Self.isRejected(image) {
        failures.append(name)
      }
      images.insert(image)
    }

    referenceImages = images
    referenceImageFailures = failures.sorted()
  }

  private static func bundledMarker(named name: String) -> CGImage? {
    let url =
      Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Markers")
      ?? Bundle.main.url(forResource: name, withExtension: "png")
    guard let url, let image = UIImage(contentsOfFile: url.path) else { return nil }
    return image.cgImage
  }

  /// ARKit's own quality check, as a value rather than a callback.
  private static func isRejected(_ image: ARReferenceImage) async -> Bool {
    await withCheckedContinuation { continuation in
      image.validate { error in
        continuation.resume(returning: error != nil)
      }
    }
  }
}

// MARK: - ARSessionDelegate

extension ARSessionController: ARSessionDelegate {
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let thermal = ARKitBridge.thermal(ProcessInfo.processInfo.thermalState)
    let (state, reason) = ARKitBridge.tracking(frame.camera.trackingState)
    if status.tracking != state || status.reason != reason || status.thermal != thermal {
      status.tracking = state
      status.reason = reason
      status.thermal = thermal
    }
    // The recorder copies what it needs and returns without retaining the frame.
    // Retaining an `ARFrame` stops ARKit delivering any more.
    recorder?.session(didUpdate: frame, thermal: thermal)
  }

  func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    anchorObserver?.session(didObserve: anchors, time: session.currentFrame?.timestamp ?? 0)
  }

  func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    anchorObserver?.session(didObserve: anchors, time: session.currentFrame?.timestamp ?? 0)
  }

  func sessionWasInterrupted(_ session: ARSession) {
    status.isInterrupted = true
  }

  func sessionInterruptionEnded(_ session: ARSession) {
    status.isInterrupted = false
  }
}
