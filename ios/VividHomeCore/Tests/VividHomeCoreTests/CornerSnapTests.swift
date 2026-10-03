import Foundation
import XCTest

@testable import VividHomeCore

/// A tap near where two mesh walls meet moves to the corner; anything else
/// stays where the finger put it.
final class CornerSnapTests: XCTestCase {
  private let wall: UInt8 = 1
  private let floor: UInt8 = 2

  /// A vertical rectangle of wall as two triangles, between two floor points.
  private func wallPatch(from p: (Double, Double), to q: (Double, Double), floorY: Double, height: Double = 1.0)
    -> [CornerSnap.Face]
  {
    let a = Vector3(p.0, floorY, p.1)
    let b = Vector3(q.0, floorY, q.1)
    let c = Vector3(q.0, floorY + height, q.1)
    let d = Vector3(p.0, floorY + height, p.1)
    return [
      CornerSnap.Face(a: a, b: b, c: c, classification: wall),
      CornerSnap.Face(a: a, b: c, c: d, classification: wall),
    ]
  }

  private func floorPatch(x: ClosedRange<Double>, z: ClosedRange<Double>, y: Double) -> [CornerSnap.Face] {
    let a = Vector3(x.lowerBound, y, z.lowerBound)
    let b = Vector3(x.upperBound, y, z.lowerBound)
    let c = Vector3(x.upperBound, y, z.upperBound)
    let d = Vector3(x.lowerBound, y, z.upperBound)
    return [
      CornerSnap.Face(a: a, b: b, c: c, classification: floor),
      CornerSnap.Face(a: a, b: c, c: d, classification: floor),
    ]
  }

  /// Two walls meeting at (0, 0): one along x (at z = 0), one along z (at x = 0).
  private func cornerRoom(floorY: Double = -1.4) -> [CornerSnap.Face] {
    wallPatch(from: (0, 0), to: (1.2, 0), floorY: floorY)
      + wallPatch(from: (0, 0), to: (0, 1.2), floorY: floorY)
      + floorPatch(x: 0...1.2, z: 0...1.2, y: floorY)
  }

  func testATapNearTheCornerMovesToIt() throws {
    let tap = Vector3(0.07, -1.33, 0.05)
    let snap = try XCTUnwrap(CornerSnap.snap(tap: tap, faces: cornerRoom()))
    XCTAssertEqual(snap.position.x, 0, accuracy: 1e-9)
    XCTAssertEqual(snap.position.z, 0, accuracy: 1e-9)
    XCTAssertEqual(snap.position.y, -1.4, accuracy: 1e-9, "down onto the floor faces")
    XCTAssertEqual(snap.floorSource, "floor-faces")
    XCTAssertEqual(snap.movedBy, (0.07 * 0.07 + 0.07 * 0.07 + 0.05 * 0.05).squareRoot(), accuracy: 1e-9)
  }

  func testWithoutFloorFacesTheWallBottomsAreTheFloor() throws {
    let faces = wallPatch(from: (0, 0), to: (1.2, 0), floorY: -1.4) + wallPatch(from: (0, 0), to: (0, 1.2), floorY: -1.4)
    let snap = try XCTUnwrap(CornerSnap.snap(tap: Vector3(0.05, -1.2, 0.05), faces: faces))
    XCTAssertEqual(snap.position.y, -1.4, accuracy: 1e-9)
    XCTAssertEqual(snap.floorSource, "wall-bottoms")
  }

  func testOneWallIsNotACorner() {
    let faces = wallPatch(from: (0, 0), to: (1.2, 0), floorY: -1.4)
    XCTAssertNil(CornerSnap.snap(tap: Vector3(0.3, -1.3, 0.05), faces: faces))
  }

  func testParallelWallsDoNotMakeACorner() {
    let faces = wallPatch(from: (0, 0), to: (1.2, 0), floorY: -1.4) + wallPatch(from: (0, 0.4), to: (1.2, 0.4), floorY: -1.4)
    XCTAssertNil(CornerSnap.snap(tap: Vector3(0.3, -1.3, 0.2), faces: faces))
  }

  func testACornerBeyondReachIsNotTheOneTapped() {
    XCTAssertNil(CornerSnap.snap(tap: Vector3(0.6, -1.3, 0.6), faces: cornerRoom()))
  }

  func testClutterCalledWallIsIgnored() throws {
    // A 20 cm box against the wall, every face classified wall: too small to be one.
    var faces = cornerRoom()
    faces += wallPatch(from: (0.5, 0.2), to: (0.7, 0.2), floorY: -1.4, height: 0.2)
    faces += wallPatch(from: (0.7, 0.2), to: (0.7, 0.4), floorY: -1.4, height: 0.2)
    let snap = try XCTUnwrap(CornerSnap.snap(tap: Vector3(0.6, -1.3, 0.25), faces: faces))
    XCTAssertEqual(snap.position.x, 0, accuracy: 1e-9, "the box's corner at (0.7, 0.2) is not a wall corner")
    XCTAssertEqual(snap.position.z, 0, accuracy: 1e-9)
  }

  func testTheWallsAreNotAskedToMeetWhereNeitherRuns() {
    // Two walls at right angles whose lines cross 0.6 m past both of their ends.
    let faces = wallPatch(from: (0.6, 0), to: (1.8, 0), floorY: -1.4) + wallPatch(from: (0, 0.6), to: (0, 1.8), floorY: -1.4)
    XCTAssertNil(CornerSnap.snap(tap: Vector3(0.1, -1.3, 0.1), faces: faces))
  }

  func testFoldingAndAngles() {
    XCTAssertEqual(CornerSnap.fold(.pi), 0, accuracy: 1e-12)
    XCTAssertEqual(CornerSnap.fold(-0.1), .pi - 0.1, accuracy: 1e-12)
    XCTAssertEqual(CornerSnap.angularDistance(0.05, .pi - 0.05), 0.1, accuracy: 1e-12)
    let walls = CornerSnap.findWalls(cornerRoom())
    XCTAssertEqual(walls.count, 2)
    XCTAssertEqual(walls[0].area, 1.2, accuracy: 1e-9)
  }
}
