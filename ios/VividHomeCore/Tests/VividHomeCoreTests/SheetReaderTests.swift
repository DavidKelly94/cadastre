import Foundation
import XCTest

@testable import VividHomeCore

/// A drawing sets itself up (ADR-0032): the scale from the title block,
/// checked against the dimensions, and each room filled out from its label to
/// the walls.
final class SheetReaderTests: XCTestCase {
  // MARK: - A small sheet

  /// Characters across the page, 4 pt wide and 7 tall, centred on a point.
  private func word(_ text: String, at x: Double, _ y: Double) -> [Sheet.Glyph] {
    let advance = 4.4
    var left = x - Double(text.count) * advance / 2
    var out: [Sheet.Glyph] = []
    for character in text {
      let width = character == " " ? 2.0 : 4.0
      out.append(
        Sheet.Glyph(
          text: String(character),
          box: Sheet.Box(minX: left, minY: y - 3.5, maxX: left + width, maxY: y + 3.5)))
      left += advance
    }
    return out
  }

  /// The same characters up the page, as a dimension beside a wall is set.
  private func upright(_ text: String, at x: Double, _ y: Double) -> [Sheet.Glyph] {
    let advance = 4.4
    var bottom = y + Double(text.count) * advance / 2
    var out: [Sheet.Glyph] = []
    for character in text {
      let height = character == " " ? 2.0 : 4.0
      out.append(
        Sheet.Glyph(
          text: String(character),
          box: Sheet.Box(minX: x - 3.5, minY: bottom - height, maxX: x + 3.5, maxY: bottom)))
      bottom -= advance
    }
    return out
  }

