// The PDF reader against a drawing whose contents are known (ADR-0032).
//
// Runs only where Apple's PDF frameworks exist: the macOS runner. The fixture
// is written by make_house_sheet.py beside this file and is the same house
// SheetReaderTests builds by hand, so what is asserted here is that the
// numbers survive the trip through a real PDF.

#if canImport(PDFKit) && canImport(CoreGraphics)
  import Foundation
  import PDFKit
  import XCTest

  import VividHomeCore
  @testable import VividHomePDF

  final class SheetPDFTests: XCTestCase {
    private func houseSheet() throws -> Sheet {
      let url = try XCTUnwrap(
        Bundle.module.url(forResource: "house-sheet", withExtension: "pdf", subdirectory: "Fixtures"))
      return try XCTUnwrap(SheetPDF.sheet(data: Data(contentsOf: url), page: 0))
    }

    func testThePageItsFillsAndItsLinesComeThroughInSheetPoints() throws {
      let sheet = try houseSheet()
      XCTAssertEqual(sheet.width, 800)
      XCTAssertEqual(sheet.height, 600)

      // The paper, six walls (one of them inside a form), and an arrowhead.
      XCTAssertEqual(sheet.fills.count, 8, "\(sheet.fills.map { $0.polygons.first?.count ?? 0 })")
      let grey = sheet.fills.filter { abs($0.red - 0.5) < 0.01 && abs($0.green - 0.5) < 0.01 }
      XCTAssertEqual(grey.count, 6)
      // The top wall: 100..460 across, 100..106 down from the top of the page.
      let boxes = grey.compactMap { fill -> Sheet.Box? in
        guard let polygon = fill.polygons.first else { return nil }
        return Sheet.Box(
          minX: polygon.map(\.x).min() ?? 0, minY: polygon.map(\.y).min() ?? 0,
          maxX: polygon.map(\.x).max() ?? 0, maxY: polygon.map(\.y).max() ?? 0)
      }
      XCTAssertTrue(
        boxes.contains { abs($0.minX - 100) < 0.01 && abs($0.maxX - 460) < 0.01 && abs($0.minY - 100) < 0.01 && abs($0.maxY - 106) < 0.01 },
        "\(boxes)")
      // The stub, drawn by a form placed with its own matrix under the scale.
      XCTAssertTrue(
        boxes.contains { abs($0.minX - 367) < 0.01 && abs($0.maxX - 373) < 0.01 && abs($0.minY - 106) < 0.01 && abs($0.maxY - 166) < 0.01 },
        "\(boxes)")

      XCTAssertEqual(sheet.segments.count, 5)
      XCTAssertTrue(
        sheet.segments.contains { abs($0.a.x - 460) < 0.01 && abs($0.b.x - 460) < 0.01 && abs(min($0.a.y, $0.b.y) - 70) < 0.01 })
    }

    func testTheTextComesThroughAsRuns() throws {
      let sheet = try houseSheet()
      let runs = Sheet.runs(from: sheet.glyphs)
      // Printed so the log shows what PDFKit made of the page, whatever the
      // assertions below say.
      for run in runs {
        print("RUN \(run.vertical ? "up" : "across") '\(run.text)' at \(Int(run.box.midX)),\(Int(run.box.midY))")
      }
      let texts = Set(runs.map(\.text))
      for expected in ["101", "KITCHEN", "102", "DINING", "103", "OFFICE", "104", "PATIO", "1/4\" = 1'-0\""] {
        XCTAssertTrue(texts.contains(expected), "missing \(expected) in \(texts.sorted())")
      }
      let office = try XCTUnwrap(runs.first { $0.text == "103" })
      XCTAssertEqual(office.box.midX, 400, accuracy: 6)
      XCTAssertEqual(office.box.midY, 220, accuracy: 6)
      XCTAssertNotNil(runs.first { SheetScale.dimension(from: $0.text) != nil && !$0.vertical })
    }

    func testTheWholeReadingProposesTheHouse() throws {
      let proposal = SheetReader.read(try houseSheet())
      print("PROPOSAL \(proposal.textRuns) runs, \(proposal.dimensions) dimensions, \(proposal.wallShapes) walls")
      if let scale = proposal.scale {
        print("PROPOSAL scale \(scale.note) \(scale.check) \(scale.agreement.agreeing)/\(scale.agreement.tested)")
      }
      for room in proposal.rooms {
        print("PROPOSAL \(room.slug) \(room.status) \(room.outline.map { "(\(Int($0.x)),\(Int($0.y)))" })")
      }

      XCTAssertEqual(proposal.wallShapes, 6)
      let scale = try XCTUnwrap(proposal.scale)
      XCTAssertEqual(scale.ratio, 48, accuracy: 1e-6)
      XCTAssertGreaterThanOrEqual(scale.agreement.agreeing, 1, "the dimension across the top, at least")
      XCTAssertNotEqual(scale.check, .disagrees)

      XCTAssertEqual(proposal.rooms.map(\.slug), ["kitchen", "dining", "office", "patio"])
      let office = proposal.rooms[2]
      XCTAssertEqual(office.status, .outlined)
      XCTAssertEqual(office.outline.count, 4)
      let xs = office.outline.map(\.x).sorted(), ys = office.outline.map(\.y).sorted()
      XCTAssertEqual(xs[0], 283, accuracy: 1.01)
      XCTAssertEqual(xs[3], 454, accuracy: 1.01)
      XCTAssertEqual(ys[0], 106, accuracy: 1.01)
      XCTAssertEqual(ys[3], 310, accuracy: 1.01)
      XCTAssertEqual(proposal.rooms[0].status, .openPlan)
      XCTAssertEqual(proposal.rooms[3].status, .notEnclosed)
    }

    func testAPageThatIsNotThereIsNoSheet() {
      XCTAssertNil(SheetPDF.sheet(data: Data("not a pdf".utf8), page: 0))
    }
  }
#endif
