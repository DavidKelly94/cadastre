import Foundation
import XCTest

@testable import VividHomeCore

/// The live rule is the offline one: range, the frustum's footprint, and
/// nothing seen through a wall.
final class WallCoverageTests: XCTestCase {
  // A 4 x 4 m room, corners NW, NE, SE, SW; north is -z.
  private let room: [(label: String, x: Double, z: Double)] = [
    ("corner-nw", 0, -4), ("corner-ne", 4, -4), ("corner-se", 4, 0), ("corner-sw", 0, 0),
  ]

  /// A camera-to-world pose looking along `heading` (x, z) with no pitch.
  private func pose(at x: Double, _ z: Double, lookingX: Double, lookingZ: Double) -> Transform {
    // The camera looks down its -z axis, so the world z column is -heading.
    let length = (lookingX * lookingX + lookingZ * lookingZ).squareRoot()
    let hx = lookingX / length, hz = lookingZ / length
    // x axis: to the right of the heading, y up, z = -heading.
    let elements: [Double] = [
      -hz, 0, hx, 0,
      0, 1, 0, 0,
      -hx, 0, -hz, 0,
      x, 1.4, z, 1,
    ]
    return Transform(elements: elements)!
  }

  func testACameraInTheMiddleFacingEastPhotographsTheEastWallOnly() throws {
    // 1920 x 1440 with fx 1400: a 69° horizontal field, 34.5° half-spread.
    let camera = try XCTUnwrap(
      WallCoverage.Camera(pose: pose(at: 2, -2, lookingX: 1, lookingZ: 0), fx: 1400, fy: 1400, width: 1920, height: 1440))
    XCTAssertEqual(camera.forwardX, 1, accuracy: 1e-9)
    XCTAssertEqual(camera.forwardZ, 0, accuracy: 1e-9)
    XCTAssertEqual(camera.spread, atan(1920.0 / 2800.0), accuracy: 1e-6)

    let walls = WallCoverage.coverage(outline: room, cameras: [camera])
    XCTAssertEqual(walls.map(\.start), ["corner-nw", "corner-ne", "corner-se", "corner-sw"])
    let east = walls[1]
    // 2 m from the wall with a 34.5° half-spread covers 2 * tan(34.5°) = 2.75 m of the 4 m wall.
    XCTAssertEqual(east.fraction, 0.675, accuracy: 0.05)
    XCTAssertEqual(walls[0].fraction, 0)
    XCTAssertEqual(walls[2].fraction, 0)
    XCTAssertEqual(walls[3].fraction, 0)
    let gaps = east.gaps
    XCTAssertEqual(gaps.count, 2, "a gap at each end of the east wall")
    XCTAssertEqual(gaps[0].from, 0, accuracy: 1e-9)
  }

  func testACameraPointedAtTheFloorPhotographsNothing() {
    // Looking straight down: the forward has no horizontal component.
    let down: [Double] = [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 2, 1.4, -2, 1]
    XCTAssertNil(WallCoverage.Camera(pose: Transform(elements: down)!, fx: 1400, fy: 1400, width: 1920, height: 1440))
  }

  func testAWallBeyondRangeIsNotPhotographed() throws {
    let camera = try XCTUnwrap(
      WallCoverage.Camera(pose: pose(at: 2, -2, lookingX: 1, lookingZ: 0), fx: 1400, fy: 1400, width: 1920, height: 1440))
    let walls = WallCoverage.coverage(outline: room, cameras: [camera], range: 1.5)
    XCTAssertEqual(walls[1].fraction, 0)
  }

  func testNothingIsSeenThroughAWall() throws {
    // An L-shaped room: the camera in the west leg looks east, and the inner
    // wall of the notch hides the far east wall's upper part.
    let ell: [(label: String, x: Double, z: Double)] = [
      ("nw", 0, -4), ("ne", 6, -4), ("ne2", 6, -2), ("se", 3, -2), ("se2", 3, 0), ("sw", 0, 0),
    ]
    let camera = try XCTUnwrap(
      WallCoverage.Camera(pose: pose(at: 1, -1, lookingX: 1, lookingZ: 0), fx: 1400, fy: 1400, width: 1920, height: 1440))
    let walls = WallCoverage.coverage(outline: ell, cameras: [camera], range: 10)
    let farEast = walls[1]  // ne -> ne2, x = 6, z from -4 to -2
    XCTAssertEqual(farEast.fraction, 0, "the notch wall se2-se stands between")
    let notch = walls[3]  // se -> se2, x = 3, z from -2 to 0
    XCTAssertGreaterThan(notch.fraction, 0.5)
  }

  func testAddingCamerasAccumulates() throws {
    var walls = WallCoverage.walls(outline: room)
    let east = try XCTUnwrap(
      WallCoverage.Camera(pose: pose(at: 2, -2, lookingX: 1, lookingZ: 0), fx: 1400, fy: 1400, width: 1920, height: 1440))
    let west = try XCTUnwrap(
      WallCoverage.Camera(pose: pose(at: 2, -2, lookingX: -1, lookingZ: 0), fx: 1400, fy: 1400, width: 1920, height: 1440))
    WallCoverage.add(east, to: &walls)
    XCTAssertEqual(walls[3].fraction, 0)
    WallCoverage.add(west, to: &walls)
    XCTAssertGreaterThan(walls[3].fraction, 0.6)
    XCTAssertGreaterThan(walls[1].fraction, 0.6, "the east wall is still covered")
  }

  func testACameraMovesIntoTheHouseFrameWithThePlacement() throws {
    // A placement that rotates 90° (session +x becomes house +z) and shifts by (1, 2).
    let pairs = [
      PlanAlignment.Pair(label: "a", sessionXZ: (0, 0), houseXZ: (1, 2)),
      PlanAlignment.Pair(label: "b", sessionXZ: (1, 0), houseXZ: (1, 3)),
      PlanAlignment.Pair(label: "c", sessionXZ: (0, 1), houseXZ: (0, 2)),
    ]
    let placement = try XCTUnwrap(PlanAlignment.solve(pairs: pairs, floorY: 0, floorSource: "x", floorHeight: 0))
    let camera = WallCoverage.Camera(x: 1, z: 0, forwardX: 1, forwardZ: 0, spread: 0.5)
    let moved = camera.moved(by: placement)
    XCTAssertEqual(moved.x, 1, accuracy: 1e-9)
    XCTAssertEqual(moved.z, 3, accuracy: 1e-9)
    XCTAssertEqual(moved.forwardX, 0, accuracy: 1e-9)
    XCTAssertEqual(moved.forwardZ, 1, accuracy: 1e-9)
    XCTAssertEqual(moved.spread, 0.5)
  }
}
