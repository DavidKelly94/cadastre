import Foundation

/// The photos a session holds, read back from the files it wrote (ADR-0028).
///
/// The app is a reader of its own record as well as its writer. This is the
/// reading: keyframes and stills in time order, each carrying what the session
/// knows about it and nothing it does not. It lives in the core package so it
/// runs on Linux and never touches ARKit (rule 3 of `AGENTS.md`), and so the
/// label a photo carries into the camera roll is tested rather than hoped.
public struct SessionPhotos: Equatable, Sendable {

  public enum Kind: String, Equatable, Sendable {
    case keyframe
    case still
  }

  /// One image the session holds, and what is known about it.
  public struct Photo: Equatable, Identifiable, Sendable {
    public var kind: Kind
    /// The keyframe index `i`, or the still index `s`.
    public var number: Int
    /// Seconds since session start.
    public var time: Double
    public var pose: Transform
    public var width: Int
    public var height: Int
    /// Session-relative, as the JSONL records it: `rgb/000123.jpg`.
    public var path: String
    /// Landmarks tapped while this keyframe was the current one, in tap order.
    /// Always empty for a still; `landmarks.jsonl` records the keyframe index.
    public var landmarkLabels: [String]

    public var id: String { "\(kind.rawValue)-\(number)" }

    public init(
      kind: Kind, number: Int, time: Double, pose: Transform, width: Int, height: Int,
      path: String, landmarkLabels: [String] = []
    ) {
      self.kind = kind
      self.number = number
      self.time = time
      self.pose = pose
      self.width = width
      self.height = height
      self.path = path
      self.landmarkLabels = landmarkLabels
    }
  }

  /// Every photo, in time order; a still that shares a keyframe's time follows it.
  public var photos: [Photo]

  public init(photos: [Photo]) {
    self.photos = photos
  }

  public var keyframeCount: Int { photos.filter { $0.kind == .keyframe }.count }
  public var stillCount: Int { photos.filter { $0.kind == .still }.count }

  /// Read a session's keyframes, stills and landmarks from its JSONL files.
  ///
  /// A line that does not decode is skipped rather than failing the read: a
  /// session that died mid-write leaves a truncated last line, and the eight
  /// hundred good frames before it are the whole point.
  public static func read(at layout: SessionLayout) -> SessionPhotos {
    let frames = JSONLReader.records(FrameRecord.self, in: layout.frames)
    let stills = JSONLReader.records(StillRecord.self, in: layout.stills)
    let landmarks = JSONLReader.records(LandmarkRecord.self, in: layout.landmarks)

    var tapped: [Int: [String]] = [:]
    for landmark in landmarks {
      tapped[landmark.index, default: []].append(landmark.label)
    }

    var photos: [Photo] = frames.map { frame in
      Photo(
        kind: .keyframe, number: frame.index, time: frame.time,
        pose: frame.poseWorldFromCamera, width: frame.width, height: frame.height,
        path: frame.rgb, landmarkLabels: tapped[frame.index] ?? [])
    }
    photos += stills.map { still in
      Photo(
        kind: .still, number: still.stillIndex, time: still.time,
        pose: still.poseWorldFromCamera, width: still.width, height: still.height,
        path: still.path)
    }
    photos.sort { lhs, rhs in
      if lhs.time != rhs.time { return lhs.time < rhs.time }
      if lhs.kind != rhs.kind { return lhs.kind == .keyframe }
      return lhs.number < rhs.number
    }
    return SessionPhotos(photos: photos)
  }

  /// Every `stride`-th keyframe and every still, in time order. Stride 1 is everything.
  public func sampled(stride: Int) -> [Photo] {
    let step = max(1, stride)
    return photos.filter { $0.kind == .still || $0.number % step == 0 }
  }
}

/// Reads the complete lines of a JSONL file as records.
public enum JSONLReader {
  /// Every line that decodes as `T`. A file not ending in a newline has a
  /// partial last line, which is left out rather than tried.
  public static func records<T: Decodable>(_ type: T.Type, in url: URL) -> [T] {
    guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
      return []
    }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    if !text.hasSuffix("\n"), !lines.isEmpty {
      lines.removeLast()
    }
    let decoder = JSONDecoder()
    var out: [T] = []
    for line in lines {
      guard let data = line.data(using: .utf8), let record = try? decoder.decode(T.self, from: data)
      else { continue }
      out.append(record)
    }
    return out
  }
}

