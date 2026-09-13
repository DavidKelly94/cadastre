import ARKit
import Foundation
import UIKit

import CadastreCore

/// Turning a running AR session into a session folder on disk.
///
/// The recorder is the one place that knows a capture is in progress. It owns the
/// counters, the manifest, and the decision to keep a frame — though it makes
/// none of those decisions itself: `KeyframePolicy`, `HealthPolicy` and
/// `SessionStats` live in CadastreCore where Linux CI covers them (ADR-0016).
/// What is left here is the part that must touch ARKit and CoreVideo.
///
/// The delegate calls in at thirty frames a second, so the per-frame path is
/// written to be short: decide, copy the two depth buffers, hand the rest to the
/// writer, return. Everything slow happens on the writer's queue.
final class SessionRecorder: NSObject, ObservableObject, ARFrameObserver {

  enum State: Equatable {
    case idle
    case recording
    case finishing
  }

  /// Why a recording could not start. Distinct from `HealthVerdict`, which is
  /// about a recording already under way.
  enum StartFailure: Error {
    case unhealthy(String)
    case badNames
    /// No trade was selected. The format requires at least one, because a
    /// session with no phase cannot be placed in the record (ADR-0022).
    case noPhases
    case io(Error)
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var stats = SessionStats()
  @Published private(set) var elapsed: Double = 0
  /// Set when the health policy wants the owner told, or the recording stopped.
  @Published private(set) var verdict: HealthVerdict = .ok

  private(set) var layout: SessionLayout?
  private(set) var sessionID: SessionID?

  private var manifest: Manifest?
  private var writer: FrameWriter?
  private var policy = KeyframePolicy()
  private var clock = TrackingClock()
  private var startedAt: Date?
  private var firstFrameTime: Double?
  private var lastFrameTime: Double?
  private var nextKeyframeIndex = 0
  private var nextStillIndex = 0
  /// Frame time of the last free-space check. Stat-ing the volume is cheap but
  /// not free, and thirty times a second buys nothing: the threshold it guards is
  /// half a gigabyte, which no single second of recording can cross.
  private var lastHealthCheck: Double = -.infinity

  /// Guards the counters, which the writer's completion handlers touch from the
  /// writer queue while the delegate touches them from the main thread.
  private let statsLock = NSLock()

  // MARK: - Starting

  /// Create the session folder, write an incomplete manifest, and start counting.
  ///
  /// The manifest is written as `incomplete` before a single frame lands. That is
  /// what makes an interrupted capture recoverable: `SessionStore.repairIfNeeded`
  /// can tell "the app died" from "the app never ran" only because the file is
  /// there from the first moment.
  func start(
    documents: URL,
    project: SlugRef,
    level: LevelRef,
    room: SlugRef,
    phases: [CapturePhase],
    notes: String?,
    expectedMarkers: [String],
    videoFormat: VideoFormat,
    policySettings: KeyframePolicySettings = KeyframePolicy.documentedDefault,
    jpegQuality: Double = AppConfig.defaultJPEGQuality
  ) throws {
    guard state == .idle else { return }

    let free = Self.freeBytes(at: documents)
    if let refusal = HealthPolicy.startRefusal(freeBytes: free) {
      throw StartFailure.unhealthy(refusal)
    }

    guard !phases.isEmpty else { throw StartFailure.noPhases }

    guard
      let id = SessionID(
        date: Date(), levelName: level.name, roomName: room.name, id6: SessionID.makeID6())
    else {
      throw StartFailure.badNames
    }

    let layout = SessionLayout(documents: documents, project: project.slug, sessionID: id)
    do {
      try layout.createDirectories()

      let started = Date()
      let manifest = Manifest.starting(
        sessionID: id,
        project: project,
        level: level,
        room: room,
        phases: phases,
        notes: notes,
        expectedMarkers: expectedMarkers,
        device: Self.device(),
        startedAt: Self.iso8601(started),
        videoFormat: videoFormat,
        keyframePolicy: policySettings,
        depth: DepthFormat(w: AppConfig.depthWidth, h: AppConfig.depthHeight),
        jpegQuality: jpegQuality,
        markerPhysicalWidth: AppConfig.markerPhysicalWidth,
        sceneReconstruction: "meshWithClassification")
      try Self.write(manifest, to: layout.manifest)

      self.writer = try FrameWriter(layout: layout, quality: jpegQuality)
      self.layout = layout
      self.sessionID = id
      self.manifest = manifest
      self.startedAt = started
      self.policy = KeyframePolicy(settings: policySettings)
      self.clock = TrackingClock()
      self.stats = SessionStats()
      self.elapsed = 0
      self.verdict = .ok
      self.firstFrameTime = nil
      self.lastFrameTime = nil
      self.nextKeyframeIndex = 0
      self.nextStillIndex = 0
      self.lastHealthCheck = -.infinity
      self.state = .recording
    } catch {
      throw StartFailure.io(error)
    }
  }

  // MARK: - Per frame

