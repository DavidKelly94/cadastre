import Foundation

/// Moving a tapped corner to where two mesh walls meet the floor (ADR-0031,
/// design §3): the rule `corners.py` runs offline over a whole mesh, applied to
/// the faces within half a metre of the tap, on the phone, at tap time.
///
/// The ARKit layer gathers the nearby faces, in session metres with their
/// classification, and hands them here; nothing in this file knows ARKit.
/// A tap raycast onto the mesh lands on a surface that rounds the corner, so
/// it can be a few centimetres off; two fitted wall planes meet where the
/// walls actually do.
public enum CornerSnap {
  /// One mesh triangle in session coordinates, with the format's class byte
  /// (1 wall, 2 floor, section 9).
  public struct Face: Equatable, Sendable {
    public var a: Vector3
    public var b: Vector3
    public var c: Vector3
    public var classification: UInt8

    public init(a: Vector3, b: Vector3, c: Vector3, classification: UInt8) {
      self.a = a
      self.b = b
      self.c = c
      self.classification = classification
    }
  }

  public struct Snap: Equatable, Sendable {
    public var position: Vector3
    /// How far the point moved from the tap, in metres.
    public var movedBy: Double
    /// Where the floor height came from: `floor-faces`, `wall-bottoms` or `tap`.
    public var floorSource: String
  }

  /// How far a tap may be moved. A corner further off than this is not the
  /// corner that was tapped.
  public static let reachMetres = 0.5
  /// `method` in `landmarks.jsonl` for a snapped corner.
  public static let method = "mesh_corner_snap"

  static let wallClass: UInt8 = 1
  static let floorClass: UInt8 = 2

  /// A vertical plane through nearby wall faces, as a line in the x-z plane:
  /// `normal · (x, z) == offset`.
  struct Wall: Equatable {
    var azimuth: Double
    var offset: Double
    var area: Double
    var extent: (low: Double, high: Double)
    var bottom: Double

    var normal: (Double, Double) { (cos(azimuth), sin(azimuth)) }
    var tangent: (Double, Double) { (-sin(azimuth), cos(azimuth)) }

    static func == (lhs: Wall, rhs: Wall) -> Bool {
      lhs.azimuth == rhs.azimuth && lhs.offset == rhs.offset && lhs.area == rhs.area
        && lhs.extent == rhs.extent && lhs.bottom == rhs.bottom
    }
  }

  /// The corner nearest the tap that two walls make, or nil when the faces
  /// around the tap do not show two walls meeting within reach.
  public static func snap(tap: Vector3, faces: [Face]) -> Snap? {
    let walls = findWalls(faces)
    guard walls.count >= 2 else { return nil }

    var best: (x: Double, z: Double, distance: Double)?
    for i in 0..<walls.count {
      for j in (i + 1)..<walls.count {
        guard let point = intersection(walls[i], walls[j]) else { continue }
        let distance = ((point.x - tap.x) * (point.x - tap.x) + (point.z - tap.z) * (point.z - tap.z))
          .squareRoot()
        guard distance <= reachMetres else { continue }
        if best == nil || distance < best!.distance {
          best = (point.x, point.z, distance)
        }
      }
    }
    guard let corner = best else { return nil }

    let floor = floorY(faces, walls: walls, tap: tap)
    let position = Vector3(corner.x, floor.y, corner.z)
    let moved = ((position.x - tap.x) * (position.x - tap.x) + (position.y - tap.y) * (position.y - tap.y)
      + (position.z - tap.z) * (position.z - tap.z)).squareRoot()
    return Snap(position: position, movedBy: moved, floorSource: floor.source)
  }

  // MARK: - Walls

