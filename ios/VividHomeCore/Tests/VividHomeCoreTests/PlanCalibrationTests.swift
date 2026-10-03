import Foundation
import XCTest

@testable import VividHomeCore

/// A plan calibrated on the phone is read by the PC, so the numbers here are
/// the ones `plan.py` produced for the same inputs, to the micrometre.
final class PlanCalibrationTests: XCTestCase {
  private let plan = PlanFile(level: "main", image: "main.png")

  func testTheScaleIsTheDistanceOverThePixels() throws {
    let calibrated = try XCTUnwrap(
      plan.calibrated(
        scaleFrom: (100, 100), to: (600, 100), distanceMetres: 5, origin: (100, 100)))
    XCTAssertEqual(calibrated.metresPerPixel!, 0.01, accuracy: 1e-12)
    XCTAssertEqual(calibrated.originPx, [100, 100])
    XCTAssertTrue(calibrated.isCalibrated)
    XCTAssertEqual(calibrated.widthMetres(imageWidth: 3000)!, 30, accuracy: 1e-9)
    XCTAssertEqual(calibrated.rotationDegrees, 0)
    XCTAssertEqual(calibrated.floorHeight, 0)
  }

  func testTwoCoincidentPointsOrANonPositiveDistanceIsNoCalibration() {
    XCTAssertNil(plan.calibrated(scaleFrom: (10, 10), to: (10, 10), distanceMetres: 5, origin: (0, 0)))
    XCTAssertNil(plan.calibrated(scaleFrom: (0, 0), to: (10, 0), distanceMetres: 0, origin: (0, 0)))
    XCTAssertNil(plan.calibrated(scaleFrom: (0, 0), to: (10, 0), distanceMetres: -1, origin: (0, 0)))
    XCTAssertNil(plan.houseToPlan(x: 1, z: 1), "uncalibrated: nothing to project with")
    XCTAssertNil(plan.planToHouse(u: 1, v: 1))
  }

  func testTheProjectionsMatchThePipelineWithRotation() throws {
    // plan.py, metres_per_pixel 0.01, origin (100, 100), rotation 30°:
    //   house_to_plan(2, 3)   = (123.20508075688777, 459.8076211353316)
    //   plan_to_house(400, 250) = (3.348076211353316, -0.20096189432334183)
    let calibrated = try XCTUnwrap(
      plan.calibrated(
        scaleFrom: (100, 100), to: (600, 100), distanceMetres: 5, origin: (100, 100),
        rotationDegrees: 30))
    let pixel = try XCTUnwrap(calibrated.houseToPlan(x: 2, z: 3))
    XCTAssertEqual(pixel.u, 123.20508075688777, accuracy: 1e-9)
    XCTAssertEqual(pixel.v, 459.8076211353316, accuracy: 1e-9)
    let house = try XCTUnwrap(calibrated.planToHouse(u: 400, v: 250))
    XCTAssertEqual(house.x, 3.348076211353316, accuracy: 1e-9)
    XCTAssertEqual(house.z, -0.20096189432334183, accuracy: 1e-9)
    // And back again.
    let back = try XCTUnwrap(calibrated.planToHouse(u: pixel.u, v: pixel.v))
    XCTAssertEqual(back.x, 2, accuracy: 1e-9)
    XCTAssertEqual(back.z, 3, accuracy: 1e-9)
  }

  func testACalibratedPlanRoundTripsThroughTheContractsKeys() throws {
    let calibrated = try XCTUnwrap(
      plan.calibrated(scaleFrom: (0, 0), to: (0, 200), distanceMetres: 4, origin: (10, 20),
        rotationDegrees: 90, floorHeight: 3.2))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(calibrated), as: UTF8.self)
    XCTAssertTrue(json.contains("\"metres_per_pixel\":0.02"), json)
    XCTAssertTrue(json.contains("\"origin_px\":[10,20]"), json)
    XCTAssertTrue(json.contains("\"rotation_deg\":90"), json)
    XCTAssertTrue(json.contains("\"floor_height_m\":3.2"), json)
    let decoded = try JSONDecoder().decode(PlanFile.self, from: Data(json.utf8))
    XCTAssertEqual(decoded, calibrated)
  }

  // MARK: - Distances as typed

  func testDistancesParseAsThePipelineParsesThem() {
    let cases: [(String, Double)] = [
      ("3.81m", 3.81), ("381cm", 3.81), ("3810mm", 3.81), ("3.81", 3.81),
      ("12' 6\"", 3.81), ("12'6\"", 3.81), ("6\"", 0.1524), ("12'", 3.6576),
      ("11'-6\"", 3.5052), ("25'-0\"", 7.62), ("11' 6 1/2\"", 3.5179),
      ("31'-11 5/8\"", 9.744075), ("5/8\"", 0.015875), ("12′ 6″", 3.81),
      ("  2 m ", 2), ("0.5M", 0.5),
    ]
    for (text, metres) in cases {
      XCTAssertEqual(PlanDistance.metres(from: text) ?? -1, metres, accuracy: 1e-6, text)
    }
  }

  func testNonsenseIsNotADistance() {
    for bad in ["", "   ", "about three metres", "m", "12' x\"", "1/0\"", "cm"] {
      XCTAssertNil(PlanDistance.metres(from: bad), bad)
    }
  }
}
