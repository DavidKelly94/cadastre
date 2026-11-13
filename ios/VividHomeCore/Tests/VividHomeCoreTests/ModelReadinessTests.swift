import XCTest

@testable import VividHomeCore

/// Enough for 3D (ADR-0035): turning on the spot photographs every wall and
/// is not enough; walking along the walls is.
final class ModelReadinessTests: XCTestCase {
  /// A 4 by 3 m room, corners in order.
  private let room: [(label: String, x: Double, z: Double)] = [
    ("corner-nw", 0, 0), ("corner-ne", 4, 0), ("corner-se", 4, 3), ("corner-sw", 0, 3),
  ]

  /// A camera at a point looking along a direction, with a 30 degree half-angle.
  private func camera(_ x: Double, _ z: Double, toward angle: Double) -> WallCoverage.Camera {
    WallCoverage.Camera(x: x, z: z, forwardX: cos(angle), forwardZ: sin(angle), spread: Double.pi / 6)
  }

  /// Standing still and turning all the way round, a frame every 5 degrees.
  private func turning(at x: Double, _ z: Double) -> [WallCoverage.Camera] {
    stride(from: 0.0, to: 360.0, by: 5.0).map { camera(x, z, toward: $0 * Double.pi / 180) }
  }

  /// Walking a loop half a meter in from the walls, turning all the way
  /// round at each step.
  private func walking() -> [WallCoverage.Camera] {
    var out: [WallCoverage.Camera] = []
    let stops: [(Double, Double)] = [
      (0.6, 0.6), (1.3, 0.6), (2.0, 0.6), (2.7, 0.6), (3.4, 0.6), (3.4, 1.5), (3.4, 2.4), (2.7, 2.4),
      (2.0, 2.4), (1.3, 2.4), (0.6, 2.4), (0.6, 1.5),
    ]
    for (x, z) in stops { out += turning(at: x, z) }
    return out
  }

  private func level(_ count: Int, at height: Double = 1.4) -> [ModelReadiness.View] {
    (0..<count).map { ModelReadiness.View(x: Double($0) * 0.3, y: height, z: 1, forwardY: 0) }
  }

  func testTurningOnTheSpotPhotographsEveryWallAndIsNotEnough() {
    let cameras = turning(at: 2, 1.5)
    let photographed = WallCoverage.coverage(outline: room, cameras: cameras)
    XCTAssertTrue(photographed.allSatisfy { $0.fraction > 0.95 }, "every wall is in a picture")

    let walls = ModelReadiness.wallViews(outline: room, cameras: cameras)
    let report = ModelReadiness.report(views: level(72), walls: walls)
    XCTAssertEqual(report.wallsTwice, 0, "and none of it from a second place")
    XCTAssertFalse(report.enough)
    XCTAssertEqual(report.gaps.count, ModelReadiness.gapsKept)
    XCTAssertEqual(report.gaps[0].wall, "corner-nw->corner-ne", "the longest stretch first")
    XCTAssertEqual(report.gaps[0].lengthM, 4.0, accuracy: 1e-9)
  }

