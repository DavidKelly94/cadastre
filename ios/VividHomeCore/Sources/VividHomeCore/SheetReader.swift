import Foundation

/// Reading a drawing's scale and rooms off the sheet itself (ADR-0032), so the
/// owner confirms what the architect already drew instead of tapping it in.
///
/// Three things are read. The **scale**, from the title block's note and the
/// page's printed size, then tested against the sheet's own dimensions. The
/// **rooms**, from their labels. Each room's **outline**, by filling out from
/// its label to the walls: architects fill their walls and lay doors on top,
/// so with only the wall shapes kept a doorway is already closed.
///
/// What comes back is a proposal. Nothing is written until the owner has
/// looked at it, and a sheet this cannot read (a scan, walls drawn as bare
/// lines) simply proposes less and leaves the manual screens to do the rest.
public enum SheetReader {
  /// The scale the sheet states and how well its dimensions agree.
  public struct ScaleFinding: Equatable, Sendable {
    public enum Check: Equatable, Sendable {
      /// Most of the dimensions that could be measured match the note.
      case agrees
      /// They do not: the page was probably printed to fit, or the note is
      /// for a detail. The scale must not be used.
      case disagrees
      /// Too few dimensions could be measured to say.
      case unchecked
    }

    /// The note as printed, e.g. `1/4" = 1'-0"`.
    public var note: String
    /// Real distance over paper distance.
    public var ratio: Double
    public var metresPerPoint: Double
    public var agreement: SheetScale.Agreement
    public var check: Check
  }

