import Foundation

// The Codable shapes of every file in a session, matching docs/session-format.md
// exactly. These are the contract between the app and the pipeline, so the field
// names below are mapped to the documented JSON keys rather than renamed, and the
// golden-string tests pin the encoded output.
//
// Unknown fields decode away silently, which is what §12 requires of a reader.

public enum SessionStatus: String, Codable, Sendable {
  case incomplete
  case complete
  case repaired
}

public enum TrackingState: String, Codable, Sendable {
  case normal
  case limited
  case notAvailable
}

public enum TrackingReason: String, Codable, Sendable {
  case none
  case initializing
  case excessiveMotion
  case insufficientFeatures
  case relocalizing
}

public enum ThermalState: String, Codable, Sendable {
  case nominal
  case fair
  case serious
  case critical
}

public enum LandmarkKind: String, Codable, Sendable {
  case corner
  case door
  case window
  case floor
  case other
}

/// A slug and the name it was derived from, as used for `project` and `room`.
public struct SlugRef: Codable, Equatable, Sendable {
  public var slug: String
  public var name: String

  public init(slug: String, name: String) {
    self.slug = slug
    self.name = name
  }
}

/// A level: a slug, a name and the storey index used to order levels.
public struct LevelRef: Codable, Equatable, Sendable {
  public var slug: String
  public var name: String
  public var index: Int

  public init(slug: String, name: String, index: Int) {
    self.slug = slug
    self.name = name
    self.index = index
  }
}

public struct DeviceInfo: Codable, Equatable, Sendable {
  public var model: String
  public var iosVersion: String
  public var appVersion: String
  public var appBuild: String

  public init(model: String, iosVersion: String, appVersion: String, appBuild: String) {
    self.model = model
    self.iosVersion = iosVersion
    self.appVersion = appVersion
    self.appBuild = appBuild
  }

  enum CodingKeys: String, CodingKey {
    case model
    case iosVersion = "ios_version"
    case appVersion = "app_version"
    case appBuild = "app_build"
  }
}

public struct VideoFormat: Codable, Equatable, Sendable {
  public var w: Int
  public var h: Int
  public var fps: Int

  public init(w: Int, h: Int, fps: Int) {
    self.w = w
    self.h = h
    self.fps = fps
  }
}

/// The thresholds the app applied when gating keyframes, recorded so the pipeline
/// can tell a sparse session from a slow walk.
public struct KeyframePolicySettings: Codable, Equatable, Sendable {
  public var minDt: Double
  public var minTranslation: Double
  public var minRotationDegrees: Double

  public init(minDt: Double, minTranslation: Double, minRotationDegrees: Double) {
    self.minDt = minDt
    self.minTranslation = minTranslation
    self.minRotationDegrees = minRotationDegrees
  }

  enum CodingKeys: String, CodingKey {
    case minDt = "min_dt_s"
    case minTranslation = "min_translation_m"
    case minRotationDegrees = "min_rotation_deg"
  }
}

public struct DepthFormat: Codable, Equatable, Sendable {
  public var w: Int
  public var h: Int
  public var dtype: String
  public var units: String

  public init(w: Int, h: Int, dtype: String = "float32", units: String = "m") {
    self.w = w
    self.h = h
    self.dtype = dtype
    self.units = units
  }
}

public struct CaptureInfo: Codable, Equatable, Sendable {
  /// ISO 8601 with offset. Wall-clock times appear only in the manifest.
  public var startedAt: String
  /// Absent while the session is still recording.
  public var endedAt: String?
  public var duration: Double
  public var videoFormat: VideoFormat
  public var keyframePolicy: KeyframePolicySettings
  public var depth: DepthFormat
  public var jpegQuality: Double
  public var markerPhysicalWidth: Double
  public var sceneReconstruction: String

