import Foundation
import XCTest

@testable import VividHomeCore

/// ADR-0031: the outline is what the guided taps are asked against, so its
/// names and its file shape are the contract.
final class RoomOutlineTests: XCTestCase {
  private let size = (width: 1000, height: 800)
  // A rectangle drawn clockwise from the top-left of the page.
  private let box: [[Double]] = [[100, 100], [500, 100], [500, 400], [100, 400]]

  private func placed() -> PlanFile {
    var plan = PlanFile(level: "main", image: "main.png")
    plan.place(room: "kitchen", x: 300, y: 250, in: size)
    return plan
  }

  func testCornersAreNamedByCompassBearingFromTheCentre() {
    XCTAssertEqual(
      RoomOutline.cornerNames(for: box), ["corner-nw", "corner-ne", "corner-se", "corner-sw"])
    // The same room drawn anticlockwise from the bottom-right: same names, by position.
    let reversed: [[Double]] = [[500, 400], [500, 100], [100, 100], [100, 400]]
    XCTAssertEqual(
      RoomOutline.cornerNames(for: reversed), ["corner-se", "corner-ne", "corner-nw", "corner-sw"])
  }

  func testASecondCornerInAQuadrantGetsASuffix() {
    // An L-shaped room: two corners in the north-east.
    let ell: [[Double]] = [[0, 0], [400, 0], [400, 150], [250, 150], [250, 400], [0, 400]]
    XCTAssertEqual(
      RoomOutline.cornerNames(for: ell),
      ["corner-nw", "corner-ne", "corner-ne2", "corner-se", "corner-se2", "corner-sw"])
    XCTAssertTrue(Set(RoomOutline.cornerNames(for: ell)).count == 6, "names are unique")
  }

  func testTooFewOrMalformedPointsHaveNoNames() {
    XCTAssertEqual(RoomOutline.cornerNames(for: [[0, 0], [1, 1]]), [])
    XCTAssertEqual(RoomOutline.cornerNames(for: [[0, 0], [1, 1], [2]]), [])
  }

  func testAnOutlineNeedsThreeCornersInsideTheRasterAndNoRepeats() {
    XCTAssertTrue(RoomOutline.isValid(box, in: size))
    XCTAssertFalse(RoomOutline.isValid([[0, 0], [10, 0]], in: size), "two points is a wall")
    XCTAssertFalse(RoomOutline.isValid([[0, 0], [1001, 0], [10, 10]], in: size), "off the raster")
    XCTAssertFalse(RoomOutline.isValid([[0, 0], [0, 0], [10, 10]], in: size), "a doubled tap")
    XCTAssertFalse(RoomOutline.isValid([[0, 0], [10, 0], [0, 0]], in: size), "closed by hand")
  }

  func testOutliningAPlacedRoomWritesTheContractsKeys() throws {
    var plan = placed()
    XCTAssertTrue(plan.outline(room: "kitchen", points: box, in: size))
    XCTAssertEqual(plan.placement(of: "kitchen")?.outline, box)
    XCTAssertEqual(plan.placement(of: "kitchen")?.cornerNames, ["corner-nw", "corner-ne", "corner-se", "corner-sw"])
    XCTAssertNotNil(plan.placement(of: "kitchen")?.outlinedAt)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(plan), as: UTF8.self)
    XCTAssertTrue(json.contains("\"outline\":[[100,100],[500,100],[500,400],[100,400]]"), json)
    XCTAssertTrue(json.contains("\"outlined_at\""), json)
    let back = try JSONDecoder().decode(PlanFile.self, from: Data(json.utf8))
    XCTAssertEqual(back, plan)
  }

  func testOutliningAnUnplacedRoomOrABadOutlineWritesNothing() {
    var plan = placed()
    XCTAssertFalse(plan.outline(room: "bath", points: box, in: size))
    XCTAssertFalse(plan.outline(room: "kitchen", points: [[0, 0], [1, 1]], in: size))
    XCTAssertNil(plan.placement(of: "kitchen")?.outline)
  }

  func testAPinWithoutAnOutlineStillDecodesAndRePlacingKeepsTheOutline() throws {
    let old = try JSONDecoder().decode(
      PlanFile.self,
      from: Data(
        #"{"level":"main","image":"main.png","rooms":[{"room":"kitchen","x":1,"y":2,"placed_at":"2026-11-03T14:02:11Z"}]}"#
          .utf8))
    XCTAssertNil(old.placement(of: "kitchen")?.outline)
    XCTAssertEqual(old.placement(of: "kitchen")?.cornerNames, [])

    var plan = placed()
    plan.outline(room: "kitchen", points: box, in: size)
    plan.place(room: "kitchen", x: 310, y: 260, in: size)
    XCTAssertEqual(plan.placement(of: "kitchen")?.outline, box, "the pin is the label; moving it keeps the walls")
    XCTAssertEqual(plan.placement(of: "kitchen")?.x, 310)
  }

  func testClearOutline() {
    var plan = placed()
    plan.outline(room: "kitchen", points: box, in: size)
    plan.clearOutline(room: "kitchen")
    XCTAssertNil(plan.placement(of: "kitchen")?.outline)
    XCTAssertNil(plan.placement(of: "kitchen")?.outlinedAt)
  }

  func testHouseCornersComeThroughTheCalibration() throws {
    var plan = try XCTUnwrap(
      placed().calibrated(
        scaleFrom: (100, 100), to: (500, 100), distanceMetres: 4, origin: (100, 400)))
    plan.outline(room: "kitchen", points: box, in: size)
    let corners = try XCTUnwrap(plan.houseCorners(of: "kitchen"))
    XCTAssertEqual(corners.map { $0.label }, ["corner-nw", "corner-ne", "corner-se", "corner-sw"])
    // 0.01 m per pixel, origin at the south-west corner: the north-east corner
    // is 4 m east and 3 m up the page, which is negative v, hence negative z.
    XCTAssertEqual(corners[1].x, 4, accuracy: 1e-9)
    XCTAssertEqual(corners[1].z, -3, accuracy: 1e-9)
    XCTAssertEqual(corners[3].x, 0, accuracy: 1e-9)
    XCTAssertEqual(corners[3].z, 0, accuracy: 1e-9)
    XCTAssertNil(PlanFile(level: "main", image: "main.png").houseCorners(of: "kitchen"))
  }
}
