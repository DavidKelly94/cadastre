import Foundation

/// The leave check (ADR-0031, design §5): what the review screen says about
/// the capture before the owner walks out, written into the manifest at Stop
/// as the additive `field_check` object so the PC can show the same lines
/// without redoing them.
///
/// Numbers, not sentences, in the file; `lines` makes the sentences, the same
/// ones on the phone and wherever the file is read by this package.
public struct FieldCheck: Codable, Equatable, Sendable {
  /// Whether the capture is on the plan, and how well.
  public struct Placement: Codable, Equatable, Sendable {
    /// `placed`, `check` or `not_placed` from the fit; `untapped` when the
    /// room was guided but fewer than two corners were tapped; `free` when
    /// the room had no outline to be placed against.
    public var status: String
    public var rmsM: Double?
    /// Corners tapped.
    public var corners: Int

    public init(status: String, rmsM: Double? = nil, corners: Int) {
      self.status = status
      self.rmsM = rmsM
      self.corners = corners
    }

    enum CodingKeys: String, CodingKey {
      case status
      case rmsM = "rms_m"
      case corners
    }
  }

  /// The walls of the outline and what the keyframes photographed of them.
  /// Absent when the capture is not placed: without a placement the keyframes
  /// cannot be put against the outline.
  public struct Walls: Codable, Equatable, Sendable {
    public struct Gap: Codable, Equatable, Sendable {
      /// The wall by its corners: `corner-nw->corner-ne`.
      public var wall: String
      /// Metres along the wall from its first corner.
      public var fromM: Double
      public var lengthM: Double

      public init(wall: String, fromM: Double, lengthM: Double) {
        self.wall = wall
        self.fromM = fromM
        self.lengthM = lengthM
      }

      enum CodingKeys: String, CodingKey {
        case wall
        case fromM = "from_m"
        case lengthM = "length_m"
      }
    }

    /// Walls at or above `photographedFraction`.
    public var photographed: Int
    public var total: Int
    /// The largest unphotographed run of each wall below the bar, worst first.
    public var gaps: [Gap]

    public init(photographed: Int, total: Int, gaps: [Gap]) {
      self.photographed = photographed
      self.total = total
      self.gaps = gaps
    }
  }

  /// The stills checklist for the pass's phases.
  public struct Stills: Codable, Equatable, Sendable {
    public var done: Int
    public var total: Int
    /// Item ids not yet photographed, in list order.
    public var missing: [String]

    public init(done: Int, total: Int, missing: [String]) {
      self.done = done
      self.total = total
      self.missing = missing
    }
  }

  /// One line of the review screen: green when `ok`, orange otherwise.
  public struct Line: Equatable, Sendable {
    public var text: String
    public var ok: Bool
  }

  /// A wall counts as photographed from this fraction, the inset's green band.
  public static let photographedFraction = 0.7

  public var placement: Placement
  public var walls: Walls?
  public var stills: Stills
  public var checkedAt: String
  /// The earlier captures of the same room and trades whose keyframes and
  /// stills were counted with this one (design §6): a top-up's check describes
  /// the room. Empty for a first capture.
  public var together: [String]

  public init(placement: Placement, walls: Walls?, stills: Stills, checkedAt: String, together: [String] = []) {
    self.placement = placement
    self.walls = walls
    self.stills = stills
    self.checkedAt = checkedAt
    self.together = together
  }

  enum CodingKeys: String, CodingKey {
    case placement
    case walls
    case stills
    case checkedAt = "checked_at"
    case together
  }

