import Foundation
import XCTest

@testable import VividHomeCore

/// [ADR-0027]: the arrangement of landmarks decides the fit, not the count.
final class AlignmentQualityTests: XCTestCase {

  private func p(_ x: Double, _ z: Double) -> Vector3 { Vector3(x, 0, z) }

  // MARK: - The claim ADR-0027 is built on

  func testTwoWellSpreadPointsBeatThreeInACorner() {
    // The whole reason the count was the wrong measure. The old rule accepted
    // the corner cluster and refused the pair; this must do the opposite on
    // every axis it measures.
    let corner = AlignmentQuality.evaluate([p(0, 0), p(0.3, 0.1), p(0.15, 0.35)])
    let spread = AlignmentQuality.evaluate([p(0, 0), p(5, 4)])

    XCTAssertGreaterThan(spread.spread, corner.spread)
    XCTAssertEqual(corner.verdict, .weak)
    XCTAssertEqual(corner.advice, "These are close together. Add one at the far end of the room.")
  }

  func testCountAloneDecidesNothing() {
    let many = AlignmentQuality.evaluate([p(0, 0), p(0.2, 0), p(0.4, 0), p(0.6, 0), p(0.8, 0)])
    XCTAssertEqual(many.verdict, .weak, "five taps along one short wall is not an alignment")
  }

  // MARK: - Impossible

  func testFewerThanTwoIsImpossible() {
    XCTAssertEqual(AlignmentQuality.evaluate([]).verdict, .impossible)
    XCTAssertEqual(AlignmentQuality.evaluate([p(0, 0)]).verdict, .impossible)
  }

  func testAdviceAtZeroAndOnePointDiffers() {
    XCTAssertEqual(AlignmentQuality.evaluate([]).advice, "Tap a room corner or a door threshold to start.")
    XCTAssertEqual(
      AlignmentQuality.evaluate([p(0, 0)]).advice,
      "One more, as far from the first as the room allows.")
  }

  // MARK: - Spread

  func testSpreadIsTheLargestPairwiseDistance() {
    let report = AlignmentQuality.evaluate([p(0, 0), p(3, 0), p(3, 4)])
    XCTAssertEqual(report.spread, 5, accuracy: 1e-9, "the 3-4-5 diagonal, not an adjacent edge")
  }

  func testShortBaselineIsWeakHoweverManyPoints() {
    let report = AlignmentQuality.evaluate([p(0, 0), p(1, 0), p(0, 1), p(1, 1)])
    XCTAssertEqual(report.verdict, .weak)
    XCTAssertLessThan(report.spread, AlignmentQuality.minimumSpread)
  }

  // MARK: - Balance

  func testCollinearPointsScoreZeroBalance() {
    let report = AlignmentQuality.evaluate([p(0, 0), p(4, 0), p(8, 0)])
    XCTAssertEqual(report.balance, 0, accuracy: 1e-9)
    XCTAssertEqual(report.verdict, .weak)
    XCTAssertEqual(report.advice, "These are nearly in a line. Add one off to the side.")
  }

  func testASquareIsPerfectlyBalanced() {
    let report = AlignmentQuality.evaluate([p(0, 0), p(4, 0), p(4, 4), p(0, 4)])
    XCTAssertEqual(report.balance, 1, accuracy: 1e-9)
    XCTAssertEqual(report.verdict, .good)
    XCTAssertNil(report.advice)
  }

  func testBalanceIsScaleFree() {
    // A hallway and a great room of the same shape must be judged the same.
    let small = AlignmentQuality.evaluate([p(0, 0), p(4, 0), p(4, 2), p(0, 2)])
    let large = AlignmentQuality.evaluate([p(0, 0), p(40, 0), p(40, 20), p(0, 20)])
    XCTAssertEqual(small.balance, large.balance, accuracy: 1e-9)
  }

  func testBalanceIsRotationInvariant() {
    // Nothing may depend on which way the owner happened to start the session,
    // since the world origin is wherever they pressed record.
    let axis = [p(0, 0), p(6, 0), p(6, 3), p(0, 3)]
    let angle = 0.7
    let turned = axis.map {
      p($0.x * cos(angle) - $0.z * sin(angle), $0.x * sin(angle) + $0.z * cos(angle))
    }
    XCTAssertEqual(
      AlignmentQuality.evaluate(axis).balance,
      AlignmentQuality.evaluate(turned).balance, accuracy: 1e-9)
  }

  func testHeightIsIgnored() {
    // The fit is SE(2) plus a z offset, so a landmark on a top plate and one on
    // the subfloor below it are the same point to this.
    let flat = AlignmentQuality.evaluate([p(0, 0), p(5, 0), p(5, 4), p(0, 4)])
    let tall = AlignmentQuality.evaluate([
      Vector3(0, 0, 0), Vector3(5, 2.4, 0), Vector3(5, -1, 4), Vector3(0, 3, 4),
    ])
    XCTAssertEqual(flat, tall)
  }

  // MARK: - Good

  func testAWellWalkedRoomIsGood() {
    let report = AlignmentQuality.evaluate([p(0, 0), p(4.2, 0), p(4.2, 3.6), p(0, 3.6), p(2.1, 0)])
    XCTAssertEqual(report.verdict, .good)
    XCTAssertNil(report.advice)
    XCTAssertEqual(report.count, 5)
  }

  func testThreeGoodPointsStillAskForMore() {
    // Three makes a residual visible; it does not make it small. As-built
    // deviation is per-wall and independent, so averaging is what helps.
    let report = AlignmentQuality.evaluate([p(0, 0), p(5, 0), p(5, 4)])
    XCTAssertEqual(report.verdict, .weak)
    XCTAssertEqual(report.advice, "Good spread. One or two more and the alignment can be checked.")
  }

  // MARK: - Degenerate input

  func testIdenticalPointsDoNotCrashOrScore() {
    let report = AlignmentQuality.evaluate([p(2, 2), p(2, 2), p(2, 2)])
    XCTAssertEqual(report.spread, 0)
    XCTAssertEqual(report.balance, 0)
    XCTAssertEqual(report.verdict, .weak)
  }
}