  public init(
    startedAt: String,
    endedAt: String? = nil,
    duration: Double,
    videoFormat: VideoFormat,
    keyframePolicy: KeyframePolicySettings,
    depth: DepthFormat,
    jpegQuality: Double,
    markerPhysicalWidth: Double,
    sceneReconstruction: String
  ) {
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.duration = duration
    self.videoFormat = videoFormat
    self.keyframePolicy = keyframePolicy
    self.depth = depth
    self.jpegQuality = jpegQuality
    self.markerPhysicalWidth = markerPhysicalWidth
    self.sceneReconstruction = sceneReconstruction
  }

  enum CodingKeys: String, CodingKey {
    case startedAt = "started_at"
    case endedAt = "ended_at"
    case duration = "duration_s"
    case videoFormat = "video_format"
    case keyframePolicy = "keyframe_policy"
    case depth
    case jpegQuality = "jpeg_quality"
    case markerPhysicalWidth = "marker_physical_width_m"
    case sceneReconstruction = "scene_reconstruction"
  }
}

public struct CoordinateFrame: Codable, Equatable, Sendable {
  public var name: String
  public var up: String
  public var units: String
  public var matrixOrder: String

  /// The only frame the MVP writes, spelled out so a reader can check rather than assume.
  public static let arkitSession = CoordinateFrame(
    name: "arkit-session", up: "+y", units: "m", matrixOrder: "column-major")

  public init(name: String, up: String, units: String, matrixOrder: String) {
    self.name = name
    self.up = up
    self.units = units
    self.matrixOrder = matrixOrder
  }

  enum CodingKeys: String, CodingKey {
    case name
    case up
    case units
    case matrixOrder = "matrix_order"
  }
}

public struct SessionStats: Codable, Equatable, Sendable {
  public var keyframes: Int
  public var dropped: Int
  public var stills: Int
  public var markerObservations: Int
  public var landmarks: Int
  public var trackingLimited: Double
  public var thermalMax: ThermalState
  public var bytes: Int

  public init(
    keyframes: Int = 0,
    dropped: Int = 0,
    stills: Int = 0,
    markerObservations: Int = 0,
    landmarks: Int = 0,
    trackingLimited: Double = 0,
    thermalMax: ThermalState = .nominal,
    bytes: Int = 0
  ) {
    self.keyframes = keyframes
    self.dropped = dropped
    self.stills = stills
    self.markerObservations = markerObservations
    self.landmarks = landmarks
    self.trackingLimited = trackingLimited
    self.thermalMax = thermalMax
    self.bytes = bytes
  }

  enum CodingKeys: String, CodingKey {
    case keyframes
    case dropped
    case stills
    case markerObservations = "marker_observations"
    case landmarks
    case trackingLimited = "tracking_limited_s"
    case thermalMax = "thermal_max"
    case bytes
  }
}

/// `manifest.json`: written at start and rewritten at stop.
public struct Manifest: Codable, Equatable, Sendable {
  public var formatVersion: Int
  public var sessionID: String
  public var status: SessionStatus
  public var project: SlugRef
  public var level: LevelRef
  public var room: SlugRef
  public var phase: CapturePhase
  public var notes: String?
  public var expectedMarkers: [String]
  public var device: DeviceInfo
  public var capture: CaptureInfo
  public var coordinateFrame: CoordinateFrame
  public var stats: SessionStats

  public init(
    formatVersion: Int = CadastreCore.sessionFormatVersion,
    sessionID: String,
    status: SessionStatus,
    project: SlugRef,
    level: LevelRef,
    room: SlugRef,
    phase: CapturePhase,
    notes: String? = nil,
    expectedMarkers: [String] = [],
    device: DeviceInfo,
    capture: CaptureInfo,
    coordinateFrame: CoordinateFrame = .arkitSession,
    stats: SessionStats = SessionStats()
  ) {
    self.formatVersion = formatVersion
    self.sessionID = sessionID
    self.status = status
    self.project = project
    self.level = level
    self.room = room
    self.phase = phase
    self.notes = notes
    self.expectedMarkers = expectedMarkers
    self.device = device
    self.capture = capture
    self.coordinateFrame = coordinateFrame
    self.stats = stats
  }

