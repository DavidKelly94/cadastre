import Foundation
import XCTest

@testable import VividHomeCore

/// Corners found in the scan and matched to the outline (ADR-0034). What
/// comes out is a proposal for the owner to confirm, never a placement.
final class CornerFinderTests: XCTestCase {
  private let wallClass: UInt8 = 1
  private let noClass: UInt8 = 0

  /// A vertical rectangle of mesh between two floor points.
  private func wall(
    _ p: (Double, Double), _ q: (Double, Double), floor: Double = 0, height: Double = 2.4,
    class classification: UInt8 = 1
  ) -> [CornerSnap.Face] {
    let a = Vector3(p.0, floor, p.1), b = Vector3(q.0, floor, q.1)
    let c = Vector3(q.0, floor + height, q.1), d = Vector3(p.0, floor + height, p.1)
    return [
      CornerSnap.Face(a: a, b: b, c: c, classification: classification),
      CornerSnap.Face(a: a, b: c, c: d, classification: classification),
    ]
  }

  /// The walls of a closed shape, corner to corner.
  private func room(_ corners: [(Double, Double)], class classification: UInt8 = 1) -> [CornerSnap.Face] {
    corners.indices.flatMap { index in
      wall(corners[index], corners[(index + 1) % corners.count], class: classification)
    }
  }

  private let rectangle: [(Double, Double)] = [(0, 0), (4, 0), (4, 3), (0, 3)]
  private let ell: [(Double, Double)] = [(0, 0), (5, 0), (5, 2), (3, 2), (3, 4), (0, 4)]

  private func outline(_ corners: [(Double, Double)], turnedBy turn: Double = 0, shift: (Double, Double) = (0, 0))
    -> [(label: String, x: Double, z: Double)]
  {
    let names = RoomOutline.cornerNames(for: corners.map { [$0.0, $0.1] })
    return corners.enumerated().map { index, corner in
      let x = cos(turn) * corner.0 - sin(turn) * corner.1 + shift.0
      let z = sin(turn) * corner.0 + cos(turn) * corner.1 + shift.1
      return (names[index], x, z)
    }
  }

  private func near(_ candidates: [CornerFinder.Candidate], _ x: Double, _ z: Double) -> Bool {
    candidates.contains { abs($0.x - x) < 0.02 && abs($0.z - z) < 0.02 }
  }

  // MARK: - Finding

  func testEveryCornerOfARoomIsFoundWithItsHeights() {
    let found = CornerFinder.candidates(faces: room(rectangle))
    XCTAssertEqual(found.count, 4)
    for corner in rectangle { XCTAssertTrue(near(found, corner.0, corner.1), "\(corner)") }
    XCTAssertEqual(found[0].bottom, 0, accuracy: 1e-9)
    XCTAssertEqual(found[0].top, 2.4, accuracy: 1e-9, "the ceiling end of the same corner")
  }

  func testWallsNobodyClassedAreStillWalls() {
    // Open framing: ARKit calls none of it wall.
    let found = CornerFinder.candidates(faces: room(rectangle, class: noClass))
    XCTAssertEqual(found.count, 4)
  }

  func testACabinetIsNotACornerOfTheRoom() {
    // A 0.6 m wide, 0.7 m tall box front against the north wall.
    let cabinet = wall((1, 0.6), (1.6, 0.6), height: 0.7) + wall((1, 0), (1, 0.6), height: 0.7)
    let found = CornerFinder.candidates(faces: room(rectangle) + cabinet)
    XCTAssertEqual(found.count, 4, "\(found)")
  }

  func testAnLShapedRoomHasSixCorners() {
    let found = CornerFinder.candidates(faces: room(ell))
    for corner in ell { XCTAssertTrue(near(found, corner.0, corner.1), "\(corner)") }
  }

  // MARK: - Matching

