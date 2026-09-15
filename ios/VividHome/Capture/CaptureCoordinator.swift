import ARKit
import SceneKit
import SwiftUI
import UIKit
import VividHomeCore

/// Assembles the capture layer into something a screen can drive.
///
/// Every part below already existed and was unit tested; none of them had a
/// caller. This is that caller. It owns the lifecycle so the views never have
/// to: which writers exist, in what order things stop, and what the HUD is
/// allowed to show at each moment.
///
/// Not `@MainActor`, for the same reason `ARSessionController` is not: the
/// ARKit delegate callbacks it ultimately feeds are not actor-isolated, and
/// annotating the type would force hops on the per-frame path. Everything here
/// is nonetheless touched from the main thread only, except the still
/// completion, which explicitly hops back.
final class CaptureCoordinator: ObservableObject, ARAnchorObserver {

  enum Phase: Equatable {
    case setup
    case recording
    case finishing(String)
    case review(SessionSummary)
    case failed(String)
  }

  /// What Session review shows. A value type rather than a live reference: once
  /// a session is closed its numbers are final, and holding the recorder would
  /// let them appear to keep moving.
  struct SessionSummary: Equatable {
    var sessionID: String
    var root: URL
    var stats: SessionStats
    var duration: Double
    var level: String
    var room: String
    var phases: [CapturePhase]
    var markersSeen: [String]
    var mesh: MeshExporter.Summary?
    var stoppedBecause: String?
  }

  let controller = ARSessionController()
  let recorder = SessionRecorder()

  @Published private(set) var phase: Phase = .setup
  /// Markers seen this session, in sighting order, for the HUD strip.
  @Published private(set) var markersSeen: [String] = []
  @Published private(set) var landmarkCount = 0
  @Published private(set) var showMesh = false
  @Published private(set) var freeBytes: Int64 = 0
  /// "Kitchen · Electrical + Plumbing", for the HUD strip.
  @Published private(set) var contextLabel = ""

  private var stillCapture: StillCapture?
  private var markerLogger: MarkerLogger?
  private var landmarkLogger: LandmarkLogger?
  private var markersWriter: JSONLWriter?
  private var landmarksWriter: JSONLWriter?
  private weak var arView: ARSCNView?
  private var placedLandmarks: [SCNNode] = []
  private var markerNodes: [UUID: SCNNode] = [:]

  private var level = LevelRef(slug: "l1", name: "Level 1", index: 1)
  private var room = SlugRef(slug: "room", name: "Room")
  private var phases: [CapturePhase] = []

  private let project = SlugRef(slug: "our-house", name: "Our house")

  private var documents: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  // MARK: - View attachment

  func attach(view: ARSCNView) {
    arView = view
    view.session = controller.session
    view.automaticallyUpdatesLighting = true
    controller.start()
    Task { await controller.loadReferenceImages() }
  }

  func setShowMesh(_ on: Bool) {
    showMesh = on
    arView?.debugOptions = on ? [.showWireframe] : []
  }

  // MARK: - Start

