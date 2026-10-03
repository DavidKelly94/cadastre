import Foundation

/// Placing a capture on the plan from tapped corners, on the phone (ADR-0031,
/// design §3): the same rigid 2D fit `align.py` solves, with the same file
/// shape written at the end, so the PC adopts the result instead of redoing it.
///
/// Rotation and translation only, no scale: the phone's own scale is metric,
/// and a fitted scale would absorb real error instead of reporting it. The
/// tests pin this to numbers `umeyama_2d` produced for the same points.
public enum PlanAlignment {
  /// One tapped corner matched to the plan's corner of the same name, both as
  /// horizontal `(x, z)` metres: the session frame and the house frame.
  public struct Pair: Equatable, Sendable {
    public var label: String
    public var sessionXZ: (x: Double, z: Double)
    public var houseXZ: (x: Double, z: Double)

    public init(label: String, sessionXZ: (x: Double, z: Double), houseXZ: (x: Double, z: Double)) {
      self.label = label
      self.sessionXZ = sessionXZ
      self.houseXZ = houseXZ
    }

    public static func == (lhs: Pair, rhs: Pair) -> Bool {
      lhs.label == rhs.label && lhs.sessionXZ == rhs.sessionXZ && lhs.houseXZ == rhs.houseXZ
    }
  }

  /// How good a fit is, in the owner's terms. The numbers are the design's:
  /// under 10 cm is placed, under the PC's 30 cm refusal is worth a look, and
  /// above that the PC would refuse it too.
  public enum Verdict: String, Equatable, Sendable {
    case placed
    case check
    case notPlaced
  }

  public static let placedBelowMetres = 0.10
  /// `REFUSE_RMS_M` in `align.py`.
  public static let refuseAboveMetres = 0.30

  public struct Solution: Equatable, Sendable {
    /// `T_hs`, column-major, as the format stores every 4x4.
    public var tHs: [Double]
    public var yawDegrees: Double
    public var pairs: [Pair]
    public var residuals: [Double]
    public var rms: Double
    public var maxResidual: Double
    public var floorSource: String

    public var verdict: Verdict {
      if rms < PlanAlignment.placedBelowMetres { return .placed }
      if rms <= PlanAlignment.refuseAboveMetres { return .check }
      return .notPlaced
    }

    /// Session metres to house metres, horizontally.
    public func houseXZ(sessionX x: Double, z: Double) -> (x: Double, z: Double) {
      (tHs[0] * x + tHs[8] * z + tHs[12], tHs[2] * x + tHs[10] * z + tHs[14])
    }

    /// One line for the HUD and the review: "placed, 6 cm" or "check, 18 cm".
    public var summary: String {
      let centimetres = Int((rms * 100).rounded())
      switch verdict {
      case .placed: return "Placed on the plan, \(centimetres) cm"
      case .check: return "Check the corners: \(centimetres) cm off"
      case .notPlaced: return "Not placed: \(centimetres) cm off, a corner is wrong"
      }
    }
  }

  /// Fit the pairs. Nil with fewer than two.
  ///
  /// `floorY` is the session-frame height of the floor and `floorHeight` the
  /// level's height in the house, so that `T_hs` lifts the session onto the
  /// level as `align.py` does (`t_y = floor_height_m - floor_y`).
  public static func solve(
    pairs: [Pair], floorY: Double, floorSource: String, floorHeight: Double
  ) -> Solution? {
    guard pairs.count >= 2 else { return nil }
    let fit = Umeyama2D.fit(
      from: pairs.map { $0.sessionXZ }, to: pairs.map { $0.houseXZ })
    let residuals = pairs.map { pair -> Double in
      let x = fit.c * pair.sessionXZ.x - fit.s * pair.sessionXZ.z + fit.tx
      let z = fit.s * pair.sessionXZ.x + fit.c * pair.sessionXZ.z + fit.tz
      return ((x - pair.houseXZ.x) * (x - pair.houseXZ.x) + (z - pair.houseXZ.z) * (z - pair.houseXZ.z))
        .squareRoot()
    }
    let ty = floorHeight - floorY
    // embed_se2: the 2x2 acting on (x, z) goes into rows and columns 0 and 2.
    let tHs: [Double] = [
      fit.c, 0, fit.s, 0,
      0, 1, 0, 0,
      -fit.s, 0, fit.c, 0,
      fit.tx, ty, fit.tz, 1,
    ]
    return Solution(
      tHs: tHs,
      yawDegrees: atan2(tHs[8], tHs[0]) * 180 / .pi,
      pairs: pairs,
      residuals: residuals,
      rms: fit.rms,
      maxResidual: residuals.max() ?? 0,
      floorSource: floorSource)
  }

