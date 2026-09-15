import Foundation

/// The manifest's three states, and the arithmetic behind the statistics.
///
/// A session's manifest is written twice: once at the start, when almost nothing
/// is known, and once at the stop, when everything is. If the app dies in
/// between, the file left on disk says `incomplete`, and the pipeline treats that
/// as an error rather than guessing. Repair is the third state, and it is
/// deliberately distinguishable from a clean stop.
extension Manifest {
  /// The manifest written when recording starts.
  ///
  /// `duration_s` is zero and the statistics are empty because nothing has
  /// happened yet. Writing it immediately, rather than at the end, is what makes
  /// an interrupted session recoverable at all.
  public static func starting(
    sessionID: SessionID,
    project: SlugRef,
    level: LevelRef,
    room: SlugRef,
    phases: [CapturePhase],
    notes: String? = nil,
    expectedMarkers: [String] = [],
    device: DeviceInfo,
    startedAt: String,
    videoFormat: VideoFormat,
    keyframePolicy: KeyframePolicySettings,
    depth: DepthFormat,
    jpegQuality: Double,
    markerPhysicalWidth: Double,
    sceneReconstruction: String
  ) -> Manifest {
    Manifest(
      sessionID: sessionID.stringValue,
      status: .incomplete,
      project: project,
      level: level,
      room: room,
      phases: phases,
      notes: notes,
      expectedMarkers: expectedMarkers,
      device: device,
      capture: CaptureInfo(
        startedAt: startedAt,
        endedAt: nil,
        duration: 0,
        videoFormat: videoFormat,
        keyframePolicy: keyframePolicy,
        depth: depth,
        jpegQuality: jpegQuality,
        markerPhysicalWidth: markerPhysicalWidth,
        sceneReconstruction: sceneReconstruction))
  }

  /// The manifest rewritten after a clean stop.
  public func finalized(endedAt: String, duration: Double, stats: SessionStats) -> Manifest {
    var updated = self
    updated.status = .complete
    updated.capture.endedAt = endedAt
    updated.capture.duration = duration
    updated.stats = stats
    return updated
  }

  /// The manifest rewritten after a crash, from what is actually on disk.
  ///
  /// Kept distinct from `finalized` so a reader can tell a session that stopped
  /// cleanly from one that was reconstructed. The pipeline warns on this rather
  /// than failing, because the data is usually fine — it is the bookkeeping that
  /// was lost.
  public func repaired(endedAt: String?, duration: Double, stats: SessionStats) -> Manifest {
    var updated = self
    updated.status = .repaired
    updated.capture.endedAt = endedAt
    updated.capture.duration = duration
    updated.stats = stats
    return updated
  }
}

extension SessionStats {
  /// Record a kept keyframe and the bytes it wrote.
  public mutating func recordKeyframe(bytes: Int) {
    keyframes += 1
    self.bytes += bytes
  }

  /// Record a keyframe the writer refused.
  public mutating func recordDrop() {
    dropped += 1
  }

  public mutating func recordStill(bytes: Int) {
    stills += 1
    self.bytes += bytes
  }

  public mutating func recordMarkerObservation() {
    markerObservations += 1
  }

  public mutating func recordLandmark() {
    landmarks += 1
  }

  /// Keep the worst thermal state the session reached.
  public mutating func recordThermal(_ state: ThermalState) {
    if state.severity > thermalMax.severity {
      thermalMax = state
    }
  }

  /// The fraction of offered keyframes that were dropped, for the HUD.
  public var dropRate: Double {
    let offered = keyframes + dropped
    return offered == 0 ? 0 : Double(dropped) / Double(offered)
  }
}

extension ThermalState {
  /// Ordering for "worst so far". The raw values are names, not a scale.
  public var severity: Int {
    switch self {
    case .nominal: 0
    case .fair: 1
    case .serious: 2
    case .critical: 3
    }
  }
}

/// Accumulates time spent in a tracking state other than normal.
///
/// ARKit reports tracking per frame, so the time limited is the sum of the gaps
/// between frames that were limited — not a count of them. A count would say
/// nothing about whether the problem lasted a moment or a minute.
public struct TrackingClock: Sendable {
  private var lastTime: Double?
  private var lastWasLimited = false

  /// Seconds spent in a state other than `.normal`.
  public private(set) var limitedSeconds: Double = 0

  public init() {}

  public mutating func record(time: Double, tracking: TrackingState) {
    if let previous = lastTime, lastWasLimited, time > previous {
      limitedSeconds += time - previous
    }
    lastTime = time
    lastWasLimited = tracking != .normal
  }
}