  func start(level: LevelRef, room: SlugRef, phases: [CapturePhase], notes: String?) {
    self.level = level
    self.room = room
    self.phases = phases

    do {
      try recorder.start(
        documents: documents,
        project: project,
        level: level,
        room: room,
        phases: phases,
        notes: notes,
        expectedMarkers: [],
        videoFormat: VideoFormat(
          w: AppConfig.colourWidth, h: AppConfig.colourHeight, fps: 30))

      // Available only once `start` has succeeded: the layout and the frame
      // writer are both created in there.
      guard let layout = recorder.layout, let writer = recorder.frameWriter else {
        phase = .failed("The recorder started without a layout, which should be impossible.")
        return
      }

      // Creating these also creates the two files. `vividhome validate` requires
      // both to exist even when nothing was logged, so an empty session with no
      // markers still validates.
      let markers = try JSONLWriter(url: layout.markers)
      let landmarks = try JSONLWriter(url: layout.landmarks)
      markersWriter = markers
      landmarksWriter = landmarks

      let markerLogger = MarkerLogger(writer: markers)
      markerLogger.currentKeyframeIndex = { [weak self] in
        self?.recorder.currentKeyframeIndex ?? -1
      }
      markerLogger.onObservation = { [weak self] in
        self?.recorder.recordMarkerObservation()
      }
      markerLogger.onFirstSighting = { [weak self] id in
        DispatchQueue.main.async { self?.markersSeen.append(id) }
      }
      self.markerLogger = markerLogger

      let landmarkLogger = LandmarkLogger(writer: landmarks)
      landmarkLogger.currentKeyframeIndex = { [weak self] in
        self?.recorder.currentKeyframeIndex ?? -1
      }
      landmarkLogger.onLandmark = { [weak self] in
        self?.recorder.recordLandmark()
      }
      self.landmarkLogger = landmarkLogger

      stillCapture = StillCapture(session: controller.session, writer: writer)

      markersSeen = []
      landmarkCount = 0
      placedLandmarks.forEach { $0.removeFromParentNode() }
      placedLandmarks = []
      markerNodes.values.forEach { $0.removeFromParentNode() }
      markerNodes = [:]
      contextLabel = room.name + " · " + phases.map(\.shortName).joined(separator: " + ")
      controller.setRecorder(recorder)
      controller.setAnchorObserver(self)
      phase = .recording
    } catch let failure as SessionRecorder.StartFailure {
      phase = .failed(Self.describe(failure))
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  private static func describe(_ failure: SessionRecorder.StartFailure) -> String {
    switch failure {
    case .unhealthy(let reason): return reason
    case .badNames: return "That level or room name has no usable slug. Try plain letters."
    case .noPhases: return "Pick at least one trade. The format has no session without one."
    case .io(let error): return "Could not create the session folder: \(error.localizedDescription)"
    }
  }

  // MARK: - During

  func takeStill() {
    guard phase == .recording, let stillCapture, stillCapture.isReady else { return }
    let index = recorder.takeStillIndex()
    stillCapture.capture(stillIndex: index, keyframeIndex: recorder.currentKeyframeIndex) {
      [weak self] outcome in
      // Runs on the writer queue.
      guard case .written(let bytes) = outcome else { return }
      DispatchQueue.main.async { self?.recorder.recordStillWritten(bytes: bytes) }
    }
  }

  func markLandmark(at point: CGPoint, label: String, kind: LandmarkKind) -> Bool {
    guard phase == .recording, let landmarkLogger, let arView else { return false }
    let time = controller.session.currentFrame?.timestamp ?? 0
    do {
      let position = try landmarkLogger.record(
        tapAt: point, in: arView, label: label, kind: kind, time: time)
      landmarkCount += 1
      place(landmark: position, label: label, kind: kind, in: arView)
      return true
    } catch {
      return false
    }
  }

  /// Draw a landmark where it was placed.
  ///
  /// Without this a tap produced a line in a file and nothing else, so there was
  /// no way to tell a mark from a missed tap, no way to see which corners were
  /// already done, and no reason to believe the raycast had landed where you
  /// meant. The node lives in the session's world frame, so walking away and
  /// coming back leaves it on the same corner — ARKit holds that frame for the
  /// life of the session. It does **not** survive into the next session, which
  /// is what printed markers are for (ADR-0006).
  private func place(landmark: Vector3, label: String, kind: LandmarkKind, in view: ARSCNView) {
    let dot = SCNSphere(radius: 0.035)
    dot.firstMaterial?.diffuse.contents = Self.colour(for: kind)
    // Unlit, so a mark in an unlit basement reads the same as one in sunlight.
    dot.firstMaterial?.lightingModel = .constant
    let node = SCNNode(geometry: dot)
    node.position = SCNVector3(Float(landmark.x), Float(landmark.y), Float(landmark.z))

    let text = SCNText(string: label, extrusionDepth: 0)
    text.font = .systemFont(ofSize: 2)
    text.flatness = 0.2
    text.firstMaterial?.diffuse.contents = Self.colour(for: kind)
    text.firstMaterial?.lightingModel = .constant
    let textNode = SCNNode(geometry: text)
    textNode.scale = SCNVector3(0.012, 0.012, 0.012)
    textNode.position = SCNVector3(0, 0.06, 0)
    // Billboard, so the label is readable from wherever you walk back to.
    textNode.constraints = [SCNBillboardConstraint()]
    node.addChildNode(textNode)

    view.scene.rootNode.addChildNode(node)
    placedLandmarks.append(node)
  }

  private static func colour(for kind: LandmarkKind) -> UIColor {
    switch kind {
    case .corner: return UIColor(red: 0.35, green: 0.64, blue: 0.91, alpha: 1)
    case .door: return UIColor(red: 0.26, green: 0.82, blue: 0.49, alpha: 1)
    case .window: return UIColor(red: 1.0, green: 0.76, blue: 0.30, alpha: 1)
    case .floor: return UIColor(red: 0.64, green: 0.71, blue: 0.77, alpha: 1)
    case .other: return UIColor(red: 0.91, green: 0.36, blue: 0.13, alpha: 1)
    }
  }

  func refreshFreeSpace() {
    let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityKey])
    freeBytes = Int64(values?.volumeAvailableCapacity ?? 0)
  }