  /// The floor's height in the session frame, by `align.py`'s preference: the
  /// median of landmarks tagged floor, else the lowest landmark, else zero.
  /// The mesh step the PC has in between is not on the phone yet.
  public static func floorY(landmarks: [(kind: LandmarkKind, y: Double)]) -> (y: Double, source: String) {
    let floors = landmarks.filter { $0.kind == .floor }.map { $0.y }.sorted()
    if !floors.isEmpty {
      let middle = floors.count / 2
      let median = floors.count % 2 == 1 ? floors[middle] : (floors[middle - 1] + floors[middle]) / 2
      return (median, "floor-landmarks")
    }
    if let lowest = landmarks.map({ $0.y }).min() {
      return (lowest, "lowest-landmark")
    }
    return (0, "assumed-zero")
  }
}

/// Least-squares rigid 2D fit taking points `a` onto points `b`: `umeyama_2d`
/// in `transforms.py`, in closed form. The rotation is the angle that
/// maximises the alignment of the centred point sets, which is the proper
/// rotation the SVD form returns with its reflection guard.
public enum Umeyama2D {
  public struct Fit: Equatable, Sendable {
    /// cos and sin of the rotation taking `a` onto `b`.
    public var c: Double
    public var s: Double
    public var tx: Double
    public var tz: Double
    public var rms: Double
  }

  public static func fit(from a: [(x: Double, z: Double)], to b: [(x: Double, z: Double)]) -> Fit {
    precondition(a.count == b.count && a.count >= 2, "at least two correspondences")
    let n = Double(a.count)
    let ca = (a.map(\.x).reduce(0, +) / n, a.map(\.z).reduce(0, +) / n)
    let cb = (b.map(\.x).reduce(0, +) / n, b.map(\.z).reduce(0, +) / n)
    var dot = 0.0
    var cross = 0.0
    for (p, q) in zip(a, b) {
      let ax = p.x - ca.0, az = p.z - ca.1
      let bx = q.x - cb.0, bz = q.z - cb.1
      dot += ax * bx + az * bz
      cross += ax * bz - az * bx
    }
    let theta = atan2(cross, dot)
    let c = cos(theta), s = sin(theta)
    let tx = cb.0 - (c * ca.0 - s * ca.1)
    let tz = cb.1 - (s * ca.0 + c * ca.1)
    var sum = 0.0
    for (p, q) in zip(a, b) {
      let x = c * p.x - s * p.z + tx
      let z = s * p.x + c * p.z + tz
      sum += (x - q.x) * (x - q.x) + (z - q.z) * (z - q.z)
    }
    return Fit(c: c, s: s, tx: tx, tz: tz, rms: (sum / n).squareRoot())
  }
}

/// `alignments/<session-id>.json` as the app writes it (ADR-0030, ADR-0031):
/// the PC's own shape plus `source` and a `method` the PC does not produce:
/// `guided` for corners asked for by name during capture, `paired` for a free
/// capture whose landmarks were paired with the drawing afterwards.
public struct AlignmentFile: Codable, Equatable, Sendable {
  public struct Correspondence: Codable, Equatable, Sendable {
    public var label: String
    public var sessionXZ: [Double]
    public var houseXZ: [Double]
    public var source: String

    enum CodingKeys: String, CodingKey {
      case label
      case sessionXZ = "session_xz"
      case houseXZ = "house_xz"
      case source
    }
  }

  public var sessionID: String
  public var level: String
  public var tHs: [Double]
  public var pairs: [Correspondence]
  public var rmsM: Double
  public var maxResidualM: Double
  public var method: String
  public var floorSource: String
  public var createdAt: String
  public var source: String

  enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case level
    case tHs = "T_hs"
    case pairs
    case rmsM = "rms_m"
    case maxResidualM = "max_residual_m"
    case method
    case floorSource = "floor_source"
    case createdAt = "created_at"
    case source
  }

  public init(sessionID: String, level: String, solution: PlanAlignment.Solution, method: String = "guided", at date: Date = Date()) {
    self.sessionID = sessionID
    self.level = level
    self.tHs = solution.tHs
    self.pairs = solution.pairs.map {
      Correspondence(
        label: $0.label, sessionXZ: [$0.sessionXZ.x, $0.sessionXZ.z],
        houseXZ: [$0.houseXZ.x, $0.houseXZ.z], source: "landmark")
    }
    self.rmsM = (solution.rms * 1e6).rounded() / 1e6
    self.maxResidualM = (solution.maxResidual * 1e6).rounded() / 1e6
    self.method = method
    self.floorSource = solution.floorSource
    self.createdAt = PlanRoom.iso8601(date)
    self.source = "app"
  }

  /// `alignments/<session-id>.json` beside `plans/` in the project folder.
  public static func url(projectDirectory: URL, sessionID: String) -> URL {
    projectDirectory
      .appendingPathComponent("alignments", isDirectory: true)
      .appendingPathComponent("\(sessionID).json")
  }

  public func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(self).write(to: url, options: .atomic)
  }

  /// The file at `url`, or nil when there is none or it does not decode:
  /// a capture with no placement yet reads the same as one never written.
  public static func read(at url: URL) -> AlignmentFile? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(AlignmentFile.self, from: data)
  }
}
