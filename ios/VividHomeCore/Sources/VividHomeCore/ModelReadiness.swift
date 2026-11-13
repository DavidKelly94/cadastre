import Foundation

/// Whether a capture holds enough to build a 3D model from (ADR-0035,
/// `capture-guidance-design.md` section 3), and what it still lacks.
///
/// Wall coverage asks whether each stretch of wall was photographed. A model
/// needs more: each stretch seen from two places a useful angle apart, and
/// the floor and the ceiling seen at all. Turning on the spot in the middle
/// of a room photographs every wall and fails this, which is the point.
///
/// Everything here comes from camera poses the session already records. The
/// pipeline computes the same numbers (`readiness.py`) and the contract job
/// compares them. Every threshold is a first guess, to be set from real
/// captures.
public enum ModelReadiness {
  /// The bearings a stretch of wall was photographed from must span this.
  public static let viewSpreadDegrees = 20.0
  /// And one of those views must be at least this close.
  public static let nearMeters = 2.5
  /// A camera tilted this far down is looking at the floor; up, the ceiling.
  public static let pitchDegrees = 25.0
  /// How many such keyframes count as having seen it,
  public static let pitchedKeyframes = 10
  /// from at least this many different squares of floor
  public static let pitchedSquares = 3
  /// of this size.
  public static let squareMeters = 0.5
  /// A second height is this far from the usual one,
  public static let heightStepMeters = 0.4
  /// for at least this share of the keyframes.
  public static let heightShare = 0.15
  /// The share of wall seen twice that reads as enough.
  public static let wallsTwiceEnough = 0.70
  /// A stretch shorter than this is not worth naming.
  public static let minimumGapMeters = 0.3
  /// How many stretches the report keeps.
  public static let gapsKept = 3

  // MARK: - Where the camera was and how it was tilted

  /// One keyframe: where the camera was and how far its view tilts up
  /// (positive) or down. Height and tilt do not change when a capture is
  /// placed, so the session frame serves.
  public struct View: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    /// The vertical part of the unit view direction.
    public var forwardY: Double

    public init(x: Double, y: Double, z: Double, forwardY: Double) {
      self.x = x
      self.y = y
      self.z = z
      self.forwardY = forwardY
    }

