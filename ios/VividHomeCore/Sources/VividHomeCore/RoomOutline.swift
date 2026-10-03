import Foundation

/// A room's corners on the plan (ADR-0031, design §2): the plan's statement of
/// where the corners are, so a tap in the field can be asked for by name and
/// placed against it.
///
/// Corners are named from the outline's geometry, never typed: the compass
/// label the capture protocol already uses (`corner-nw`, `corner-ne`, ...),
/// from each corner's bearing out of the room's centre, with a numeric suffix
/// when a room has two corners in one quadrant (`corner-nw2`). The same name is
/// what the HUD asks for and what `landmarks.jsonl` records, so a landmark
/// label in a session is a key into the outline. On the drawing +x is right
/// and +y is down, so north is up the page, which is how plans are read.
public enum RoomOutline {
  public static let minimumCorners = 3

  /// Names for the corners of `points`, in the same order.
  public static func cornerNames(for points: [[Double]]) -> [String] {
    guard points.count >= minimumCorners, points.allSatisfy({ $0.count == 2 }) else { return [] }
    let cx = points.map { $0[0] }.reduce(0, +) / Double(points.count)
    let cy = points.map { $0[1] }.reduce(0, +) / Double(points.count)
    var seen: [String: Int] = [:]
    return points.map { point in
      let quadrant = (point[1] <= cy ? "n" : "s") + (point[0] <= cx ? "w" : "e")
      let count = (seen[quadrant] ?? 0) + 1
      seen[quadrant] = count
      return count == 1 ? "corner-\(quadrant)" : "corner-\(quadrant)\(count)"
    }
  }

  /// Whether the points make an outline: enough of them, each inside the
  /// raster, none repeated back to back.
  public static func isValid(_ points: [[Double]], in size: (width: Int, height: Int)) -> Bool {
    guard points.count >= minimumCorners else { return false }
    for (index, point) in points.enumerated() {
      guard point.count == 2, point[0] >= 0, point[1] >= 0,
        point[0] <= Double(size.width), point[1] <= Double(size.height)
      else { return false }
      if index > 0, point == points[index - 1] { return false }
    }
    return points.first != points.last
  }
}

extension PlanRoom {
  /// The corner names of this room's outline, or none when it has no outline.
  public var cornerNames: [String] {
    outline.map(RoomOutline.cornerNames(for:)) ?? []
  }
}

extension PlanFile {
  /// Record where a placed room's corners are on the drawing, in order.
  ///
  /// Refused, returning false, when the room is not placed or the points do
  /// not make an outline; nothing is written in that case.
  @discardableResult
  public mutating func outline(
    room: String, points: [[Double]], in size: (width: Int, height: Int), at date: Date = Date()
  ) -> Bool {
    guard let index = rooms.firstIndex(where: { $0.room == room }),
      RoomOutline.isValid(points, in: size)
    else { return false }
    rooms[index].outline = points
    rooms[index].outlinedAt = PlanRoom.iso8601(date)
    return true
  }

  public mutating func clearOutline(room: String) {
    guard let index = rooms.firstIndex(where: { $0.room == room }) else { return }
    rooms[index].outline = nil
    rooms[index].outlinedAt = nil
  }

  /// A room's corners in house metres, by name, for the live solve: the plan
  /// pixel of each corner through the calibration. Nil when the level is not
  /// calibrated or the room has no outline.
  public func houseCorners(of room: String) -> [(label: String, x: Double, z: Double)]? {
    guard isCalibrated, let placement = placement(of: room), let outline = placement.outline
    else { return nil }
    let names = RoomOutline.cornerNames(for: outline)
    guard names.count == outline.count else { return nil }
    var out: [(label: String, x: Double, z: Double)] = []
    for (name, point) in zip(names, outline) {
      guard let house = planToHouse(u: point[0], v: point[1]) else { return nil }
      out.append((name, house.x, house.z))
    }
    return out
  }
}