  func testAnLShapedRoomFitsItsOutlineOneWay() throws {
    // The plan has the room turned and somewhere else: the scan's frame is
    // arbitrary, which is the whole problem.
    let plan = outline(ell, turnedBy: 0.7, shift: (12, -3))
    let proposal = try XCTUnwrap(
      CornerMatch.propose(candidates: CornerFinder.candidates(faces: room(ell)), outline: plan))
    XCTAssertEqual(proposal.fit.marks.count, 6)
    XCTAssertEqual(proposal.missing, [])
    XCTAssertFalse(proposal.isAmbiguous, "an L only fits one way round")
    XCTAssertLessThan(proposal.fit.rms, 0.01)
    // Each mark is the scan's corner for that name.
    for (index, mark) in proposal.fit.marks.enumerated() {
      XCTAssertEqual(mark.label, plan[index].label)
      XCTAssertEqual(mark.x, ell[index].0, accuracy: 0.02)
      XCTAssertEqual(mark.z, ell[index].1, accuracy: 0.02)
    }
  }

  func testARectangleFitsTwoWaysAndSaysSo() throws {
    let plan = outline(rectangle, turnedBy: -0.4, shift: (2, 9))
    let proposal = try XCTUnwrap(
      CornerMatch.propose(candidates: CornerFinder.candidates(faces: room(rectangle)), outline: plan))
    XCTAssertEqual(proposal.fit.marks.count, 4)
    XCTAssertTrue(proposal.isAmbiguous)
    XCTAssertEqual(proposal.alternatives.count, 1, "the other way round, and only that")
    // The two fits name each corner differently: what one calls NW the other calls SE.
    let first = proposal.fit.marks.first { $0.label == "corner-nw" }
    let second = proposal.alternatives[0].marks.first { $0.label == "corner-se" }
    XCTAssertEqual(first?.x, second?.x)
    XCTAssertEqual(first?.z, second?.z)
  }

  func testAHiddenCornerIsNamedForTheOwnerToTap() throws {
    // The south-west corner is behind something: its two walls stop short.
    let faces = wall((0, 0), (4, 0)) + wall((4, 0), (4, 3)) + wall((4, 3), (1.2, 3)) + wall((0, 0), (0, 1.8))
    let found = CornerFinder.candidates(faces: faces)
    XCTAssertEqual(found.count, 3, "\(found)")
    let proposal = try XCTUnwrap(CornerMatch.propose(candidates: found, outline: outline(rectangle)))
    XCTAssertEqual(proposal.fit.marks.count, 3)
    XCTAssertEqual(proposal.missing.count, 1)
  }

  func testAStrayCornerIsLeftOutAndNoiseIsAbsorbed() throws {
    var found = CornerFinder.candidates(faces: room(ell))
    found = found.map {
      CornerFinder.Candidate(x: $0.x + 0.03, z: $0.z - 0.02, bottom: $0.bottom, top: $0.top, support: $0.support)
    }
    found.append(CornerFinder.Candidate(x: 1.7, z: 1.1, bottom: 0, top: 0.9, support: 0.6))
    let proposal = try XCTUnwrap(CornerMatch.propose(candidates: found, outline: outline(ell)))
    XCTAssertEqual(proposal.fit.marks.count, 6)
    XCTAssertFalse(proposal.fit.marks.contains { abs($0.x - 1.7) < 0.01 })
  }

  func testOneCornerAloneProposesNothing() {
    let one = [CornerFinder.Candidate(x: 0, z: 0, bottom: 0, top: 2.4, support: 3)]
    XCTAssertNil(CornerMatch.propose(candidates: one, outline: outline(rectangle)))
    XCTAssertNil(CornerMatch.propose(candidates: [], outline: outline(rectangle)))
  }

  func testCornersThatFitNoOutlineProposeNothing() {
    // A 2 by 2 m room against a 4 by 3 m outline: no pair is the right distance apart.
    let small = CornerFinder.candidates(faces: room([(0, 0), (2, 0), (2, 2), (0, 2)]))
    XCTAssertNil(CornerMatch.propose(candidates: small, outline: outline(rectangle)))
  }
}