  enum CodingKeys: String, CodingKey {
    case formatVersion = "format_version"
    case sessionID = "session_id"
    case status
    case project
    case level
    case room
    case phase
    case notes
    case expectedMarkers = "expected_markers"
    case device
    case capture
    case coordinateFrame = "coordinate_frame"
    case stats
  }
}

/// One line of `frames.jsonl`.
public struct FrameRecord: Codable, Equatable, Sendable {
  public var index: Int
  public var time: Double
  /// Camera-to-world: `p_w = T_wc · p_c`.
  public var poseWorldFromCamera: Transform
  public var intrinsics: Intrinsics
  public var width: Int
  public var height: Int
  public var depthWidth: Int
  public var depthHeight: Int
  public var exposureDuration: Double
  public var exposureOffset: Double
  public var tracking: TrackingState
  public var reason: TrackingReason
  public var thermal: ThermalState
  public var rgb: String
  public var depth: String
  public var conf: String

  public init(
    index: Int,
    time: Double,
    poseWorldFromCamera: Transform,
    intrinsics: Intrinsics,
    width: Int,
    height: Int,
    depthWidth: Int,
    depthHeight: Int,
    exposureDuration: Double,
    exposureOffset: Double,
    tracking: TrackingState,
    reason: TrackingReason,
    thermal: ThermalState,
    rgb: String,
    depth: String,
    conf: String
  ) {
    self.index = index
    self.time = time
    self.poseWorldFromCamera = poseWorldFromCamera
    self.intrinsics = intrinsics
    self.width = width
    self.height = height
    self.depthWidth = depthWidth
    self.depthHeight = depthHeight
    self.exposureDuration = exposureDuration
    self.exposureOffset = exposureOffset
    self.tracking = tracking
    self.reason = reason
    self.thermal = thermal
    self.rgb = rgb
    self.depth = depth
    self.conf = conf
  }

  /// The paths the app writes for keyframe `index`, zero-padded to 6 digits.
  public static func paths(forKeyframe index: Int) -> (rgb: String, depth: String, conf: String) {
    let stem = String(format: "%06d", index)
    return ("rgb/\(stem).jpg", "depth/\(stem).f32", "conf/\(stem).u8")
  }

  /// Depth intrinsics for this frame, scaled from the colour intrinsics.
  public var depthIntrinsics: Intrinsics {
    intrinsics.scaled(
      fromWidth: width, height: height, toWidth: depthWidth, height: depthHeight)
  }

  enum CodingKeys: String, CodingKey {
    case index = "i"
    case time = "t"
    case poseWorldFromCamera = "T_wc"
    case intrinsics = "K"
    case width = "w"
    case height = "h"
    case depthWidth = "dw"
    case depthHeight = "dh"
    case exposureDuration = "exp_s"
    case exposureOffset = "exp_off"
    case tracking
    case reason
    case thermal
    case rgb
    case depth
    case conf
  }
}

/// One line of `stills.jsonl`. No depth: stills have no depth file.
public struct StillRecord: Codable, Equatable, Sendable {
  public var stillIndex: Int
  /// Index of the most recent keyframe when the still was taken, or -1 if none.
  public var index: Int
  public var time: Double
  public var poseWorldFromCamera: Transform
  /// Intrinsics for the still's own resolution, not the keyframe's.
  public var intrinsics: Intrinsics
  public var width: Int
  public var height: Int
  public var exposureDuration: Double
  public var exposureOffset: Double
  public var tracking: TrackingState
  public var reason: TrackingReason
  public var thermal: ThermalState
  public var path: String