  func testWalkingAlongTheWallsSeesThemFromTwoPlaces() throws {
    let walls = ModelReadiness.wallViews(outline: room, cameras: walking())
    let report = ModelReadiness.report(views: level(40), walls: walls)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(report.wallsTwice), 0.9)
  }

  func testAViewMustBeCloseAndTheBearingsMustSpread() {
    // Two places 0.3 m apart, 2 m from the north wall: about 9 degrees.
    var walls = ModelReadiness.wallViews(
      outline: room,
      cameras: [camera(1.85, 2, toward: -Double.pi / 2), camera(2.15, 2, toward: -Double.pi / 2)])
    XCTAssertFalse(walls[0].seenTwice.contains(true), "too little change of viewpoint")
    XCTAssertTrue(walls[0].seenOnce.contains(true))

    // A meter and a half apart is plenty.
    walls = ModelReadiness.wallViews(
      outline: room,
      cameras: [camera(1.2, 2, toward: -Double.pi / 2), camera(2.8, 2, toward: -Double.pi / 2)])
    XCTAssertTrue(walls[0].seenTwice[20], "the middle of the north wall")

    // The same pair from 2.8 m away never comes within reach of it.
    walls = ModelReadiness.wallViews(
      outline: room,
      cameras: [camera(0.6, 2.8, toward: -Double.pi / 2), camera(3.4, 2.8, toward: -Double.pi / 2)])
    XCTAssertFalse(walls[0].seenTwice.contains(true), "seen twice, but only from across the room")
  }

  func testFloorAndCeilingNeedTiltedViewsFromSeveralPlaces() {
    let tilt = sin(30 * Double.pi / 180)
    func views(_ count: Int, forwardY: Double, spread: Bool) -> [ModelReadiness.View] {
      (0..<count).map {
        ModelReadiness.View(x: spread ? Double($0) * 0.6 : 0.1, y: 1.4, z: 0.1, forwardY: forwardY)
      }
    }
    XCTAssertFalse(ModelReadiness.report(views: level(50), walls: nil).floor)
    XCTAssertTrue(ModelReadiness.report(views: views(12, forwardY: -tilt, spread: true), walls: nil).floor)
    XCTAssertFalse(
      ModelReadiness.report(views: views(12, forwardY: -tilt, spread: false), walls: nil).floor,
      "a dozen looks down from one spot is one look")
    XCTAssertFalse(ModelReadiness.report(views: views(6, forwardY: -tilt, spread: true), walls: nil).floor)
    let up = ModelReadiness.report(views: views(12, forwardY: tilt, spread: true), walls: nil)
    XCTAssertTrue(up.ceiling)
    XCTAssertFalse(up.floor)
  }

  func testASecondHeightIsNoticedAndIsOnlyAdvice() {
    let one = ModelReadiness.report(views: level(40), walls: nil)
    XCTAssertFalse(one.heights)
    let two = ModelReadiness.report(views: level(32) + level(8, at: 2.0), walls: nil)
    XCTAssertTrue(two.heights)
    XCTAssertFalse(two.enough, "height alone does not make a model")
  }

  func testTheLinesSayWhatIsMissingInTheOwnersUnits() {
    let gap = FieldCheck.Walls.Gap(wall: "corner-ne->corner-se", fromM: 1.2, lengthM: 1.5)
    let thin = ModelReadiness.Report(wallsTwice: 0.62, floor: true, ceiling: false, heights: false, gaps: [gap])
    XCTAssertEqual(
      thin.line(in: .imperial),
      FieldCheck.Line(text: "Not enough for 3D yet: walls seen from two spots: 62%; ceiling not seen", ok: false))
    XCTAssertEqual(
      thin.missing(in: .imperial),
      [
        "NE–SE wall: 4 ft 11 in seen from one spot only, starting 3 ft 11 in past NE. "
          + "Step sideways and look again.",
        "Ceiling not seen. Tilt up as you walk.",
      ])
    XCTAssertEqual(
      thin.missing(in: .metric)[0],
      "NE–SE wall: 1.5 m seen from one spot only, starting 1.2 m past NE. Step sideways and look again.")

    let unplaced = ModelReadiness.Report(wallsTwice: nil, floor: true, ceiling: true, heights: true, gaps: [])
    XCTAssertEqual(
      unplaced.line(in: .imperial).text, "Not enough for 3D yet: walls unknown until the capture is placed")
    XCTAssertEqual(unplaced.missing(in: .imperial), [])

    let good = ModelReadiness.Report(wallsTwice: 0.9, floor: true, ceiling: true, heights: false, gaps: [])
    XCTAssertEqual(good.line(in: .metric), FieldCheck.Line(text: "Enough for 3D", ok: true))
    XCTAssertEqual(good.missing(in: .metric), ["One height only. A second pass with the phone raised helps."])
  }

  func testTheReportTravelsInTheLeaveCheck() throws {
    let report = ModelReadiness.Report(
      wallsTwice: 0.62, floor: true, ceiling: false, heights: true,
      gaps: [FieldCheck.Walls.Gap(wall: "corner-ne->corner-se", fromM: 1.2, lengthM: 1.5)])
    let check = FieldCheck(
      placement: FieldCheck.Placement(status: "placed", rmsM: 0.05, corners: 4), walls: nil,
      stills: FieldCheck.Stills(done: 0, total: 0, missing: []), checkedAt: "2026-11-13T00:00:00Z",
      model: report)
    let data = try JSONEncoder().encode(check)
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"walls_twice\":0.62"))
    XCTAssertEqual(try JSONDecoder().decode(FieldCheck.self, from: data), check)
    XCTAssertEqual(check.lines(in: .imperial).count, 4)

    // A check made before this has three lines and no model.
    let old = Data(
      #"{"placement":{"status":"free","corners":0},"stills":{"done":0,"total":0,"missing":[]},"checked_at":"x","together":[]}"#
        .utf8)
    let decoded = try JSONDecoder().decode(FieldCheck.self, from: old)
    XCTAssertNil(decoded.model)
    XCTAssertEqual(decoded.lines(in: .imperial).count, 3)
  }
}