  private func wall(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Sheet.Fill {
    Sheet.Fill(
      polygons: [[Sheet.Point(x0, y0), Sheet.Point(x1, y0), Sheet.Point(x1, y1), Sheet.Point(x0, y1)]],
      red: 0.5, green: 0.5, blue: 0.5)
  }

  private let line = Sheet.Glyph(text: "\n", box: Sheet.Box(minX: 0, minY: 0, maxX: 0, maxY: 0))

  /// A 20 by 12 ft house at 1/4 inch to the foot (18 pt per foot), 6 pt
  /// walls: an open kitchen and dining on the left, an office on the right
  /// with a wall stub hanging into it, and a patio label outside.
  private func house(witnessRight: Double = 460) -> Sheet {
    var glyphs: [Sheet.Glyph] = []
    for (tag, name, x, y) in [
      ("101", "KITCHEN", 150.0, 160.0), ("102", "DINING", 220.0, 250.0), ("103", "OFFICE", 400.0, 220.0),
      ("104", "PATIO", 620.0, 200.0),
    ] {
      glyphs += word(tag, at: x, y)
      glyphs.append(line)
      glyphs += word(name, at: x, y + 12)
      glyphs.append(line)
    }
    glyphs += word("20' - 0\"", at: 280, 80)
    glyphs.append(line)
    glyphs += upright("12' - 0\"", at: 80, 208)
    glyphs.append(line)
    glyphs += word("1/4\" = 1'-0\"", at: 620, 520)
    glyphs.append(line)
    glyphs += word("FIRST FLOOR PLAN", at: 620, 500)

    let fills = [
      wall(100, 100, 460, 106), wall(100, 310, 460, 316), wall(100, 100, 106, 316),
      wall(454, 100, 460, 316), wall(277, 100, 283, 316),
      wall(367, 106, 373, 166),  // the stub
      // Paper, and a compact black arrowhead: neither is a wall.
      Sheet.Fill(
        polygons: [[Sheet.Point(0, 0), Sheet.Point(800, 0), Sheet.Point(800, 600), Sheet.Point(0, 600)]],
        red: 1, green: 1, blue: 1),
      Sheet.Fill(
        polygons: [[Sheet.Point(98, 78), Sheet.Point(104, 80), Sheet.Point(98, 82)]], red: 0, green: 0, blue: 0),
    ]
    let segments = [
      Sheet.Segment(Sheet.Point(100, 70), Sheet.Point(100, 98)),
      Sheet.Segment(Sheet.Point(witnessRight, 70), Sheet.Point(witnessRight, 98)),
      Sheet.Segment(Sheet.Point(70, 100), Sheet.Point(98, 100)),
      Sheet.Segment(Sheet.Point(70, witnessRight - 144), Sheet.Point(98, witnessRight - 144)),
      Sheet.Segment(Sheet.Point(100, 80), Sheet.Point(460, 80)),  // the dimension line itself
    ]
    return Sheet(width: 800, height: 600, glyphs: glyphs, fills: fills, segments: segments)
  }

  // MARK: - Text

  func testGlyphsGatherIntoRunsAcrossAndUpThePage() {
    var glyphs = word("M BEDROOM", at: 100, 100)
    glyphs += word("VAULT", at: 200, 100)
    glyphs.append(line)
    glyphs += upright("9' - 11 3/4\"", at: 50, 200)
    let runs = Sheet.runs(from: glyphs)
    XCTAssertEqual(runs.map(\.text), ["M BEDROOM", "VAULT", "9' - 11 3/4\""])
    XCTAssertEqual(runs.map(\.vertical), [false, false, true])
    XCTAssertEqual(runs[0].box.midX, 100, accuracy: 1)
    XCTAssertEqual(runs[2].box.midY, 200, accuracy: 3)
  }

  // MARK: - Scale

  /// Build 77 on the owner's sheet: the PDF reader gave the last character of
  /// every line twice, in the same place. Narrow ones joined the run they
  /// ended, so the scale read `1'-0""` and a bedroom was `BEDROOM 22`.
  func testACharacterGivenTwiceInOnePlaceCountsOnce() {
    var glyphs: [Sheet.Glyph] = []
    for text in ["BEDROOM 2", "1/4\" = 1'-0\"", "HALL", "WIC"] {
      let word = word(text, at: 100, Double(glyphs.count) * 2 + 40)
      glyphs += word
      glyphs.append(word[word.count - 1])
      glyphs.append(line)
    }
    let texts = Sheet.runs(from: glyphs).map(\.text)
    XCTAssertEqual(texts, ["BEDROOM 2", "1/4\" = 1'-0\"", "HALL", "WIC"])
  }

  func testScaleNotesReadAsARatio() throws {
    XCTAssertEqual(try XCTUnwrap(SheetScale.ratio(from: "1/4\" = 1'-0\"")), 48, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(SheetScale.ratio(from: "SCALE: 1/8\" = 1'-0\"")), 96, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(SheetScale.ratio(from: "3/4\" = 1'-0\"")), 16, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(SheetScale.ratio(from: "1:50")), 50, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(SheetScale.ratio(from: "Scale 1 : 100")), 100, accuracy: 1e-9)
    for text in ["1 = 1", "12:30", "KITCHEN", "A = B", "2:50"] {
      XCTAssertNil(SheetScale.ratio(from: text), text)
    }
    // A quarter inch to the foot: one point is two thirds of an inch.
    XCTAssertEqual(SheetScale.metresPerPoint(ratio: 48), 0.0254 * 2 / 3, accuracy: 1e-12)
  }

  func testOnlyFeetAndInchesAreDimensions() throws {
    XCTAssertEqual(try XCTUnwrap(SheetScale.dimension(from: "40' - 0\"")), 12.192, accuracy: 1e-9)
    XCTAssertEqual(
      try XCTUnwrap(SheetScale.dimension(from: "9' - 11 3/4\"")), (9 * 12 + 11.75) * 0.0254, accuracy: 1e-9)
    for text in ["200", "6\"", "BEDROOM 2", "1/4\" = 1'-0\"", "10x10 FIR"] {
      XCTAssertNil(SheetScale.dimension(from: text), text)
    }
  }

  func testTheScaleIsBorneOutByTheSheetsOwnDimensions() throws {
    let proposal = SheetReader.read(house())
    let scale = try XCTUnwrap(proposal.scale)
    XCTAssertEqual(scale.note, "1/4\" = 1'-0\"")
    XCTAssertEqual(scale.ratio, 48, accuracy: 1e-9)
    XCTAssertEqual(scale.agreement, SheetScale.Agreement(tested: 2, agreeing: 2))
    XCTAssertEqual(scale.check, .agrees)
    XCTAssertEqual(proposal.dimensions, 2)
  }

  func testASheetPrintedToFitItsPageIsCaught() throws {
    // The same notes over geometry nine tenths the size: the witness lines
    // are 324 pt apart where 20 ft at the stated scale is 360.
    let scale = try XCTUnwrap(SheetReader.read(house(witnessRight: 424)).scale)
    XCTAssertEqual(scale.agreement.tested, 2)
    XCTAssertEqual(scale.agreement.agreeing, 0)
    XCTAssertEqual(scale.check, .disagrees)
  }

  // MARK: - Rooms

  func testRoomsAreFilledOutFromTheirLabelsToTheWalls() throws {
    let proposal = SheetReader.read(house())
    XCTAssertEqual(proposal.wallShapes, 6, "the paper and the arrowhead are not walls")
    XCTAssertEqual(proposal.rooms.map(\.slug), ["kitchen", "dining", "office", "patio"])
    XCTAssertEqual(proposal.rooms.map(\.tag), ["101", "102", "103", "104"])

    // The office: four corners on the inside wall faces, the stub closed over.
    let office = proposal.rooms[2]
    XCTAssertEqual(office.status, .outlined)
    XCTAssertEqual(office.outline.count, 4, "\(office.outline)")
    let xs = office.outline.map(\.x).sorted(), ys = office.outline.map(\.y).sorted()
    XCTAssertEqual(xs[0], 283, accuracy: 1.01)
    XCTAssertEqual(xs[3], 454, accuracy: 1.01)
    XCTAssertEqual(ys[0], 106, accuracy: 1.01)
    XCTAssertEqual(ys[3], 310, accuracy: 1.01)
    // Clockwise from the top-left, as the owner would walk it on the page.
    XCTAssertEqual(office.outline[0].x, xs[0], accuracy: 1e-9)
    XCTAssertEqual(office.outline[0].y, ys[0], accuracy: 1e-9)
    XCTAssertEqual(office.outline[1].x, xs[3], accuracy: 1e-9)
    XCTAssertEqual(office.outline[1].y, ys[0], accuracy: 1e-9)
    // 171 by 204 pt of floor, less the stub.
    XCTAssertEqual(office.areaPoints, 171 * 204, accuracy: 171 * 204 * 0.03)

    // Kitchen and dining share one space with no wall between.
    XCTAssertEqual(proposal.rooms[0].status, .openPlan)
    XCTAssertEqual(proposal.rooms[0].sharedWith, ["dining"])
    XCTAssertEqual(proposal.rooms[1].sharedWith, ["kitchen"])
    XCTAssertEqual(proposal.rooms[0].outline.count, 4)

    // The patio is outside the walls: a pin, and no outline.
    XCTAssertEqual(proposal.rooms[3].status, .notEnclosed)
    XCTAssertTrue(proposal.rooms[3].outline.isEmpty)
  }

  func testWithoutRoomNumbersNamesThatReadAsRoomsAreKept() {
    var glyphs: [Sheet.Glyph] = []
    for (text, x, y) in [
      ("KITCHEN", 100.0, 100.0), ("SHELVES", 200.0, 100.0), ("M BATH", 300.0, 100.0),
      ("FIRST FLOOR PLAN", 400.0, 300.0), ("WIC", 100.0, 200.0), ("WIC", 300.0, 200.0),
    ] {
      glyphs += word(text, at: x, y)
      glyphs.append(line)
    }
    let labels = SheetReader.roomLabels(in: Sheet.runs(from: glyphs))
    XCTAssertEqual(labels.map { $0.slug }, ["kitchen", "m-bath", "wic", "wic-2"])
    XCTAssertTrue(SheetReader.isTag("203"))
    XCTAssertTrue(SheetReader.isTag("12A"))
    XCTAssertFalse(SheetReader.isTag("7"))
    XCTAssertFalse(SheetReader.isTag("A201"))
  }

  // MARK: - The grid

  func testTheEdgeWalkTurnsAtEveryCornerOfAnLShape() {
    // ##.
    // ##.
    // ###
    let bitmap = [true, true, false, true, true, false, true, true, true]
    let corners = SheetReader.Grid.trace(bitmap, width: 3, height: 3)
    XCTAssertEqual(corners.map { [$0.x, $0.y] }, [[0, 0], [2, 0], [2, 2], [3, 2], [3, 3], [0, 3]])
    XCTAssertTrue(SheetReader.Grid.trace([false, false], width: 2, height: 1).isEmpty)
  }

  func testAOneCellJogIsNotACorner() {
    // A 40 by 20 rectangle whose top edge steps down one cell half way along.
    let loop = [(0, 0), (20, 0), (20, 1), (40, 1), (40, 20), (0, 20)].map { (x: $0.0, y: $0.1) }
    let kept = SheetReader.Grid.simplify(loop, tolerance: 1.5)
    XCTAssertEqual(kept.count, 4, "\(kept)")
    // A real notch stays.
    let notched = [(0, 0), (20, 0), (20, 8), (40, 8), (40, 20), (0, 20)].map { (x: $0.0, y: $0.1) }
    XCTAssertEqual(SheetReader.Grid.simplify(notched, tolerance: 1.5).count, 6)
  }

  func testGrowingThenShrinkingClosesAThinGapAndNothingElse() {
    // Two 4 by 6 blocks with a 2 cell slot between them, padded all round.
    let width = 20, height = 16
    var bitmap = [Bool](repeating: false, count: width * height)
    for y in 5..<11 {
      for x in 5..<15 where !(x == 9 || x == 10) || y >= 9 { bitmap[y * width + x] = true }
    }
    var closed = SheetReader.Grid.spread(bitmap, width: width, height: height, radius: 2, value: true)
    closed = SheetReader.Grid.spread(closed, width: width, height: height, radius: 2, value: false)
    XCTAssertTrue(closed[5 * width + 9], "the slot is filled")
    XCTAssertEqual(SheetReader.Grid.trace(closed, width: width, height: height).count, 4)
    XCTAssertFalse(closed[4 * width + 9], "and nothing grew past the old edge")
  }

  // MARK: - A real sheet

  /// Run the reader on a real drawing dumped to JSON and print what it found.
  /// Skipped unless `VIVIDHOME_SHEET_JSON` names the file: an owner's plan is
  /// theirs, so none is committed, and this is how one is tried locally.
  func testARealSheetNamedByTheEnvironment() throws {
    guard let path = ProcessInfo.processInfo.environment["VIVIDHOME_SHEET_JSON"] else {
      throw XCTSkip("set VIVIDHOME_SHEET_JSON to a sheet dumped as JSON")
    }
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
    func numbers(_ value: Any?) -> [Double] { (value as? [NSNumber])?.map(\.doubleValue) ?? [] }
    let glyphs = (object["glyphs"] as? [[Any]] ?? []).map { entry -> Sheet.Glyph in
      let box = numbers(Array(entry.dropFirst()))
      return Sheet.Glyph(
        text: entry.first as? String ?? "",
        box: Sheet.Box(minX: box[0], minY: box[1], maxX: box[2], maxY: box[3]))
    }
    let fills = (object["fills"] as? [[String: Any]] ?? []).map { entry -> Sheet.Fill in
      let colour = numbers(entry["rgb"])
      let polygons = (entry["polygons"] as? [[NSNumber]] ?? []).map { flat -> [Sheet.Point] in
        stride(from: 0, to: flat.count - 1, by: 2).map { Sheet.Point(flat[$0].doubleValue, flat[$0 + 1].doubleValue) }
      }
      return Sheet.Fill(polygons: polygons, red: colour[0], green: colour[1], blue: colour[2])
    }
    let flat = numbers(object["segments"])
    let segments = stride(from: 0, to: flat.count - 3, by: 4).map {
      Sheet.Segment(Sheet.Point(flat[$0], flat[$0 + 1]), Sheet.Point(flat[$0 + 2], flat[$0 + 3]))
    }
    let size = numbers(object["size"])
    let sheet = Sheet(width: size[0], height: size[1], glyphs: glyphs, fills: fills, segments: segments)

    let started = Date()
    let proposal = SheetReader.read(sheet)
    print("SHEET read in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
    print("SHEET \(proposal.textRuns) runs, \(proposal.dimensions) dimensions, \(proposal.wallShapes) wall shapes")
    if let scale = proposal.scale {
      print("SHEET scale \(scale.note) ratio \(scale.ratio) \(scale.check) \(scale.agreement.agreeing)/\(scale.agreement.tested)")
    } else {
      print("SHEET no scale note")
    }
    // How much a wrong scale would be flattered by chance on a sheet this dense.
    let runs = Sheet.runs(from: sheet.glyphs)
    for ratio in [43.2, 47.0, 50.0, 96.0] {
      let chance = SheetScale.agreement(
        runs: runs, segments: sheet.segments, metresPerPoint: SheetScale.metresPerPoint(ratio: ratio))
      print("SHEET a wrong scale of \(ratio) would have \(chance.agreeing)/\(chance.tested) agree")
    }
    for room in proposal.rooms {
      let feet = room.areaPoints * pow((proposal.scale?.metresPerPoint ?? 0) / 0.3048, 2)
      print(
        "SHEET \(room.tag ?? "-") \(room.slug): \(room.status) \(room.outline.count) corners, "
          + "\(Int(feet.rounded())) sq ft" + (room.sharedWith.isEmpty ? "" : " with \(room.sharedWith)"))
    }
    if let out = ProcessInfo.processInfo.environment["VIVIDHOME_SHEET_OUT"] {
      let rooms = proposal.rooms.map { room -> [String: Any] in
        ["slug": room.slug, "status": "\(room.status)", "outline": room.outline.map { [$0.x, $0.y] }]
      }
      try JSONSerialization.data(withJSONObject: ["rooms": rooms]).write(to: URL(fileURLWithPath: out))
    }
  }

  // MARK: - Into the plan

  func testApplyingWritesTheScaleThePinsAndTheOutlines() throws {
    let proposal = SheetReader.read(house())
    var plan = PlanFile(level: "main", image: "main.png")
    // The raster is the 800 by 600 pt page at two pixels a point.
    let applied = plan.apply(
      proposal, pixelsPerPoint: 2, imageSize: (1600, 1200), rooms: ["kitchen", "office", "patio"],
      setScale: true, at: Date(timeIntervalSince1970: 1_793_733_302))

    XCTAssertTrue(applied.scaleSet)
    XCTAssertEqual(applied.pinned, ["kitchen", "office", "patio"])
    XCTAssertEqual(applied.outlined, ["office"], "an open plan and an unenclosed room are pinned only")
    // 20 ft of house is 360 pt, 720 px.
    XCTAssertEqual(try XCTUnwrap(plan.metresPerPixel) * 720, 20 * 0.3048, accuracy: 1e-9)
    XCTAssertEqual(plan.originPx, [200, 200], "the top-left of the walls")
    XCTAssertNil(plan.placement(of: "dining"), "not chosen")

    let office = try XCTUnwrap(plan.placement(of: "office"))
    XCTAssertEqual(office.x, 800, accuracy: 1)
    XCTAssertEqual(office.cornerNames, ["corner-nw", "corner-ne", "corner-se", "corner-sw"])
    // The office in house metres: 171 pt of 18 to the foot is 9.5 ft wide.
    let corners = try XCTUnwrap(plan.houseCorners(of: "office"))
    XCTAssertEqual(corners[1].x - corners[0].x, 9.5 * 0.3048, accuracy: 0.02)
    XCTAssertEqual(corners[2].z - corners[1].z, (204.0 / 18) * 0.3048, accuracy: 0.02)
  }

  func testAnExistingScaleAndPinAreKept() throws {
    let proposal = SheetReader.read(house())
    var plan = try XCTUnwrap(
      PlanFile(level: "main", image: "main.png").calibrated(
        scaleFrom: (0, 0), to: (100, 0), distanceMetres: 1, origin: (5, 5)))
    XCTAssertTrue(plan.place(room: "office", x: 10, y: 10, in: (1600, 1200)))
    let applied = plan.apply(
      proposal, pixelsPerPoint: 2, imageSize: (1600, 1200), rooms: ["office"], setScale: true)
    XCTAssertFalse(applied.scaleSet, "captures may already be aligned to the old one")
    XCTAssertEqual(plan.metresPerPixel, 0.01)
    XCTAssertEqual(applied.pinned, [])
    XCTAssertEqual(applied.outlined, ["office"])
    XCTAssertEqual(plan.placement(of: "office")?.x, 10)
  }

  func testAScaleItsDimensionsContradictIsNeverWritten() {
    let proposal = SheetReader.read(house(witnessRight: 424))
    var plan = PlanFile(level: "main", image: "main.png")
    let applied = plan.apply(
      proposal, pixelsPerPoint: 2, imageSize: (1600, 1200), rooms: [], setScale: true)
    XCTAssertFalse(applied.scaleSet)
    XCTAssertFalse(plan.isCalibrated)
  }

  /// Reading the drawing a second time is how a room is put back: the plan
  /// has to know which rooms still stand as drawn and which were changed.
  func testAPlanKnowsWhichRoomsStandAsDrawnAndPutsOneBack() throws {
    let proposal = SheetReader.read(house())
    let office = try XCTUnwrap(proposal.rooms.first { $0.slug == "office" })
    let kitchen = try XCTUnwrap(proposal.rooms.first { $0.slug == "kitchen" })
    var plan = PlanFile(level: "main", image: "main.png")
    XCTAssertEqual(plan.sheetState(of: office, pixelsPerPoint: 2), .missing)

    let first = Date(timeIntervalSince1970: 1_793_733_302)
    plan.apply(
      proposal, pixelsPerPoint: 2, imageSize: (1600, 1200), rooms: ["kitchen", "office"],
      setScale: true, at: first)
    XCTAssertEqual(plan.sheetState(of: office, pixelsPerPoint: 2), .asDrawn)
    XCTAssertEqual(plan.sheetState(of: kitchen, pixelsPerPoint: 2), .pinned, "open plan: nothing to outline")
    let stamped = try XCTUnwrap(plan.placement(of: "office")?.outlinedAt)

    // Applying again changes nothing, the time it was outlined included.
    let later = Date(timeIntervalSince1970: 1_793_800_000)
    var again = plan.apply(
      proposal, pixelsPerPoint: 2, imageSize: (1600, 1200), rooms: ["office"], setScale: false, at: later)
    XCTAssertEqual(again.outlined, [])
    XCTAssertEqual(plan.placement(of: "office")?.outlinedAt, stamped)

    // A corner dragged by hand: no longer as drawn, and applying puts it back.
    var moved = try XCTUnwrap(plan.placement(of: "office")?.outline)
    moved[0][0] += 40
    XCTAssertTrue(plan.outline(room: "office", points: moved, in: (1600, 1200), at: later))
    XCTAssertEqual(plan.sheetState(of: office, pixelsPerPoint: 2), .byHand)
    again = plan.apply(
      proposal, pixelsPerPoint: 2, imageSize: (1600, 1200), rooms: ["office"], setScale: false, at: later)
    XCTAssertEqual(again.outlined, ["office"])
    XCTAssertEqual(plan.sheetState(of: office, pixelsPerPoint: 2), .asDrawn)

    // An outline drawn by hand where the drawing has none stays by hand.
    let square: [[Double]] = [[220, 220], [500, 220], [500, 500], [220, 500]]
    XCTAssertTrue(plan.outline(room: "kitchen", points: square, in: (1600, 1200), at: later))
    XCTAssertEqual(plan.sheetState(of: kitchen, pixelsPerPoint: 2), .byHand)

    // Removed from the plan, it comes back with its pin and its outline.
    plan.unplace(room: "office")
    XCTAssertEqual(plan.sheetState(of: office, pixelsPerPoint: 2), .missing)
    again = plan.apply(
      proposal, pixelsPerPoint: 2, imageSize: (1600, 1200), rooms: ["office"], setScale: false, at: later)
    XCTAssertEqual(again.pinned, ["office"])
    XCTAssertEqual(again.outlined, ["office"])
  }
}