  /// The hot path. Called on the main thread at the video frame rate.
  ///
  /// Order matters here. The depth and confidence buffers are copied
  /// synchronously because ARKit reuses them as soon as this returns, but the
  /// colour buffer is retained rather than copied — `CVPixelBuffer` is
  /// reference-counted and holding one is safe, where holding the `ARFrame`
  /// would stop ARKit delivering any more.
  func session(didUpdate frame: ARFrame, thermal: ThermalState) {
    let (tracking, reason) = ARKitBridge.tracking(frame.camera.trackingState)
    clock.record(time: frame.timestamp, tracking: tracking)

    if firstFrameTime == nil { firstFrameTime = frame.timestamp }
    lastFrameTime = frame.timestamp
    if let first = firstFrameTime {
      elapsed = frame.timestamp - first
    }

    guard state == .recording, let writer, let layout else { return }

    mutateStats { $0.recordThermal(thermal) }
    if frame.timestamp - lastHealthCheck >= AppConfig.healthCheckInterval {
      lastHealthCheck = frame.timestamp
      verdict = HealthPolicy.verdict(
        freeBytes: Self.freeBytes(at: layout.root), thermal: thermal)
    }

    // Only `.normal` frames are keyframes: a pose recorded while tracking is
    // limited is a pose the pipeline cannot trust, and one bad pose in a chain
    // is worse than a gap.
    guard tracking == .normal else { return }

    let pose = ARKitBridge.transform(frame.camera.transform)
    guard policy.shouldKeep(time: frame.timestamp, pose: pose) else { return }

    guard let sceneDepth = frame.sceneDepth,
      let confidenceMap = sceneDepth.confidenceMap
    else {
      return
    }

    let depth: Data
    let confidence: Data
    do {
      depth = try PixelBufferPacker.depth(sceneDepth.depthMap)
      confidence = try PixelBufferPacker.confidence(confidenceMap)
    } catch {
      mutateStats { $0.recordDrop() }
      return
    }

    let colour = frame.capturedImage
    let resolution = frame.camera.imageResolution
    let index = nextKeyframeIndex
    nextKeyframeIndex += 1

    let paths = FrameRecord.paths(forKeyframe: index)
    let record = FrameRecord(
      index: index,
      time: frame.timestamp,
      poseWorldFromCamera: pose,
      intrinsics: ARKitBridge.intrinsics(frame.camera.intrinsics),
      width: Int(resolution.width),
      height: Int(resolution.height),
      depthWidth: CVPixelBufferGetWidth(sceneDepth.depthMap),
      depthHeight: CVPixelBufferGetHeight(sceneDepth.depthMap),
      exposureDuration: frame.camera.exposureDuration,
      exposureOffset: Double(frame.camera.exposureOffset),
      tracking: tracking,
      reason: reason,
      thermal: thermal,
      rgb: paths.rgb,
      depth: paths.depth,
      conf: paths.conf)

    writer.write(record: record, colour: colour, depth: depth, confidence: confidence) {
      [weak self] outcome in
      self?.record(outcome)
    }
  }

  /// Fold a writer outcome into the statistics.
  ///
  /// A drop is not an error. It is the bounded queue refusing work the phone
  /// cannot keep up with, and the manifest carries the count so the pipeline —
  /// and the owner — can see how often it happened.
  private func record(_ outcome: FrameWriter.Outcome) {
    switch outcome {
    case .written(let bytes):
      mutateStats { $0.recordKeyframe(bytes: bytes) }
    case .dropped:
      mutateStats { $0.recordDrop() }
    case .failed:
      mutateStats { $0.recordDrop() }
    }
  }

  func recordStillWritten(bytes: Int) {
    mutateStats { $0.recordStill(bytes: bytes) }
  }

  func recordMarkerObservation() {
    mutateStats { $0.recordMarkerObservation() }
  }

  func recordLandmark() {
    mutateStats { $0.recordLandmark() }
  }

  /// The keyframe index a still or landmark should reference, or -1 before the
  /// first keyframe lands.
  var currentKeyframeIndex: Int {
    nextKeyframeIndex - 1
  }

  func takeStillIndex() -> Int {
    let index = nextStillIndex
    nextStillIndex += 1
    return index
  }

  // MARK: - Stopping

  /// Drain the writer, rewrite the manifest as complete, and go idle.
  ///
  /// The order is the point: the writer is drained first so the statistics in the
  /// manifest describe files that are on disk rather than ones still queued.
  @discardableResult
  func stop(meshExport: ((SessionLayout) -> Void)? = nil) throws -> SessionLayout? {
    guard state == .recording, let layout, let manifest, let writer else { return nil }
    state = .finishing

    meshExport?(layout)
    try writer.finish()

    let duration = (lastFrameTime ?? 0) - (firstFrameTime ?? 0)
    var final = stats
    final.trackingLimited = clock.limitedSeconds

    let completed = manifest.finalized(
      endedAt: Self.iso8601(Date()),
      duration: max(0, duration),
      stats: final)
    try Self.write(completed, to: layout.manifest)

    self.writer = nil
    self.manifest = completed
    self.stats = final
    self.state = .idle
    return layout
  }

  // MARK: - Helpers

  private func mutateStats(_ change: (inout SessionStats) -> Void) {
    statsLock.lock()
    var copy = stats
    change(&copy)
    statsLock.unlock()

    if Thread.isMainThread {
      stats = copy
    } else {
      DispatchQueue.main.async { [weak self] in self?.stats = copy }
    }
  }

  /// The manifest, pretty-printed with sorted keys.
  ///
  /// Pretty-printed because a human reads it when a capture goes wrong, and it is
  /// written twice per session rather than thirty times a second, so the bytes
  /// cost nothing. Sorted keys so two manifests diff cleanly.
  static func write(_ manifest: Manifest, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
    try encoder.encode(manifest).write(to: url, options: .atomic)
  }

  static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  static func freeBytes(at url: URL) -> Int {
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    if let capacity = values?.volumeAvailableCapacityForImportantUsage {
      return Int(capacity)
    }
    return Int.max
  }

  static func device() -> DeviceInfo {
    let bundle = Bundle.main
    return DeviceInfo(
      model: UIDevice.current.model,
      iosVersion: UIDevice.current.systemVersion,
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "unknown",
      appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
  }
}