  public init(
    stillIndex: Int,
    index: Int,
    time: Double,
    poseWorldFromCamera: Transform,
    intrinsics: Intrinsics,
    width: Int,
    height: Int,
    exposureDuration: Double,
    exposureOffset: Double,
    tracking: TrackingState,
    reason: TrackingReason,
    thermal: ThermalState,
    path: String
  ) {
    self.stillIndex = stillIndex
    self.index = index
    self.time = time
    self.poseWorldFromCamera = poseWorldFromCamera
    self.intrinsics = intrinsics
    self.width = width
    self.height = height
    self.exposureDuration = exposureDuration
    self.exposureOffset = exposureOffset
    self.tracking = tracking
    self.reason = reason
    self.thermal = thermal
    self.path = path
  }

  /// The path the app writes for still `index`, zero-padded to 3 digits.
  public static func path(forStill index: Int) -> String {
    "stills/" + String(format: "%03d", index) + ".jpg"
  }

  enum CodingKeys: String, CodingKey {
    case stillIndex = "s"
    case index = "i"
    case time = "t"
    case poseWorldFromCamera = "T_wc"
    case intrinsics = "K"
    case width = "w"
    case height = "h"
    case exposureDuration = "exp_s"
    case exposureOffset = "exp_off"
    case tracking
    case reason
    case thermal
    case path
  }
}

/// One line of `markers.jsonl`, from an `ARImageAnchor` add or update.
public struct MarkerObservation: Codable, Equatable, Sendable {
  public var time: Double
  public var index: Int
  public var markerID: String
  /// The ARKit **image-anchor** transform, not the canonical marker frame. The
  /// pipeline applies `R_am` to convert; see `docs/session-format.md` §8.
  public var poseWorldFromAnchor: Transform
  public var tracked: Bool
  public var physicalWidth: Double

  public init(
    time: Double,
    index: Int,
    markerID: String,
    poseWorldFromAnchor: Transform,
    tracked: Bool,
    physicalWidth: Double
  ) {
    self.time = time
    self.index = index
    self.markerID = markerID
    self.poseWorldFromAnchor = poseWorldFromAnchor
    self.tracked = tracked
    self.physicalWidth = physicalWidth
  }

  enum CodingKeys: String, CodingKey {
    case time = "t"
    case index = "i"
    case markerID = "marker_id"
    case poseWorldFromAnchor = "T_wa"
    case tracked
    case physicalWidth = "physical_width_m"
  }
}

/// One line of `landmarks.jsonl`, from a tap resolved by raycast.
public struct LandmarkRecord: Codable, Equatable, Sendable {
  public var time: Double
  public var index: Int
  public var label: String
  public var kind: LandmarkKind
  public var position: Vector3
  public var method: String

  public init(
    time: Double, index: Int, label: String, kind: LandmarkKind, position: Vector3, method: String
  ) {
    self.time = time
    self.index = index
    self.label = label
    self.kind = kind
    self.position = position
    self.method = method
  }

  enum CodingKeys: String, CodingKey {
    case time = "t"
    case index = "i"
    case label
    case kind
    case position = "p_w"
    case method
  }
}

/// Printed marker identifiers, `CD-000` to `CD-059`.
public enum MarkerID {
  /// The prefix chosen in ADR-0019.
  public static let prefix = "CD-"

  /// Formats a marker id from a tag number.
  public static func string(for number: Int) -> String {
    prefix + String(format: "%03d", number)
  }

  /// Validation rule 8: marker ids match `CD-\d{3}`.
  public static func isValid(_ value: String) -> Bool {
    guard value.count == 6, value.hasPrefix(prefix) else { return false }
    return value.dropFirst(prefix.count).allSatisfy { $0.isASCII && $0.isNumber }
  }

  /// The tag number in a marker id, or nil if it is not a valid id.
  public static func number(in value: String) -> Int? {
    guard isValid(value) else { return nil }
    return Int(value.dropFirst(prefix.count))
  }
}