  /// From the live placement and the walls' coverage as the HUD had them.
  public static func make(
    guided: Bool, cornersTapped: Int, placement: PlanAlignment.Solution?,
    coverage: [WallCoverage.Wall]?, checklist: [StillsChecklist.Item], taken: [String?],
    checkedAt: String, together: [String] = []
  ) -> FieldCheck {
    let placed: Placement
    if !guided {
      placed = Placement(status: "free", corners: cornersTapped)
    } else if let placement {
      let status: String
      switch placement.verdict {
      case .placed: status = "placed"
      case .check: status = "check"
      case .notPlaced: status = "not_placed"
      }
      placed = Placement(status: status, rmsM: placement.rms, corners: cornersTapped)
    } else {
      placed = Placement(status: "untapped", corners: cornersTapped)
    }

    var walls: Walls?
    if let coverage, let placement, placement.verdict != .notPlaced {
      var gaps: [(fraction: Double, gap: Walls.Gap)] = []
      for wall in coverage where wall.fraction < photographedFraction {
        guard let widest = wall.gaps.max(by: { $0.length < $1.length }) else { continue }
        gaps.append(
          (wall.fraction,
           Walls.Gap(
             wall: "\(wall.start)->\(wall.end)", fromM: decimetres(widest.from), lengthM: decimetres(widest.length))))
      }
      gaps.sort { $0.fraction < $1.fraction }
      walls = Walls(
        photographed: coverage.filter { $0.fraction >= photographedFraction }.count,
        total: coverage.count, gaps: gaps.map(\.gap))
    }

    let progress = StillsChecklist.progress(items: checklist, taken: taken)
    return FieldCheck(
      placement: placed, walls: walls,
      stills: Stills(done: progress.done, total: progress.total, missing: progress.missing.map(\.id)),
      checkedAt: checkedAt, together: together)
  }

  /// The three lines, in the order the review screen shows them.
  public var lines: [Line] {
    [placementLine, wallsLine, stillsLine]
  }

  public var placementLine: Line {
    let centimetres = Int(((placement.rmsM ?? 0) * 100).rounded())
    switch placement.status {
    case "placed": return Line(text: "Placed on the plan, \(centimetres) cm", ok: true)
    case "check": return Line(text: "Check the corners: \(centimetres) cm off", ok: false)
    case "not_placed": return Line(text: "Not placed: \(centimetres) cm off, a corner is wrong", ok: false)
    case "untapped": return Line(text: "Not placed: tap two corners", ok: false)
    default: return Line(text: "Not placed yet: no outline for this room", ok: false)
    }
  }

  public var wallsLine: Line {
    guard let walls else {
      return Line(text: "Walls photographed: unknown until the capture is placed", ok: false)
    }
    var text = "Walls photographed: \(walls.photographed) of \(walls.total)"
    if let worst = walls.gaps.first {
      let corners = worst.wall.components(separatedBy: "->").map(Self.short)
      let wallName = corners.count == 2 ? "\(corners[0])–\(corners[1]) wall" : worst.wall
      text += "; \(wallName), \(Self.metres(worst.lengthM)) not photographed"
        + " from \(Self.metres(worst.fromM)) past \(corners.first ?? "its first corner")"
      if walls.gaps.count > 1 { text += " (+\(walls.gaps.count - 1) more)" }
    }
    return Line(text: text, ok: walls.photographed == walls.total)
  }

  public var stillsLine: Line {
    guard stills.total > 0 else { return Line(text: "Stills: no list for these trades", ok: true) }
    var text = "Stills: \(stills.done) of \(stills.total) on the list"
    if !stills.missing.isEmpty {
      let names = stills.missing.prefix(3).map { StillsChecklist.name(for: $0) }
      text += "; missing " + names.joined(separator: ", ")
      if stills.missing.count > 3 { text += " (+\(stills.missing.count - 3) more)" }
    }
    return Line(text: text, ok: stills.missing.isEmpty)
  }

  /// `corner-ne2` reads as `NE2`.
  static func short(_ label: String) -> String {
    let trimmed = label.hasPrefix("corner-") ? String(label.dropFirst("corner-".count)) : label
    return trimmed.uppercased()
  }

  static func metres(_ value: Double) -> String {
    String(format: "%.1f m", value)
  }

  /// Gap metres to the nearest decimetre, which is the coverage cell.
  private static func decimetres(_ value: Double) -> Double {
    (value * 10).rounded() / 10
  }
}
