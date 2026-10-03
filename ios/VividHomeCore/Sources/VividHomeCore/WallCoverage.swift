import Foundation

/// Which parts of a room's walls the keyframes have photographed, live, as the
/// room is captured (ADR-0031, design §4): the rule `vividhome coverage` runs
/// offline, applied to the outline and the keyframes so far.
///
/// A wall is the segment between two consecutive outline corners, in house
/// metres, cut into 10 cm cells. A cell is photographed when some keyframe
/// was within range of it, had it within the footprint its frustum makes on
/// the floor, and had no other wall of the room in the way. The mesh half of
/// the offline report is not computed here.
public enum WallCoverage {
  /// Along a wall. Finer than any gap worth reporting.
  public static let cellMetres = 0.10
  /// How far a keyframe can be from a wall and still count as photographing it.
  public static let rangeMetres = 4.0
  /// A camera with less horizontal forward than this is pointed at the floor
  /// or the ceiling and photographs no wall.
  public static let minimumHorizontalForward = 0.3

  /// One keyframe's footprint on the floor: where it was, which way it looked,
  /// and the half-angle its image corners make on the plan. In whatever frame
  /// its pose was in; `moved(by:)` takes it into the house frame.
  public struct Camera: Equatable, Sendable {
    public var x: Double
    public var z: Double
    public var forwardX: Double
    public var forwardZ: Double
    public var spread: Double

    public init(x: Double, z: Double, forwardX: Double, forwardZ: Double, spread: Double) {
      self.x = x
      self.z = z
      self.forwardX = forwardX
      self.forwardZ = forwardZ
      self.spread = spread
    }

    /// From a keyframe's camera-to-world pose and intrinsics, as `_cameras`
    /// in `coverage.py` reads them. Nil for a camera pointed at the floor or
    /// the ceiling.
    public init?(pose: Transform, fx: Double, fy: Double, width: Int, height: Int) {
      let e = pose.elements
      // Columns of the rotation block: x axis e[0..2], y axis e[4..6], z axis e[8..10].
      let forward = (-e[8], -e[9], -e[10])
      let horizontal = (forward.0 * forward.0 + forward.2 * forward.2).squareRoot()
      guard horizontal >= WallCoverage.minimumHorizontalForward else { return nil }
      let flat = (forward.0 / horizontal, forward.2 / horizontal)
      let tanX = Double(width) / (2 * fx)
      let tanY = Double(height) / (2 * fy)
      var spread = 0.0
      for sx in [-1.0, 1.0] {
        for sy in [-1.0, 1.0] {
          // R · (sx·tanX, sy·tanY, -1), flattened onto the floor.
          let cx = sx * tanX, cy = sy * tanY, cz = -1.0
          let rayX = e[0] * cx + e[4] * cy + e[8] * cz
          let rayZ = e[2] * cx + e[6] * cy + e[10] * cz
          let length = (rayX * rayX + rayZ * rayZ).squareRoot()
          guard length > 0 else { continue }
          let angle = abs(atan2(flat.0 * (rayZ / length) - flat.1 * (rayX / length),
            flat.0 * (rayX / length) + flat.1 * (rayZ / length)))
          spread = max(spread, angle)
        }
      }
      self.init(x: e[12], z: e[14], forwardX: flat.0, forwardZ: flat.1, spread: spread)
    }

    /// This camera in the house frame, through a placement.
    public func moved(by placement: PlanAlignment.Solution) -> Camera {
      moved(byTHs: placement.tHs)
    }

    /// This camera in the house frame, through a stored `T_hs` (column-major,
    /// as the alignment file holds it): a yaw and a translation.
    public func moved(byTHs t: [Double]) -> Camera {
      guard t.count == 16 else { return self }
      return Camera(
        x: t[0] * x + t[8] * z + t[12], z: t[2] * x + t[10] * z + t[14],
        forwardX: t[0] * forwardX + t[8] * forwardZ, forwardZ: t[2] * forwardX + t[10] * forwardZ,
        spread: spread)
    }
  }

  /// One wall of the outline and what has photographed it.
  public struct Wall: Equatable, Sendable {
    public var start: String
    public var end: String
    public var length: Double
    public var photographed: [Bool]
    var startX: Double, startZ: Double, directionX: Double, directionZ: Double

