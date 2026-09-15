import Foundation

/// A floor plan for one level: `plans/<level>.json`, `docs/session-format.md` §13.
///
/// Project-level, not session data ([ADR-0025]). It is imported rather than
/// captured, it is edited after the fact, and it sits beside the sessions rather
/// than inside any of them — raw sessions stay immutable.
///
/// The first six fields are what `vividhome plan add` and `plan calibrate` have
/// always written; `source` and `rooms` are what the app adds. The names match
/// the pipeline exactly, because a second spelling of the same field is how two
/// sides of one contract drift apart.
public struct PlanFile: Codable, Equatable, Sendable {

  /// Level slug; must equal the file's own stem.
  public var level: String
  /// Raster filename, beside the JSON.
  public var image: String
  /// Metres per pixel, or nil when the level has not been calibrated.
  public var metresPerPixel: Double?
  /// Plan-pixel position of the house-frame origin, or nil when uncalibrated.
  public var originPx: [Double]?
  public var rotationDegrees: Double
  public var floorHeight: Double
  /// The imported original, when it was kept.
  public var source: PlanSource?
  /// Where the owner says each room is. See ``PlanRoom``.
  public var rooms: [PlanRoom]

  /// Calibration is the presence of both numbers, never a stored flag.
  ///
  /// A boolean beside them could disagree with them, and then nothing says which
  /// is right. The app never sets these: it solves nothing, so every plan it
  /// writes is uncalibrated and `vividhome plan calibrate` is what fills them in.
  public var isCalibrated: Bool { metresPerPixel != nil && originPx != nil }

  /// Half-calibrated is a defect, not a state: `house_to_plan` raises on it far
  /// from here, and a plan claiming a scale it cannot use is worse than one
  /// claiming nothing.
  public var isHalfCalibrated: Bool { (metresPerPixel == nil) != (originPx == nil) }

  public init(
    level: String,
    image: String,
    metresPerPixel: Double? = nil,
    originPx: [Double]? = nil,
    rotationDegrees: Double = 0,
    floorHeight: Double = 0,
    source: PlanSource? = nil,
    rooms: [PlanRoom] = []
  ) {
    self.level = level
    self.image = image
    self.metresPerPixel = metresPerPixel
    self.originPx = originPx
    self.rotationDegrees = rotationDegrees
    self.floorHeight = floorHeight
    self.source = source
    self.rooms = rooms
  }

  enum CodingKeys: String, CodingKey {
    case level
    case image
    case metresPerPixel = "metres_per_pixel"
    case originPx = "origin_px"
    case rotationDegrees = "rotation_deg"
    case floorHeight = "floor_height_m"
    case source
    case rooms
  }

  /// Decoding tolerates a plan written by an older `plan add`, which has neither
  /// `source` nor `rooms`, and ignores anything it does not know — §12's rule,
  /// and what makes section 13 additive rather than a version bump.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    level = try c.decode(String.self, forKey: .level)
    image = try c.decode(String.self, forKey: .image)
    metresPerPixel = try c.decodeIfPresent(Double.self, forKey: .metresPerPixel)
    originPx = try c.decodeIfPresent([Double].self, forKey: .originPx)
    rotationDegrees = try c.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
    floorHeight = try c.decodeIfPresent(Double.self, forKey: .floorHeight) ?? 0
    source = try c.decodeIfPresent(PlanSource.self, forKey: .source)
    rooms = try c.decodeIfPresent([PlanRoom].self, forKey: .rooms) ?? []
  }

  /// Place a room, or move it if it is already placed.
  ///
  /// Placing is idempotent per room because a room is in one place: a second
  /// placement is a correction, and rule 4 refuses a level with the same slug
  /// twice. Out-of-bounds is refused here rather than written and caught later
  /// by `validate --project`.
  @discardableResult
  public mutating func place(
    room: String, x: Double, y: Double, in size: (width: Int, height: Int), at date: Date = Date()
  ) -> Bool {
    guard SessionID.slug(room) == room else { return false }
    guard x >= 0, y >= 0, x <= Double(size.width), y <= Double(size.height) else { return false }
    let entry = PlanRoom(room: room, x: x, y: y, placedAt: PlanRoom.iso8601(date))
    if let index = rooms.firstIndex(where: { $0.room == room }) {
      rooms[index] = entry
    } else {
      rooms.append(entry)
    }
    return true
  }

  public mutating func unplace(room: String) {
    rooms.removeAll { $0.room == room }
  }

  public func placement(of room: String) -> PlanRoom? {
    rooms.first { $0.room == room }
  }
}

/// The imported file, kept verbatim beside the raster.
public struct PlanSource: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case pdf
    case jpeg
    case heic
  }

  public var file: String
  public var kind: Kind
  /// Only meaningful for `pdf`.
  public var page: Int?

  public init(file: String, kind: Kind, page: Int? = nil) {
    self.file = file
    self.kind = kind
    self.page = page
  }
}

/// Where the owner says a room is, in **pixels of the raster**, origin top-left.
///
/// Not metres and not plan units: an uncalibrated raster has no metric meaning,
/// which is the point of it being uncalibrated.
///
/// **This is not a correspondence.** It is a fingertip on a drawing, recorded so
/// the app can shade a room by what has been captured. It carries no accuracy
/// claim and is never an input to alignment — `vividhome align` reads
/// `landmarks.jsonl` and marker poses, and nothing else. The two have the same
/// shape, a label and a 2D point, so only the rule keeps them apart.
public struct PlanRoom: Codable, Equatable, Sendable {
  public var room: String
  public var x: Double
  public var y: Double
  public var placedAt: String

  public init(room: String, x: Double, y: Double, placedAt: String) {
    self.room = room
    self.x = x
    self.y = y
    self.placedAt = placedAt
  }

  enum CodingKeys: String, CodingKey {
    case room
    case x
    case y
    case placedAt = "placed_at"
  }

  public static func iso8601(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.string(from: date)
  }
}