/// What a photo says about itself, built from the session and nothing else.
///
/// This is the text that travels with a photo into the camera roll, so it is
/// deliberately only what the manifest and the JSONL files state. A label is
/// as true as the manifest it came from: a session recorded under the wrong
/// room carries that room into every saved photo.
public struct PhotoLabel: Equatable, Sendable {
  /// `Our House · Main Floor · Kitchen · electrical, plumbing`
  public var headline: String
  /// `keyframe 123 · 12.3 s`, or `still 3 · 40.0 s`
  public var frame: String
  /// `corner NE tapped here`, or nil when nothing was tapped at this keyframe.
  public var landmarks: String?
  /// When the photo was taken: the session's start plus its `t`, or nil when
  /// the manifest's timestamp does not parse.
  public var takenAt: Date?
  /// For the keywords field: enough to trace the photo back to its frame.
  public var keywords: [String]

  public init(
    headline: String, frame: String, landmarks: String?, takenAt: Date?, keywords: [String]
  ) {
    self.headline = headline
    self.frame = frame
    self.landmarks = landmarks
    self.takenAt = takenAt
    self.keywords = keywords
  }

  /// The label as text, one item per line.
  public var caption: String {
    var lines = [headline, frame]
    if let landmarks { lines.append(landmarks) }
    return lines.joined(separator: "\n")
  }

  public static func make(for photo: SessionPhotos.Photo, manifest: Manifest?, sessionID: String)
    -> PhotoLabel
  {
    let headline: String
    if let manifest {
      headline = [
        manifest.project.name, manifest.level.name, manifest.room.name,
        manifest.phases.map(\.rawValue).joined(separator: ", "),
      ].joined(separator: " · ")
    } else {
      headline = sessionID
    }

    let which = photo.kind == .still ? "still \(photo.number)" : "keyframe \(photo.number)"
    let frame = which + " · " + String(format: "%.1f", photo.time) + " s"

    let landmarks: String? =
      photo.landmarkLabels.isEmpty
      ? nil : photo.landmarkLabels.joined(separator: ", ") + " tapped here"

    let takenAt = manifest.flatMap { Self.date(fromISO8601: $0.capture.startedAt) }
      .map { $0.addingTimeInterval(photo.time) }

    var keywords = ["VividHome", sessionID, which]
    if let manifest {
      keywords.append(manifest.project.slug)
      keywords.append(manifest.level.slug)
      keywords.append(manifest.room.slug)
    }

    return PhotoLabel(
      headline: headline, frame: frame, landmarks: landmarks, takenAt: takenAt, keywords: keywords)
  }

  /// The manifest's `started_at` (ISO 8601 with offset), with or without
  /// fractional seconds, or nil.
  public static func date(fromISO8601 text: String) -> Date? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = parser.date(from: text) { return date }
    parser.formatOptions = [.withInternetDateTime]
    return parser.date(from: text)
  }
}

/// Which way to turn a stored image so it shows upright, read from its pose.
///
/// Stored images are landscape sensor orientation whatever way the phone was
/// held (`docs/session-format.md` §3): image right is camera `+x` and image up
/// is camera `+y`. Where the world's up lands in the camera frame therefore says
/// which edge of the stored image was really the top. The file is never
/// rotated; this is for display and for the EXIF orientation tag on a copy.
///
/// The raw values are the EXIF orientation values, so the tag is the case.
public enum DisplayOrientation: Int, Equatable, Sendable {
  /// The stored image is already upright.
  case upright = 1
  /// Turn it a half turn.
  case rotate180 = 3
  /// The stored top row belongs on the right: turn it 90° clockwise.
  case rotate90Clockwise = 6
  /// The stored top row belongs on the left: turn it 90° counterclockwise.
  case rotate90Counterclockwise = 8

  public var exifOrientation: Int { rawValue }

  /// Degrees to turn the stored pixels clockwise for display.
  public var degreesClockwise: Int {
    switch self {
    case .upright: return 0
    case .rotate180: return 180
    case .rotate90Clockwise: return 90
    case .rotate90Counterclockwise: return 270
    }
  }

  /// From a camera-to-world pose. A camera pointed at the floor or the ceiling
  /// has no meaningful roll and is shown as stored.
  public static func from(pose: Transform) -> DisplayOrientation {
    // World up in camera coordinates is the second row of the rotation block:
    // up_c = Rᵀ · (0, 1, 0).
    let x = pose[1, 0]
    let y = pose[1, 1]
    let z = pose[1, 2]
    if abs(z) >= abs(x), abs(z) >= abs(y) {
      return .upright
    }
    if abs(y) >= abs(x) {
      return y >= 0 ? .upright : .rotate180
    }
    // Up lies along the stored image's horizontal axis: on its right when x > 0,
    // on its left when x < 0. The edge that is really the top has to be turned
    // to the top.
    return x > 0 ? .rotate90Counterclockwise : .rotate90Clockwise
  }
}
