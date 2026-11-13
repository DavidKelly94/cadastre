import Foundation

/// What a vector drawing says about itself (ADR-0032): the text an architect
/// printed, the shapes they filled and the lines they stroked, lifted out of
/// the PDF by the app and handed here as plain numbers.
///
/// Everything is in **sheet points**: 1/72 inch on the printed page, origin at
/// the page's top-left corner, `x` right and `y` down, which is how the plan
/// raster is addressed too. Nothing in this file knows what a PDF is; the
/// reader that does lives in the Apple-only target beside this one.
public struct Sheet: Sendable {
  public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
      self.x = x
      self.y = y
    }
  }

  public struct Box: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
      self.minX = minX
      self.minY = minY
      self.maxX = maxX
      self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }

    func union(_ other: Box) -> Box {
      Box(
        minX: min(minX, other.minX), minY: min(minY, other.minY),
        maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }
  }

  /// One character as the page lays it out, in reading order. A line break is
  /// a glyph whose text is a newline; a space may have an empty box.
  public struct Glyph: Equatable, Sendable {
    public var text: String
    public var box: Box

    public init(text: String, box: Box) {
      self.text = text
      self.box = box
    }
  }

  /// One filled path: its subpaths as closed polygons, and its colour.
  public struct Fill: Equatable, Sendable {
    public var polygons: [[Point]]
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(polygons: [[Point]], red: Double, green: Double, blue: Double) {
      self.polygons = polygons
      self.red = red
      self.green = green
      self.blue = blue
    }
  }

  /// One stroked straight line.
  public struct Segment: Equatable, Sendable {
    public var a: Point
    public var b: Point

    public init(_ a: Point, _ b: Point) {
      self.a = a
      self.b = b
    }
  }

  /// The page, in points.
  public var width: Double
  public var height: Double
  public var glyphs: [Glyph]
  public var fills: [Fill]
  public var segments: [Segment]

  public init(width: Double, height: Double, glyphs: [Glyph], fills: [Fill], segments: [Segment]) {
    self.width = width
    self.height = height
    self.glyphs = glyphs
    self.fills = fills
    self.segments = segments
  }
}

// MARK: - Text

extension Sheet {
  /// A piece of text that belongs together: a room name, a dimension, a note.
  public struct Run: Equatable, Sendable {
    public var text: String
    public var box: Box
    /// Set when the characters step down or up the page, as a dimension beside
    /// a vertical wall does.
    public var vertical: Bool
  }

  /// The glyphs gathered into runs.
  ///
  /// Two characters belong together when one follows the other closely along
  /// a line, across the page or up it. A space is allowed to widen the gap, so
  /// `40' - 0"` is one run; a wider gap, a line break or a change of direction
  /// starts a new one. That is deliberately all: what a run means is decided
  /// by whoever reads it.
  public static func runs(from glyphs: [Glyph]) -> [Run] {
    var out: [Run] = []
    var text = ""
    var box: Box?
    var last: Box?
    var vertical: Bool?
    var spaced = false

    func flush() {
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      if let box, !trimmed.isEmpty {
        out.append(Run(text: trimmed, box: box, vertical: vertical ?? false))
      }
      text = ""
      box = nil
      last = nil
      vertical = nil
      spaced = false
    }

    for glyph in glyphs {
      if glyph.text.contains(where: { $0.isNewline }) {
        flush()
        continue
      }
      let blank = glyph.text.allSatisfy { $0.isWhitespace }
      if blank || (glyph.box.width <= 0 && glyph.box.height <= 0) {
        spaced = spaced || blank
        continue
      }
      guard let previous = last else {
        text = glyph.text
        box = glyph.box
        last = glyph.box
        spaced = false
        continue
      }

      let reach = spaced ? 1.2 : 0.45
      // Across the page: side by side on one line.
      let tall = max(previous.height, glyph.box.height)
      let gapX = glyph.box.minX - previous.maxX
      let across =
        abs(glyph.box.midY - previous.midY) <= 0.5 * tall
        && gapX >= -0.5 * tall && gapX <= reach * tall
      // Up or down the page: stacked in one column.
      let wide = max(previous.width, glyph.box.width)
      let gapY = max(previous.minY - glyph.box.maxY, glyph.box.minY - previous.maxY)
      let along =
        abs(glyph.box.midX - previous.midX) <= 0.5 * wide
        && gapY >= -0.5 * wide && gapY <= reach * wide

      let joins: Bool
      switch vertical {
      case .some(true): joins = along
      case .some(false): joins = across
      case .none: joins = across || along
      }
      if joins {
        if vertical == nil { vertical = !across }
        text += (spaced ? " " : "") + glyph.text
        box = box?.union(glyph.box)
        last = glyph.box
      } else {
        flush()
        text = glyph.text
        box = glyph.box
        last = glyph.box
      }
      spaced = false
    }
    flush()
    return out
  }
}

// MARK: - Scale