  public struct Room: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
      /// Enclosed by walls: the outline can be used as it is.
      case outlined
      /// Shares its space with other labelled rooms, with no wall between.
      case openPlan
      /// The fill escaped the building: the label sits outside the walls, or
      /// the walls do not close.
      case notEnclosed
    }

    /// As printed, e.g. `M BEDROOM`.
    public var name: String
    /// What the app calls it, e.g. `m-bedroom`; unique on the sheet.
    public var slug: String
    /// The room number printed with the name, when there is one.
    public var tag: String?
    /// Where the label sits, in sheet points: the room's pin.
    public var label: Sheet.Point
    /// The corners in order, in sheet points; empty when not enclosed.
    public var outline: [Sheet.Point]
    public var status: Status
    /// Floor area inside the outline, in square points.
    public var areaPoints: Double
    /// The other rooms in the same space, by slug, for an open plan.
    public var sharedWith: [String]
  }

  public struct Proposal: Equatable, Sendable {
    public var scale: ScaleFinding?
    public var rooms: [Room]
    /// The filled shapes taken as walls, and their bounding box.
    public var wallShapes: Int
    public var wallBounds: Sheet.Box?
    /// What the sheet held, so a screenshot of the confirm screen says what
    /// the reader saw.
    public var textRuns: Int
    public var dimensions: Int
  }

  /// Corners beyond this are not a room anyone taps their way round.
  public static let maximumCorners = 16

  public static func read(_ sheet: Sheet) -> Proposal {
    let runs = Sheet.runs(from: sheet.glyphs)
    let scale = findScale(runs: runs, segments: sheet.segments)
    let labels = roomLabels(in: runs)
    let walls = wallPolygons(in: sheet.fills)
    let dimensions = runs.filter { SheetScale.dimension(from: $0.text) != nil }.count

    var proposal = Proposal(
      scale: scale, rooms: [], wallShapes: walls.count, wallBounds: bounds(of: walls),
      textRuns: runs.count, dimensions: dimensions)

    guard let wallBounds = proposal.wallBounds, !labels.isEmpty else {
      proposal.rooms = labels.map {
        Room(
          name: $0.name, slug: $0.slug, tag: $0.tag, label: $0.point, outline: [],
          status: .notEnclosed, areaPoints: 0, sharedWith: [])
      }
      return proposal
    }

    // Half-point cells: a 4 inch wall at 1/4 inch scale is six points, twelve
    // cells. Coarser on a sheet too large to hold at that grain.
    let margin = 12.0
    let spanX = wallBounds.width + 2 * margin, spanY = wallBounds.height + 2 * margin
    let grain = spanX * spanY * 4 > 40_000_000 ? 1.0 : 2.0
    var grid = Grid(
      originX: wallBounds.minX - margin, originY: wallBounds.minY - margin,
      width: Int((spanX * grain).rounded(.up)), height: Int((spanY * grain).rounded(.up)),
      grain: grain)
    for polygon in walls { grid.fill(polygon) }
    grid.thicken()

    // A wall end sticking into a room is not a corner of it. Stubs up to
    // about 18 cm thick are closed over before the outline is traced.
    let stub = scale.map { 0.09 / $0.metresPerPoint } ?? 5.0
    let radius = max(2, Int((stub * grain).rounded()))

    var regionOf: [Int: Int] = [:]  // label index -> region id
    var regions: [Int: Region] = [:]
    for (index, label) in labels.enumerated() {
      guard let seed = grid.freeCell(near: label.point) else { continue }
      let existing = grid.region(at: seed)
      if existing > 0 {
        regionOf[index] = existing
      } else {
        let id = regions.count + 1
        regions[id] = grid.flood(from: seed, id: id)
        regionOf[index] = id
      }
    }

    var outlines: [Int: [Sheet.Point]] = [:]
    for (id, region) in regions where !region.escapes {
      outlines[id] = grid.outline(of: region, id: id, closing: radius, scale: scale)
    }

    var sharing: [Int: [Int]] = [:]
    for (index, id) in regionOf { sharing[id, default: []].append(index) }

    proposal.rooms = labels.enumerated().map { index, label in
      guard let id = regionOf[index], let region = regions[id], !region.escapes,
        let outline = outlines[id], outline.count >= RoomOutline.minimumCorners
      else {
        return Room(
          name: label.name, slug: label.slug, tag: label.tag, label: label.point, outline: [],
          status: .notEnclosed, areaPoints: 0, sharedWith: [])
      }
      let others = (sharing[id] ?? []).filter { $0 != index }.sorted().map { labels[$0].slug }
      return Room(
        name: label.name, slug: label.slug, tag: label.tag, label: label.point, outline: outline,
        status: others.isEmpty ? .outlined : .openPlan,
        areaPoints: Double(region.cells) / (grain * grain), sharedWith: others)
    }
    return proposal
  }

  // MARK: - Scale

  static func findScale(runs: [Sheet.Run], segments: [Sheet.Segment]) -> ScaleFinding? {
    var best: ScaleFinding?
    var seen: Set<Double> = []
    for run in runs where !run.vertical {
      guard let ratio = SheetScale.ratio(from: run.text), seen.insert(ratio).inserted else { continue }
      let metresPerPoint = SheetScale.metresPerPoint(ratio: ratio)
      let agreement = SheetScale.agreement(runs: runs, segments: segments, metresPerPoint: metresPerPoint)
      let check: ScaleFinding.Check
      if agreement.tested < 2 {
        check = .unchecked
      } else if agreement.agreeing >= 2, Double(agreement.agreeing) >= 0.6 * Double(agreement.tested) {
        check = .agrees
      } else {
        check = .disagrees
      }
      let finding = ScaleFinding(
        note: run.text, ratio: ratio, metresPerPoint: metresPerPoint, agreement: agreement, check: check)
      // A sheet can carry a second note for a detail: keep the one its
      // dimensions bear out best.
      if best == nil || agreement.agreeing > (best?.agreement.agreeing ?? 0) { best = finding }
    }
    return best
  }

  // MARK: - Room labels

  struct Label: Equatable {
    var name: String
    var slug: String
    var tag: String?
    var point: Sheet.Point
  }

  /// Words printed on a plan that are never a room.
  private static let notRooms: Set<String> = [
    "SCALE", "PLAN", "NORTH", "DATE", "DRAWN", "CHECKED", "SHEET", "REV", "REVISION", "PROJECT",
    "CLIENT", "ARCHITECT", "DRAWING", "TITLE", "NOTES", "GENERAL", "TYP", "TYPICAL", "STATUS",
    "AREAS", "TOTAL", "CONDITIONED", "UNCONDITIONED", "DESCRIPTION",
  ]

  /// What a room is usually called, for sheets that print no room numbers.
  private static let roomWords: [String] = [
    "ROOM", "BED", "BATH", "KITCHEN", "LIVING", "DINING", "OFFICE", "GARAGE", "CLOSET", "PANTRY",
    "LAUNDRY", "ENTRY", "HALL", "FOYER", "STUDY", "DEN", "MUD", "POWDER", "WIC", "UTILITY", "MECH",
    "STORAGE", "FAMILY", "GREAT", "NOOK", "LOFT", "BONUS", "GYM", "REC", "LOUNGE", "NURSERY",
  ]

  static func isRoomName(_ text: String) -> Bool {
    guard text.count >= 3, text.count <= 28, SheetScale.dimension(from: text) == nil else { return false }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .&/-")
    guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
    let letters = text.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
    guard letters >= 3 else { return false }
    let words = text.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" }).map(String.init)
    return !words.contains { notRooms.contains($0.trimmingCharacters(in: CharacterSet(charactersIn: ".:"))) }
  }

  static func isTag(_ text: String) -> Bool {
    guard text.count >= 2, text.count <= 5 else { return false }
    var digits = 0
    for (offset, character) in text.enumerated() {
      if character.isNumber {
        digits += 1
      } else if !(character.isLetter && character.isUppercase && offset == text.count - 1) {
        return false
      }
    }
    return digits >= 2
  }

  /// The rooms a sheet labels. A name with a room number boxed above it is
  /// the strongest sign there is, so when a sheet numbers its rooms only
  /// numbered names count; otherwise names are kept when they read as a room.
  static func roomLabels(in runs: [Sheet.Run]) -> [Label] {
    let flat = runs.filter { !$0.vertical }
    let tags = flat.filter { isTag($0.text) }
    let names = flat.filter { isRoomName($0.text) }

    // Each number goes to the nearest name below it.
    var byTag: [String: (score: Double, name: Sheet.Run, tag: Sheet.Run)] = [:]
    for tag in tags {
      var best: (score: Double, name: Sheet.Run)?
      for name in names {
        let below = name.box.minY - tag.box.maxY
        let aside = abs(name.box.midX - tag.box.midX)
        guard below >= -2, below <= max(22, 3 * name.box.height),
          aside <= max(40, 0.5 * name.box.width + 10)
        else { continue }
        let score = below + 2 * aside
        if best == nil || score < best!.score { best = (score, name) }
      }
      guard let best else { continue }
      if let held = byTag[tag.text], held.score <= best.score { continue }
      byTag[tag.text] = (best.score, best.name, tag)
    }
    // And each name keeps only its nearest number.
    var byName: [String: (score: Double, name: Sheet.Run, tag: Sheet.Run)] = [:]
    for pair in byTag.values {
      let key = "\(pair.name.box.minX),\(pair.name.box.minY)"
      if let held = byName[key], held.score <= pair.score { continue }
      byName[key] = pair
    }

    var found: [(name: String, tag: String?, point: Sheet.Point)] = []
    if byName.count >= 3 {
      for pair in byName.values {
        // The pin goes on the number: it sits in the room's open floor,
        // where the name can run under furniture or over a wall.
        found.append((pair.name.text, pair.tag.text, Sheet.Point(pair.tag.box.midX, pair.tag.box.midY)))
      }
      found.sort { ($0.tag ?? "") == ($1.tag ?? "") ? $0.name < $1.name : ($0.tag ?? "") < ($1.tag ?? "") }
    } else {
      for name in names where roomWords.contains(where: { name.text.contains($0) }) {
        found.append((name.text, nil, Sheet.Point(name.box.midX, name.box.midY)))
      }
      found.sort { $0.point.y == $1.point.y ? $0.point.x < $1.point.x : $0.point.y < $1.point.y }
    }

    var used: [String: Int] = [:]
    var out: [Label] = []
    for entry in found {
      guard let base = SessionID.slug(entry.name) else { continue }
      let count = (used[base] ?? 0) + 1
      used[base] = count
      var slug = count == 1 ? base : "\(base)-\(count)"
      if SessionID.slug(slug) != slug { slug = SessionID.slug(slug) ?? base }
      out.append(Label(name: entry.name, slug: slug, tag: entry.tag, point: entry.point))
    }
    return out
  }

  // MARK: - Walls

  /// The filled shapes that are walls: of the colours a sheet fills with, the
  /// one covering the most area in long thin shapes. White is paper, and a
  /// compact fill is a pad, a column or an arrowhead, not a wall.
  static func wallPolygons(in fills: [Sheet.Fill]) -> [[Sheet.Point]] {
    var groups: [String: (area: Double, polygons: [[Sheet.Point]])] = [:]
    for fill in fills {
      guard min(fill.red, fill.green, fill.blue) < 0.9 else { continue }
      let key = [fill.red, fill.green, fill.blue].map { String(Int(($0 * 20).rounded())) }
        .joined(separator: ",")
      for polygon in fill.polygons where polygon.count >= 3 {
        let area = abs(signedArea(polygon))
        let around = perimeter(polygon)
        guard area > 1, around > 0 else { continue }
        // 1 for a circle, 0.79 for a square, small for anything long and thin.
        let compactness = 4 * Double.pi * area / (around * around)
        var group = groups[key] ?? (0, [])
        if compactness < 0.5 { group.area += area }
        group.polygons.append(polygon)
        groups[key] = group
      }
    }
    guard let best = groups.values.max(by: { $0.area < $1.area }), best.area > 0 else { return [] }
    return best.polygons
  }

  static func signedArea(_ polygon: [Sheet.Point]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      let a = polygon[index], b = polygon[(index + 1) % polygon.count]
      sum += a.x * b.y - b.x * a.y
    }
    return sum / 2
  }

  static func perimeter(_ polygon: [Sheet.Point]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      let a = polygon[index], b = polygon[(index + 1) % polygon.count]
      sum += ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
    return sum
  }

  static func bounds(of polygons: [[Sheet.Point]]) -> Sheet.Box? {
    var box: Sheet.Box?
    for polygon in polygons {
      for point in polygon {
        let here = Sheet.Box(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y)
        box = box?.union(here) ?? here
      }
    }
    return box
  }

  // MARK: - The grid

  struct Region {
    var cells = 0
    var minX = Int.max
    var minY = Int.max
    var maxX = Int.min
    var maxY = Int.min
    /// Reached the edge of the grid: outside the building.
    var escapes = false
  }

  /// The walls as cells, and the rooms flooded between them. A cell is
  /// `wall` (-1), free (0), or the id of the region that reached it.
  struct Grid {
    var originX: Double
    var originY: Double
    var width: Int
    var height: Int
    /// Cells per point.
    var grain: Double
    var cells: [Int16]

    init(originX: Double, originY: Double, width: Int, height: Int, grain: Double) {
      self.originX = originX
      self.originY = originY
      self.width = max(1, width)
      self.height = max(1, height)
      self.grain = grain
      cells = Array(repeating: 0, count: self.width * self.height)
    }

    /// Mark the cells whose centres are inside the polygon, even-odd.
    mutating func fill(_ polygon: [Sheet.Point]) {
      guard polygon.count >= 3 else { return }
      let ys = polygon.map { $0.y }
      let first = max(0, Int(((ys.min()! - originY) * grain - 0.5).rounded(.up)))
      let last = min(height - 1, Int(((ys.max()! - originY) * grain - 0.5).rounded(.down)))
      guard first <= last else { return }
      var crossings: [Double] = []
      for row in first...last {
        let y = originY + (Double(row) + 0.5) / grain
        crossings.removeAll(keepingCapacity: true)
        for index in polygon.indices {
          let a = polygon[index], b = polygon[(index + 1) % polygon.count]
          if (a.y <= y && y < b.y) || (b.y <= y && y < a.y) {
            crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
          }
        }
        crossings.sort()
        var pair = 0
        while pair + 1 < crossings.count {
          let from = max(0, Int(((crossings[pair] - originX) * grain - 0.5).rounded(.up)))
          let to = min(width - 1, Int(((crossings[pair + 1] - originX) * grain - 0.5).rounded(.up)) - 1)
          if from <= to {
            for column in from...to { cells[row * width + column] = -1 }
          }
          pair += 2
        }
      }
    }

    /// Grow the walls by one cell, so a hairline seam between two wall shapes
    /// that abut is not a way out of a room.
    mutating func thicken() {
      let before = cells
      for row in 0..<height {
        for column in 0..<width where before[row * width + column] == 0 {
          var near = false
          for dy in -1...1 where !near {
            let y = row + dy
            guard y >= 0, y < height else { continue }
            for dx in -1...1 {
              let x = column + dx
              if x >= 0, x < width, before[y * width + x] == -1 {
                near = true
                break
              }
            }
          }
          if near { cells[row * width + column] = -1 }
        }
      }
    }

    func cell(of point: Sheet.Point) -> (x: Int, y: Int)? {
      let x = Int(((point.x - originX) * grain).rounded(.down))
      let y = Int(((point.y - originY) * grain).rounded(.down))
      guard x >= 0, y >= 0, x < width, y < height else { return nil }
      return (x, y)
    }

    /// The cell under a label, or the nearest one that is not wall: a label
    /// can sit on a wall line when the room is small.
    func freeCell(near point: Sheet.Point) -> (x: Int, y: Int)? {
      guard let start = cell(of: point) else { return nil }
      if cells[start.y * width + start.x] != -1 { return start }
      for reach in 1...12 {
        for dy in -reach...reach {
          for dx in -reach...reach where max(abs(dx), abs(dy)) == reach {
            let x = start.x + dx, y = start.y + dy
            if x >= 0, y >= 0, x < width, y < height, cells[y * width + x] != -1 { return (x, y) }
          }
        }
      }
      return nil
    }

    func region(at cell: (x: Int, y: Int)) -> Int {
      Int(cells[cell.y * width + cell.x])
    }

    /// Fill outward from a cell to the walls, a row span at a time.
    mutating func flood(from seed: (x: Int, y: Int), id: Int) -> Region {
      var region = Region()
      let mark = Int16(id)
      var stack: [(x: Int, y: Int)] = [seed]
      while let next = stack.popLast() {
        guard cells[next.y * width + next.x] == 0 else { continue }
        var left = next.x
        while left > 0, cells[next.y * width + left - 1] == 0 { left -= 1 }
        var right = next.x
        while right < width - 1, cells[next.y * width + right + 1] == 0 { right += 1 }
        for column in left...right { cells[next.y * width + column] = mark }
        region.cells += right - left + 1
        region.minX = min(region.minX, left)
        region.maxX = max(region.maxX, right)
        region.minY = min(region.minY, next.y)
        region.maxY = max(region.maxY, next.y)
        if left == 0 || right == width - 1 || next.y == 0 || next.y == height - 1 {
          region.escapes = true
        }
        for row in [next.y - 1, next.y + 1] where row >= 0 && row < height {
          var column = left
          while column <= right {
            if cells[row * width + column] == 0 {
              stack.append((column, row))
              while column <= right, cells[row * width + column] == 0 { column += 1 }
            } else {
              column += 1
            }
          }
        }
      }
      return region
    }

    /// The region's corners, in sheet points, clockwise from the top-left.
    func outline(of region: Region, id: Int, closing radius: Int, scale: ScaleFinding?) -> [Sheet.Point] {
      let pad = radius + 2
      let w = region.maxX - region.minX + 1 + 2 * pad
      let h = region.maxY - region.minY + 1 + 2 * pad
      var bitmap = [Bool](repeating: false, count: w * h)
      let mark = Int16(id)
      for row in region.minY...region.maxY {
        for column in region.minX...region.maxX where cells[row * width + column] == mark {
          bitmap[(row - region.minY + pad) * w + (column - region.minX + pad)] = true
        }
      }
      // Close over wall stubs: grow, then shrink by the same amount.
      bitmap = Grid.spread(bitmap, width: w, height: h, radius: radius, value: true)
      bitmap = Grid.spread(bitmap, width: w, height: h, radius: radius, value: false)

      let loop = Grid.trace(bitmap, width: w, height: h)
      // Drop the steps a slanted or slightly jogged wall leaves: anything
      // within about 4 cm of the straight line between its neighbours.
      let slack = max(1.5, (scale.map { 0.04 / $0.metresPerPoint } ?? 2.0) * grain)
      let corners = Grid.simplify(loop, tolerance: slack)
      return corners.map {
        Sheet.Point(
          originX + Double($0.x - pad + region.minX) / grain,
          originY + Double($0.y - pad + region.minY) / grain)
      }
    }

    /// Grow the cells holding `value` by `radius` in every direction, as a
    /// square: a row pass then a column pass. With `true` this thickens the
    /// shape; with `false` it thins it by the same rule.
    static func spread(_ bitmap: [Bool], width: Int, height: Int, radius: Int, value: Bool) -> [Bool] {
      var rows = bitmap
      for row in 0..<height {
        // Left to right, then right to left, carrying the nearest `value` cell.
        var nearest = Int.min / 2
        for column in 0..<width {
          if bitmap[row * width + column] == value { nearest = column }
          if column - nearest <= radius { rows[row * width + column] = value }
        }
        nearest = Int.max / 2
        for column in stride(from: width - 1, through: 0, by: -1) {
          if bitmap[row * width + column] == value { nearest = column }
          if nearest - column <= radius { rows[row * width + column] = value }
        }
      }
      var out = rows
      for column in 0..<width {
        var nearest = Int.min / 2
        for row in 0..<height {
          if rows[row * width + column] == value { nearest = row }
          if row - nearest <= radius { out[row * width + column] = value }
        }
        nearest = Int.max / 2
        for row in stride(from: height - 1, through: 0, by: -1) {
          if rows[row * width + column] == value { nearest = row }
          if nearest - row <= radius { out[row * width + column] = value }
        }
      }
      return out
    }

    /// Walk the outer edge of the set cells, keeping them on the right, and
    /// return the grid corners where the walk turns, starting at the top-left
    /// one. Cells that touch only at a corner are not joined.
    static func trace(_ bitmap: [Bool], width: Int, height: Int) -> [(x: Int, y: Int)] {
      func set(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && bitmap[y * width + x]
      }
      guard let start = bitmap.firstIndex(of: true) else { return [] }
      // The top-left corner of the first set cell in reading order, heading
      // east along its top edge.
      let origin = (x: start % width, y: start / width)
      let steps = [(1, 0), (0, 1), (-1, 0), (0, -1)]  // east, south, west, north
      var at = origin
      var heading = 0
      var corners: [(x: Int, y: Int)] = []
      var first = true
      var budget = 8 * (width + 2) * (height + 2)
      while budget > 0 {
        budget -= 1
        // The two cells ahead of this grid corner: the one on the walk's
        // right, which is set while the edge runs on, and the one on its left.
        let right: (Int, Int)
        let left: (Int, Int)
        switch heading {
        case 0: right = (at.x, at.y); left = (at.x, at.y - 1)
        case 1: right = (at.x - 1, at.y); left = (at.x, at.y)
        case 2: right = (at.x - 1, at.y - 1); left = (at.x - 1, at.y)
        default: right = (at.x, at.y - 1); left = (at.x - 1, at.y - 1)
        }
        if !set(right.0, right.1) {
          corners.append(at)
          heading = (heading + 1) % 4
        } else if set(left.0, left.1) {
          corners.append(at)
          heading = (heading + 3) % 4
        }
        if !first, at.x == origin.x, at.y == origin.y, heading == 0 { break }
        first = false
        at = (at.x + steps[heading].0, at.y + steps[heading].1)
      }
      // The walk ends by turning at the origin, so that corner is last.
      if let last = corners.last, last.x == origin.x, last.y == origin.y {
        corners.insert(corners.removeLast(), at: 0)
      }
      return corners
    }

    /// Remove corners that lie within `tolerance` cells of the line between
    /// the corners kept either side of them.
    static func simplify(_ loop: [(x: Int, y: Int)], tolerance: Double) -> [(x: Int, y: Int)] {
      guard loop.count > 4 else { return loop }
      // Anchor on the first corner and the one furthest from it, and reduce
      // each half between them.
      var far = 0
      var farthest = -1.0
      for (index, point) in loop.enumerated() {
        let d = Double((point.x - loop[0].x) * (point.x - loop[0].x) + (point.y - loop[0].y) * (point.y - loop[0].y))
        if d > farthest {
          farthest = d
          far = index
        }
      }
      func reduce(_ points: [(x: Int, y: Int)]) -> [(x: Int, y: Int)] {
        guard points.count > 2 else { return points }
        let a = points[0], b = points[points.count - 1]
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let length = (dx * dx + dy * dy).squareRoot()
        var worst = 0
        var distance = -1.0
        for index in 1..<(points.count - 1) {
          let px = Double(points[index].x - a.x), py = Double(points[index].y - a.y)
          let d = length == 0 ? (px * px + py * py).squareRoot() : abs(px * dy - py * dx) / length
          if d > distance {
            distance = d
            worst = index
          }
        }
        if distance <= tolerance { return [a, b] }
        let head = reduce(Array(points[0...worst]))
        let tail = reduce(Array(points[worst...]))
        return head.dropLast() + tail
      }
      let first = reduce(Array(loop[0...far]))
      let second = reduce(Array(loop[far...]) + [loop[0]])
      return Array(first.dropLast() + second.dropLast())
    }
  }
}