    public var cells: Int { photographed.count }
    public var fraction: Double {
      cells == 0 ? 0 : Double(photographed.filter { $0 }.count) / Double(cells)
    }

    /// Runs of cells never photographed, as (metres from `start`, length).
    public var gaps: [(from: Double, length: Double)] {
      var out: [(from: Double, length: Double)] = []
      var index = 0
      while index < photographed.count {
        guard !photographed[index] else { index += 1; continue }
        let begin = index
        while index < photographed.count, !photographed[index] { index += 1 }
        let from = Double(begin) * WallCoverage.cellMetres
        let to = min(Double(index) * WallCoverage.cellMetres, length)
        out.append((from, to - from))
      }
      return out
    }
  }

  /// The walls of an outline, nothing photographed yet.
  public static func walls(outline: [(label: String, x: Double, z: Double)]) -> [Wall] {
    guard outline.count >= 2 else { return [] }
    var out: [Wall] = []
    for index in outline.indices {
      let a = outline[index], b = outline[(index + 1) % outline.count]
      let dx = b.x - a.x, dz = b.z - a.z
      let length = (dx * dx + dz * dz).squareRoot()
      guard length > 0 else { continue }
      let cells = max(1, Int((length / cellMetres).rounded(.up)))
      out.append(
        Wall(
          start: a.label, end: b.label, length: length, photographed: Array(repeating: false, count: cells),
          startX: a.x, startZ: a.z, directionX: dx / length, directionZ: dz / length))
    }
    return out
  }

  /// Mark what one camera, in the house frame, photographs of these walls.
  public static func add(_ camera: Camera, to walls: inout [Wall], range: Double = rangeMetres) {
    let cosLimit = cos(camera.spread)
    for index in walls.indices {
      let wall = walls[index]
      for cell in 0..<wall.cells where !wall.photographed[cell] {
        let along = min((Double(cell) + 0.5) * cellMetres, wall.length)
        let cx = wall.startX + along * wall.directionX
        let cz = wall.startZ + along * wall.directionZ
        let vx = cx - camera.x, vz = cz - camera.z
        let distance = (vx * vx + vz * vz).squareRoot()
        guard distance > 0, distance <= range else { continue }
        let bearing = (vx * camera.forwardX + vz * camera.forwardZ) / distance
        guard bearing >= cosLimit else { continue }
        guard visible(from: (camera.x, camera.z), to: (cx, cz), walls: walls, except: index) else { continue }
        walls[index].photographed[cell] = true
      }
    }
  }

  /// Rebuild from every camera: what `add` gives for each, from nothing.
  public static func coverage(
    outline: [(label: String, x: Double, z: Double)], cameras: [Camera], range: Double = rangeMetres
  ) -> [Wall] {
    var out = walls(outline: outline)
    for camera in cameras { add(camera, to: &out, range: range) }
    return out
  }

  /// Whether the segment from the camera to a cell crosses none of the other
  /// walls (proper crossings only, as `_visible` in `coverage.py`).
  static func visible(from a: (Double, Double), to b: (Double, Double), walls: [Wall], except: Int) -> Bool {
    func cross(_ ux: Double, _ uz: Double, _ vx: Double, _ vz: Double) -> Double { ux * vz - uz * vx }
    for (index, wall) in walls.enumerated() where index != except {
      let c = (wall.startX, wall.startZ)
      let d = (wall.startX + wall.directionX * wall.length, wall.startZ + wall.directionZ * wall.length)
      let d1 = cross(d.0 - c.0, d.1 - c.1, a.0 - c.0, a.1 - c.1)
      let d2 = cross(d.0 - c.0, d.1 - c.1, b.0 - c.0, b.1 - c.1)
      let d3 = cross(b.0 - a.0, b.1 - a.1, c.0 - a.0, c.1 - a.1)
      let d4 = cross(b.0 - a.0, b.1 - a.1, d.0 - a.0, d.1 - a.1)
      if d1 * d2 < 0 && d3 * d4 < 0 { return false }
    }
    return true
  }
}

extension PlanAlignment.Solution {
  /// A session direction in the house frame: the rotation only.
  public func houseDirection(sessionX x: Double, z: Double) -> (x: Double, z: Double) {
    (tHs[0] * x + tHs[8] * z, tHs[2] * x + tHs[10] * z)
  }
}