  /// Greedy clustering of wall faces into vertical planes, as `find_walls`:
  /// the largest unassigned face seeds a plane, faces within 10° of its
  /// normal and 15 cm of its line join, the plane is refitted by area, and
  /// membership is taken once more. Clusters under 0.05 m² are furniture.
  static func findWalls(_ faces: [Face]) -> [Wall] {
    struct Candidate {
      var theta: Double
      var area: Double
      var cx: Double
      var cz: Double
      var corners: [Vector3]
    }
    var candidates: [Candidate] = []
    for face in faces where face.classification == wallClass {
      let (nx, ny, nz, area) = normalAndArea(face)
      guard area > 0, abs(ny) <= 0.2 else { continue }
      candidates.append(
        Candidate(
          theta: fold(atan2(nz, nx)), area: area,
          cx: (face.a.x + face.b.x + face.c.x) / 3, cz: (face.a.z + face.b.z + face.c.z) / 3,
          corners: [face.a, face.b, face.c]))
    }
    guard !candidates.isEmpty else { return [] }

    let angleTolerance = 10.0 * .pi / 180
    let offsetTolerance = 0.15
    var remaining = Array(repeating: true, count: candidates.count)
    var walls: [Wall] = []

    func members(reference: Double, offset: Double) -> [Int] {
      let normal = (cos(reference), sin(reference))
      return candidates.indices.filter { index in
        guard remaining[index] else { return false }
        let candidate = candidates[index]
        let along = candidate.cx * normal.0 + candidate.cz * normal.1
        return angularDistance(candidate.theta, reference) <= angleTolerance
          && abs(along - offset) <= offsetTolerance
      }
    }

    while let seed = candidates.indices.filter({ remaining[$0] }).max(by: { candidates[$0].area < candidates[$1].area }) {
      var reference = fold(candidates[seed].theta)
      var normal = (cos(reference), sin(reference))
      var group = members(
        reference: reference, offset: candidates[seed].cx * normal.0 + candidates[seed].cz * normal.1)
      if group.isEmpty { group = [seed] }

      // Refit by area; angles averaged as doubled vectors so a wall straddling
      // 0° and 180° averages to itself.
      var sinSum = 0.0, cosSum = 0.0, weight = 0.0
      for index in group {
        sinSum += candidates[index].area * sin(2 * candidates[index].theta)
        cosSum += candidates[index].area * cos(2 * candidates[index].theta)
        weight += candidates[index].area
      }
      reference = fold(atan2(sinSum, cosSum) / 2)
      normal = (cos(reference), sin(reference))
      var offset = 0.0
      for index in group {
        offset += candidates[index].area * (candidates[index].cx * normal.0 + candidates[index].cz * normal.1)
      }
      offset /= max(weight, 1e-12)
      group = members(reference: reference, offset: offset)
      if !group.contains(seed) { group.append(seed) }
      for index in group { remaining[index] = false }

      let total = group.reduce(0.0) { $0 + candidates[$1].area }
      guard total >= 0.05 else { continue }
      let tangent = (-sin(reference), cos(reference))
      var low = Double.infinity, high = -Double.infinity, bottom = Double.infinity
      var refitOffset = 0.0
      for index in group {
        refitOffset += candidates[index].area * (candidates[index].cx * normal.0 + candidates[index].cz * normal.1)
        for corner in candidates[index].corners {
          let along = corner.x * tangent.0 + corner.z * tangent.1
          low = min(low, along)
          high = max(high, along)
          bottom = min(bottom, corner.y)
        }
      }
      refitOffset /= max(total, 1e-12)
      walls.append(Wall(azimuth: reference, offset: refitOffset, area: total, extent: (low, high), bottom: bottom))
    }
    return walls.sorted { $0.area > $1.area }
  }

  /// Where two walls' lines cross, when they are at least 30° apart and both
  /// walls' faces run to within 30 cm of the crossing: a corner, not a ghost.
  static func intersection(_ a: Wall, _ b: Wall) -> (x: Double, z: Double)? {
    var delta = abs(a.azimuth - b.azimuth) * 180 / .pi
    delta = min(delta, 180 - delta)
    guard delta >= 30 else { return nil }
    let (a1, a2) = a.normal
    let (b1, b2) = b.normal
    let determinant = a1 * b2 - a2 * b1
    guard abs(determinant) > 1e-9 else { return nil }
    let x = (a.offset * b2 - a2 * b.offset) / determinant
    let z = (a1 * b.offset - a.offset * b1) / determinant
    let reach = 0.3
    for wall in [a, b] {
      let (t1, t2) = wall.tangent
      let along = x * t1 + z * t2
      let gap = max(0, wall.extent.low - along, along - wall.extent.high)
      guard gap <= reach else { return nil }
    }
    return (x, z)
  }

  /// The floor's height near the tap: the median of floor faces' centroids,
  /// else the bottom of the walls, else the tap's own height.
  static func floorY(_ faces: [Face], walls: [Wall], tap: Vector3) -> (y: Double, source: String) {
    let heights = faces.filter { $0.classification == floorClass }
      .map { ($0.a.y + $0.b.y + $0.c.y) / 3 }.sorted()
    if !heights.isEmpty {
      let middle = heights.count / 2
      let median = heights.count % 2 == 1 ? heights[middle] : (heights[middle - 1] + heights[middle]) / 2
      return (median, "floor-faces")
    }
    if let bottom = walls.map({ $0.bottom }).min(), bottom.isFinite {
      return (bottom, "wall-bottoms")
    }
    return (tap.y, "tap")
  }

  // MARK: - Geometry

  static func normalAndArea(_ face: Face) -> (Double, Double, Double, Double) {
    let ux = face.b.x - face.a.x, uy = face.b.y - face.a.y, uz = face.b.z - face.a.z
    let vx = face.c.x - face.a.x, vy = face.c.y - face.a.y, vz = face.c.z - face.a.z
    let cx = uy * vz - uz * vy
    let cy = uz * vx - ux * vz
    let cz = ux * vy - uy * vx
    let length = (cx * cx + cy * cy + cz * cz).squareRoot()
    guard length > 0 else { return (0, 0, 0, 0) }
    return (cx / length, cy / length, cz / length, length / 2)
  }

  /// An azimuth folded to [0, π): a wall has no front.
  static func fold(_ theta: Double) -> Double {
    var value = theta.truncatingRemainder(dividingBy: .pi)
    if value < 0 { value += .pi }
    if abs(value - .pi) < 1e-9 { value = 0 }
    return value
  }

  static func angularDistance(_ theta: Double, _ reference: Double) -> Double {
    let delta = abs(fold(theta) - fold(reference))
    return min(delta, .pi - delta)
  }
}
