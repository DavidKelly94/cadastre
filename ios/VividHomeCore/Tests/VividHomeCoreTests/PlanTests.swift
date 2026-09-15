import Foundation
import XCTest

@testable import VividHomeCore

/// `docs/session-format.md` §13, the project-level plan file.
final class PlanTests: XCTestCase {

  private let size = (width: 800, height: 600)

  private func decode(_ json: String) throws -> PlanFile {
    try JSONDecoder().decode(PlanFile.self, from: Data(json.utf8))
  }

  // MARK: - The contract's field names

  func testKeysMatchThePipelineExactly() throws {
    var plan = PlanFile(level: "main", image: "main.png")
    plan.place(room: "kitchen", x: 400, y: 300, in: size)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(plan), as: UTF8.self)

    // A second spelling of any of these is how two sides of one contract drift.
    for key in ["\"level\"", "\"image\"", "\"rotation_deg\"", "\"floor_height_m\"", "\"rooms\"", "\"placed_at\""] {
      XCTAssertTrue(json.contains(key), "missing \(key) in \(json)")
    }
    XCTAssertFalse(json.contains("calibrated"), "calibration is derived, never a stored flag")
  }

  func testAPlanFromAnOlderPlanAddDecodes() throws {
    // No source, no rooms — exactly what `vividhome plan add` has always written.
    let plan = try decode("""
      {"level":"main","image":"main.png","metres_per_pixel":null,"origin_px":null,
       "rotation_deg":0.0,"floor_height_m":0.0}
      """)
    XCTAssertEqual(plan.level, "main")
    XCTAssertTrue(plan.rooms.isEmpty)
    XCTAssertNil(plan.source)
    XCTAssertFalse(plan.isCalibrated)
  }

  func testUnknownFieldsAreIgnored() throws {
    // §12: readers ignore what they do not know, which is what makes §13 additive.
    let plan = try decode("""
      {"level":"main","image":"main.png","something_a_future_client_added":true,
       "rooms":[{"room":"kitchen","x":10,"y":20,"placed_at":"2026-11-03T14:02:11Z"}]}
      """)
    XCTAssertEqual(plan.rooms.count, 1)
    XCTAssertEqual(plan.rooms[0].room, "kitchen")
  }

  // MARK: - Calibration is derived, not stored

  func testCalibrationIsThePresenceOfBothNumbers() {
    var plan = PlanFile(level: "main", image: "main.png")
    XCTAssertFalse(plan.isCalibrated)
    XCTAssertFalse(plan.isHalfCalibrated)

    plan.metresPerPixel = 0.01
    XCTAssertFalse(plan.isCalibrated, "a scale with no origin is not calibrated")
    XCTAssertTrue(plan.isHalfCalibrated)

    plan.originPx = [100, 200]
    XCTAssertTrue(plan.isCalibrated)
    XCTAssertFalse(plan.isHalfCalibrated)
  }

  func testTheAppNeverWritesCalibration() {
    // The app solves nothing, so everything it writes is uncalibrated.
    var plan = PlanFile(level: "main", image: "main.png")
    plan.place(room: "kitchen", x: 1, y: 1, in: size)
    XCTAssertNil(plan.metresPerPixel)
    XCTAssertNil(plan.originPx)
  }

  // MARK: - Placing a room

  func testPlacingIsIdempotentPerRoom() {
    var plan = PlanFile(level: "main", image: "main.png")
    XCTAssertTrue(plan.place(room: "kitchen", x: 10, y: 10, in: size))
    XCTAssertTrue(plan.place(room: "kitchen", x: 40, y: 50, in: size))

    // Rule 4 refuses a level with the same slug twice: a second placement is a
    // correction, not a second room.
    XCTAssertEqual(plan.rooms.count, 1)
    XCTAssertEqual(plan.placement(of: "kitchen")?.x, 40)
  }

  func testOutOfBoundsIsRefusedRatherThanWritten() {
    var plan = PlanFile(level: "main", image: "main.png")
    XCTAssertFalse(plan.place(room: "kitchen", x: 900, y: 300, in: size))
    XCTAssertFalse(plan.place(room: "kitchen", x: 400, y: -1, in: size))
    XCTAssertTrue(plan.rooms.isEmpty, "validate --project should never see it")
  }

  func testEdgesAreInside() {
    var plan = PlanFile(level: "main", image: "main.png")
    XCTAssertTrue(plan.place(room: "corner", x: 0, y: 0, in: size))
    XCTAssertTrue(plan.place(room: "far", x: 800, y: 600, in: size))
  }

  func testABadSlugIsRefused() {
    var plan = PlanFile(level: "main", image: "main.png")
    XCTAssertFalse(plan.place(room: "Not A Slug", x: 10, y: 10, in: size))
    XCTAssertFalse(plan.place(room: "kitchen_1", x: 10, y: 10, in: size), "underscores split ids")
    XCTAssertTrue(plan.rooms.isEmpty)
  }

  func testUnplace() {
    var plan = PlanFile(level: "main", image: "main.png")
    plan.place(room: "kitchen", x: 10, y: 10, in: size)
    plan.place(room: "garage", x: 20, y: 20, in: size)
    plan.unplace(room: "kitchen")
    XCTAssertEqual(plan.rooms.map(\.room), ["garage"])
  }

  func testPlacedAtIsUTCInternetDateTime() {
    var plan = PlanFile(level: "main", image: "main.png")
    plan.place(room: "kitchen", x: 1, y: 1, in: size, at: Date(timeIntervalSince1970: 1_793_000_531))
    XCTAssertEqual(plan.placement(of: "kitchen")?.placedAt, "2026-10-26T07:42:11Z")
  }

  // MARK: - Round trip

  func testRoundTripPreservesEverything() throws {
    var plan = PlanFile(
      level: "main", image: "main.png", metresPerPixel: 0.012, originPx: [12.5, 33],
      rotationDegrees: 1.5, floorHeight: 2.7,
      source: PlanSource(file: "main.source.pdf", kind: .pdf, page: 2))
    plan.place(room: "kitchen", x: 400, y: 300, in: size)

    let data = try JSONEncoder().encode(plan)
    let back = try JSONDecoder().decode(PlanFile.self, from: data)
    XCTAssertEqual(plan, back)
  }
}