/// The scale a sheet states, and whether its own dimensions bear it out.
public enum SheetScale {
  /// Real distance over paper distance, from a note such as `1/4" = 1'-0"`
  /// (48) or `1:50` (50). Nil when the text is not a scale note.
  public static func ratio(from note: String) -> Double? {
    var text = note.lowercased().replacingOccurrences(of: "scale", with: " ")
    text = text.trimmingCharacters(in: CharacterSet(charactersIn: " :\t"))

    if let equals = text.firstIndex(of: "=") {
      let paper = String(text[..<equals]).trimmingCharacters(in: .whitespaces)
      let real = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
      // Both sides must carry a unit mark: a bare number is metres to
      // `PlanDistance`, and `1 = 1` is not a scale.
      guard isImperial(paper), isImperial(real),
        let paperMetres = PlanDistance.metres(from: paper), paperMetres > 0,
        let realMetres = PlanDistance.metres(from: real), realMetres > 0
      else { return nil }
      let ratio = realMetres / paperMetres
      return ratio >= 1 ? ratio : nil
    }

    // Metric: `1:50`, `1 : 100`.
    let parts = text.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
    if parts.count == 2, parts[0] == "1", let denominator = Double(parts[1]), denominator >= 1 {
      return denominator
    }
    return nil
  }

  /// Metres on the ground per point on the sheet at this ratio.
  public static func metresPerPoint(ratio: Double) -> Double {
    ratio * 0.0254 / 72
  }

  /// A printed dimension, `40' - 0"` or `9' - 11 3/4"`, in metres. Only
  /// feet-and-inches strings count: a bare number on a drawing is a room
  /// number, a door tag or a note.
  public static func dimension(from text: String) -> Double? {
    let allowed = CharacterSet(charactersIn: "0123456789 '\"-/.’′”″")
    guard let first = text.unicodeScalars.first, CharacterSet.decimalDigits.contains(first),
      text.unicodeScalars.allSatisfy({ allowed.contains($0) }),
      text.contains("'") || text.contains("’") || text.contains("′"),
      let metres = PlanDistance.metres(from: text), metres > 0
    else { return nil }
    return metres
  }

  private static func isImperial(_ text: String) -> Bool {
    text.contains("'") || text.contains("\"") || text.contains("’") || text.contains("”")
      || text.contains("′") || text.contains("″")
  }

  /// How the sheet's dimensions compare with a scale.
  public struct Agreement: Equatable, Sendable {
    /// Dimensions that had two lines to measure between.
    public var tested: Int
    /// Of those, the ones with two lines exactly their printed length apart.
    public var agreeing: Int
  }

  /// Test a scale against the sheet: for each printed dimension, look for the
  /// two witness lines it measures between, exactly its length apart at this
  /// scale and either side of the text.
  ///
  /// On a dense sheet a pair of unrelated lines can sit the right distance
  /// apart by chance, so one agreement proves little. Most of them agreeing
  /// does, and a sheet printed to fit a page fails nearly all of them.
  public static func agreement(
    runs: [Sheet.Run], segments: [Sheet.Segment], metresPerPoint: Double
  ) -> Agreement {
    guard metresPerPoint > 0 else { return Agreement(tested: 0, agreeing: 0) }
    // Witness lines by where they stand: vertical ones by x with their y
    // extent, horizontal ones by y with their x extent.
    var uprights: [(at: Double, low: Double, high: Double)] = []
    var levels: [(at: Double, low: Double, high: Double)] = []
    for segment in segments {
      let dx = abs(segment.a.x - segment.b.x), dy = abs(segment.a.y - segment.b.y)
      if dx < 0.05, dy > 3 {
        uprights.append((segment.a.x, min(segment.a.y, segment.b.y), max(segment.a.y, segment.b.y)))
      } else if dy < 0.05, dx > 3 {
        levels.append((segment.a.y, min(segment.a.x, segment.b.x), max(segment.a.x, segment.b.x)))
      }
    }

    var tested = 0
    var agreeing = 0
    for run in runs {
      guard let metres = dimension(from: run.text), metres >= 0.6 else { continue }
      let want = metres / metresPerPoint
      let centre = run.vertical ? run.box.midY : run.box.midX
      let across = run.vertical ? run.box.midX : run.box.midY
      let lines = run.vertical ? levels : uprights
      var stations: [Double] = []
      for line in lines
      where line.low - 12 <= across && across <= line.high + 12 && abs(line.at - centre) <= want + 6 {
        stations.append(line.at)
      }
      stations.sort()
      guard stations.count >= 2 else { continue }
      tested += 1
      let tolerance = 0.75 + 0.001 * want
      var found = false
      for start in stations where start <= centre {
        // The first station at or past where the far witness line should be.
        var low = 0
        var high = stations.count
        let target = start + want - tolerance
        while low < high {
          let middle = (low + high) / 2
          if stations[middle] < target { low = middle + 1 } else { high = middle }
        }
        if low < stations.count, stations[low] <= start + want + tolerance, stations[low] >= centre {
          found = true
          break
        }
      }
      if found { agreeing += 1 }
    }
    return Agreement(tested: tested, agreeing: agreeing)
  }
}