    /// From a keyframe's camera-to-world pose: ARKit's camera looks down its
    /// own `-z` (section 3).
    public init(pose: Transform) {
      let e = pose.elements
      let fx = -e[8], fy = -e[9], fz = -e[10]
      let length = (fx * fx + fy * fy + fz * fz).squareRoot()
      self.init(x: e[12], y: e[13], z: e[14], forwardY: length > 0 ? fy / length : 0)
    }
  }

  // MARK: - Walls seen from two places

  /// One wall of the outline and the directions it has been photographed from.
  public struct WallViews: Equatable, Sendable {
    public var start: String
    public var end: String
    public var length: Double
    /// Per cell: the lowest and highest bearing it was photographed from,
    /// in radians along the wall, and the nearest such view. A cell nobody
    /// has photographed has `low > high`.
    var low: [Double]
    var high: [Double]
    var nearest: [Double]
    var startX: Double, startZ: Double, directionX: Double, directionZ: Double

    public var cells: Int { low.count }

    /// Per cell, whether it has been seen from two places.
    public var seenTwice: [Bool] {
      let spread = ModelReadiness.viewSpreadDegrees * Double.pi / 180
      return (0..<cells).map { cell in
        low[cell] <= high[cell] && high[cell] - low[cell] >= spread
          && nearest[cell] <= ModelReadiness.nearMeters
      }
    }

    /// Per cell, whether it has been photographed at all.
    public var seenOnce: [Bool] { (0..<cells).map { low[$0] <= high[$0] } }

    /// Runs of cells not seen twice, as (meters from `start`, length).
    public var gaps: [(from: Double, length: Double)] {
      let twice = seenTwice
      var out: [(from: Double, length: Double)] = []
      var index = 0
      while index < twice.count {
        guard !twice[index] else { index += 1; continue }
        let begin = index
        while index < twice.count, !twice[index] { index += 1 }
        let from = Double(begin) * WallCoverage.cellMetres
        let to = min(Double(index) * WallCoverage.cellMetres, length)
        out.append((from, to - from))
      }
      return out
    }
  }

  /// The walls of an outline, nothing seen yet. The same cells as
  /// `WallCoverage.walls`.
  public static func walls(outline: [(label: String, x: Double, z: Double)]) -> [WallViews] {
    guard outline.count >= 2 else { return [] }
    var out: [WallViews] = []
    for index in outline.indices {
      let a = outline[index], b = outline[(index + 1) % outline.count]
      let dx = b.x - a.x, dz = b.z - a.z
      let length = (dx * dx + dz * dz).squareRoot()
      guard length > 0 else { continue }
      let cells = max(1, Int((length / WallCoverage.cellMetres).rounded(.up)))
      out.append(
        WallViews(
          start: a.label, end: b.label, length: length,
          low: Array(repeating: 1, count: cells), high: Array(repeating: -1, count: cells),
          nearest: Array(repeating: Double.infinity, count: cells),
          startX: a.x, startZ: a.z, directionX: dx / length, directionZ: dz / length))
    }
    return out
  }

  /// Add what one camera, in the same frame as the outline, photographs.
  /// A cell counts under exactly the rule `WallCoverage.add` uses: in range,
  /// inside the image, and not behind another wall.
  public static func add(
    _ camera: WallCoverage.Camera, to walls: inout [WallViews], range: Double = WallCoverage.rangeMetres
  ) {
    let cosLimit = cos(camera.spread)
    let segments = walls.map { wall in
      (ax: wall.startX, az: wall.startZ,
       bx: wall.startX + wall.directionX * wall.length, bz: wall.startZ + wall.directionZ * wall.length)
    }
    for index in walls.indices {
      let wall = walls[index]
      for cell in 0..<wall.cells {
        let along = min((Double(cell) + 0.5) * WallCoverage.cellMetres, wall.length)
        let cx = wall.startX + along * wall.directionX
        let cz = wall.startZ + along * wall.directionZ
        let vx = cx - camera.x, vz = cz - camera.z
        let distance = (vx * vx + vz * vz).squareRoot()
        guard distance > 0, distance <= range else { continue }
        let bearing = (vx * camera.forwardX + vz * camera.forwardZ) / distance
        guard bearing >= cosLimit else { continue }
        guard visible(fromX: camera.x, fromZ: camera.z, toX: cx, toZ: cz, segments: segments, except: index)
        else { continue }
        // Where the camera stands as seen from the cell, as an angle along
        // the wall. Every camera is on the room's side, so the angles of one
        // wall share a sign and never wrap.
        let angle = atan2(
          wall.directionX * -vz - wall.directionZ * -vx, wall.directionX * -vx + wall.directionZ * -vz)
        if walls[index].low[cell] > walls[index].high[cell] {
          walls[index].low[cell] = angle
          walls[index].high[cell] = angle
        } else {
          walls[index].low[cell] = min(walls[index].low[cell], angle)
          walls[index].high[cell] = max(walls[index].high[cell], angle)
        }
        walls[index].nearest[cell] = min(walls[index].nearest[cell], distance)
      }
    }
  }

  /// Rebuild from every camera.
  public static func wallViews(
    outline: [(label: String, x: Double, z: Double)], cameras: [WallCoverage.Camera],
    range: Double = WallCoverage.rangeMetres
  ) -> [WallViews] {
    var out = walls(outline: outline)
    for camera in cameras { add(camera, to: &out, range: range) }
    return out
  }

  static func visible(
    fromX ax: Double, fromZ az: Double, toX bx: Double, toZ bz: Double,
    segments: [(ax: Double, az: Double, bx: Double, bz: Double)], except: Int
  ) -> Bool {
    func cross(_ ux: Double, _ uz: Double, _ vx: Double, _ vz: Double) -> Double { ux * vz - uz * vx }
    for (index, s) in segments.enumerated() where index != except {
      let d1 = cross(s.bx - s.ax, s.bz - s.az, ax - s.ax, az - s.az)
      let d2 = cross(s.bx - s.ax, s.bz - s.az, bx - s.ax, bz - s.az)
      let d3 = cross(bx - ax, bz - az, s.ax - ax, s.az - az)
      let d4 = cross(bx - ax, bz - az, s.bx - ax, s.bz - az)
      if d1 * d2 < 0 && d3 * d4 < 0 { return false }
    }
    return true
  }

  // MARK: - The report

  /// What the leave check records under `field_check.model` (section 4).
  public struct Report: Codable, Equatable, Sendable {
    /// The share of wall seen from two places, 0 to 1 in hundredths. Nil
    /// when the capture is not placed on an outline, so there are no walls
    /// to measure against.
    public var wallsTwice: Double?
    public var floor: Bool
    public var ceiling: Bool
    /// Whether the camera was held at two heights. Advice, not a condition.
    public var heights: Bool
    /// The longest stretches of wall not yet seen twice, longest first.
    public var gaps: [FieldCheck.Walls.Gap]

    public init(wallsTwice: Double?, floor: Bool, ceiling: Bool, heights: Bool, gaps: [FieldCheck.Walls.Gap]) {
      self.wallsTwice = wallsTwice
      self.floor = floor
      self.ceiling = ceiling
      self.heights = heights
      self.gaps = gaps
    }

    enum CodingKeys: String, CodingKey {
      case wallsTwice = "walls_twice"
      case floor, ceiling, heights, gaps
    }

    /// Green when the walls, the floor and the ceiling are all there.
    public var enough: Bool {
      (wallsTwice ?? 0) >= ModelReadiness.wallsTwiceEnough && floor && ceiling
    }

    var wallsPercent: Int { Int(((wallsTwice ?? 0) * 100 + 0.5).rounded(.down)) }

    /// The leave check's line: advice, never a reason to stop.
    public func line(in units: Units) -> FieldCheck.Line {
      if enough { return FieldCheck.Line(text: "Enough for 3D", ok: true) }
      var parts: [String] = []
      if wallsTwice == nil {
        parts.append("walls unknown until the capture is placed")
      } else if (wallsTwice ?? 0) < ModelReadiness.wallsTwiceEnough {
        parts.append("walls seen from two spots: \(wallsPercent)%")
      }
      if !floor { parts.append("floor not seen") }
      if !ceiling { parts.append("ceiling not seen") }
      return FieldCheck.Line(text: "Not enough for 3D yet: " + parts.joined(separator: "; "), ok: false)
    }

    /// What is still missing, worst first, each as something to do about it.
    public func missing(in units: Units) -> [String] {
      var out: [String] = []
      if let wallsTwice, wallsTwice < ModelReadiness.wallsTwiceEnough, let worst = gaps.first {
        let corners = worst.wall.components(separatedBy: "->").map(FieldCheck.short)
        let name = corners.count == 2 ? "\(corners[0])–\(corners[1]) wall" : worst.wall
        let corner = corners.first ?? "its first corner"
        let place = worst.fromM > 0 ? "\(units.length(worst.fromM)) past \(corner)" : "at \(corner)"
        out.append(
          "\(name): \(units.length(worst.lengthM)) seen from one spot only, starting \(place). "
            + "Step sideways and look again.")
      }
      if !ceiling { out.append("Ceiling not seen. Tilt up as you walk.") }
      if !floor { out.append("Floor not seen. Tilt down as you walk.") }
      if out.isEmpty, !heights {
        out.append("One height only. A second pass with the phone raised helps.")
      }
      return out
    }
  }

  /// Measure a capture. `walls` is nil when it is not placed on an outline.
  public static func report(views: [View], walls: [WallViews]?) -> Report {
    let down = sin(pitchDegrees * Double.pi / 180)
    func seen(_ test: (View) -> Bool) -> Bool {
      var count = 0
      var squares: Set<String> = []
      for view in views where test(view) {
        count += 1
        let column = Int((view.x / squareMeters).rounded(.down))
        let row = Int((view.z / squareMeters).rounded(.down))
        squares.insert("\(column),\(row)")
      }
      return count >= pitchedKeyframes && squares.count >= pitchedSquares
    }
    let floor = seen { $0.forwardY <= -down }
    let ceiling = seen { $0.forwardY >= down }

    var heights = false
    if !views.isEmpty {
      let sorted = views.map(\.y).sorted()
      let median = sorted.count % 2 == 1
        ? sorted[sorted.count / 2]
        : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
      let apart = views.filter { abs($0.y - median) >= heightStepMeters }.count
      heights = Double(apart) >= heightShare * Double(views.count)
    }

    var wallsTwice: Double?
    var gaps: [FieldCheck.Walls.Gap] = []
    if let walls, !walls.isEmpty {
      let cells = walls.reduce(0) { $0 + $1.cells }
      let twice = walls.reduce(0) { $0 + $1.seenTwice.filter { $0 }.count }
      wallsTwice = cells == 0 ? 0 : hundredths(Double(twice) / Double(cells))
      var runs: [(order: Int, gap: FieldCheck.Walls.Gap)] = []
      for (order, wall) in walls.enumerated() {
        for run in wall.gaps where run.length >= minimumGapMeters {
          runs.append(
            (order,
             FieldCheck.Walls.Gap(
               wall: "\(wall.start)->\(wall.end)", fromM: tenths(run.from), lengthM: tenths(run.length))))
        }
      }
      runs.sort {
        if $0.gap.lengthM != $1.gap.lengthM { return $0.gap.lengthM > $1.gap.lengthM }
        if $0.order != $1.order { return $0.order < $1.order }
        return $0.gap.fromM < $1.gap.fromM
      }
      gaps = runs.prefix(gapsKept).map(\.gap)
    }
    return Report(wallsTwice: wallsTwice, floor: floor, ceiling: ceiling, heights: heights, gaps: gaps)
  }

  static func hundredths(_ value: Double) -> Double { (value * 100 + 0.5).rounded(.down) / 100 }
  static func tenths(_ value: Double) -> Double { (value * 10 + 0.5).rounded(.down) / 10 }
}