  // MARK: - Anchors

  /// Log the observation, then draw it.
  ///
  /// The coordinator sits in front of `MarkerLogger` rather than beside it so a
  /// sighting reaches the file and the screen from one place. ARKit delivers
  /// these on the main queue — `ARSessionController` leaves `delegateQueue`
  /// nil — so touching SceneKit here is safe.
  func session(didObserve anchors: [ARAnchor], time: Double) {
    markerLogger?.session(didObserve: anchors, time: time)
    guard let arView else { return }

    for case let image as ARImageAnchor in anchors {
      guard let name = image.referenceImage.name else { continue }
      let node: SCNNode
      if let existing = markerNodes[image.identifier] {
        node = existing
      } else {
        node = Self.makeMarkerNode(
          name: name, width: CGFloat(image.referenceImage.physicalSize.width))
        markerNodes[image.identifier] = node
        arView.scene.rootNode.addChildNode(node)
      }
      node.simdTransform = image.transform
      // A marker out of view stops being tracked; hiding rather than removing
      // keeps its identity, so walking back does not create a second node.
      node.isHidden = !image.isTracked
    }
  }

  private static func makeMarkerNode(name: String, width: CGFloat) -> SCNNode {
    let node = SCNNode()

    let plane = SCNPlane(width: width, height: width)
    plane.firstMaterial?.diffuse.contents = UIColor(
      red: 0.26, green: 0.82, blue: 0.49, alpha: 0.28)
    plane.firstMaterial?.lightingModel = .constant
    plane.firstMaterial?.isDoubleSided = true
    let face = SCNNode(geometry: plane)
    // An image anchor's plane lies in its local X-Z, with +Y the normal; an
    // SCNPlane is built in X-Y, so it needs turning to sit on the marker
    // instead of standing upright through it.
    face.eulerAngles.x = -.pi / 2
    node.addChildNode(face)

    let text = SCNText(string: name, extrusionDepth: 0)
    text.font = .systemFont(ofSize: 2, weight: .bold)
    text.flatness = 0.2
    text.firstMaterial?.diffuse.contents = UIColor(
      red: 0.26, green: 0.82, blue: 0.49, alpha: 1)
    text.firstMaterial?.lightingModel = .constant
    let label = SCNNode(geometry: text)
    label.scale = SCNVector3(0.015, 0.015, 0.015)
    label.position = SCNVector3(0, Float(width) * 0.6, 0)
    label.constraints = [SCNBillboardConstraint()]
    node.addChildNode(label)

    return node
  }

  // MARK: - Stop

  /// Stop, in an order that matters.
  ///
  /// Observers are detached first so no frame or anchor arrives mid-teardown.
  /// The JSONL writers are closed before `stop`, because `stop` rewrites the
  /// manifest with the final statistics and the two files should be on disk and
  /// synchronised by the time it claims they are. The mesh is exported inside
  /// `stop`, which holds the session open until it is done.
  func stop(reason: String? = nil) {
    guard phase == .recording else { return }
    phase = .finishing(reason ?? "Writing frames, exporting mesh. Keep the app open.")

    controller.setRecorder(nil)
    controller.setAnchorObserver(nil)

    let anchors = controller.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
    let seen = markerLogger?.seen.sorted() ?? []
    markerNodes.values.forEach { $0.removeFromParentNode() }
    markerNodes = [:]

    try? markersWriter?.close()
    try? landmarksWriter?.close()
    markersWriter = nil
    landmarksWriter = nil

    var mesh: MeshExporter.Summary?
    let elapsed = recorder.elapsed
    // Read before `stop`, which clears it.
    let sessionID = recorder.sessionID?.stringValue ?? "unknown"

    do {
      let layout = try recorder.stop { layout in
        mesh = try? MeshExporter.export(anchors: anchors, to: layout)
      }
      guard let layout else {
        phase = .failed("The session stopped without a folder to show.")
        return
      }
      phase = .review(
        SessionSummary(
          sessionID: sessionID,
          root: layout.root,
          stats: recorder.stats,
          duration: elapsed,
          level: level.name,
          room: room.name,
          phases: phases,
          markersSeen: seen,
          mesh: mesh,
          stoppedBecause: reason))
    } catch {
      phase = .failed("Could not finish the session: \(error.localizedDescription)")
    }

    controller.pause()
    stillCapture = nil
    markerLogger = nil
    landmarkLogger = nil
  }

  func backToSetup() {
    // Deliberately does not restart the session. There is no AR view on the
    // setup screen, and a running session with nothing attached burns battery
    // and heats the phone for no picture. `attach` starts it when a view exists.
    phase = .setup
  }
}
