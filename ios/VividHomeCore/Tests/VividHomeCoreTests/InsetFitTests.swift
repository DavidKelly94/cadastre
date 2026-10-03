import Foundation
import XCTest

@testable import VividHomeCore

final class InsetFitTests: XCTestCase {
  func testARoomFillsTheBoxCentredWithItsMargin() throws {
    // A 4 x 3 m room, north at -z, into a 120 x 120 box with a 10 pt margin:
    // the wider axis sets the scale, 100 / 4 = 25 pt per metre.
    let corners: [(x: Double, z: Double)] = [(0, -3), (4, -3), (4, 0), (0, 0)]
    let fit = try XCTUnwrap(InsetFit(points: corners, width: 120, height: 120, margin: 10))
    XCTAssertEqual(fit.scale, 25, accuracy: 1e-9)
    let nw = fit.point(x: 0, z: -3)
    let se = fit.point(x: 4, z: 0)
    XCTAssertEqual(nw.x, 10, accuracy: 1e-9)
    XCTAssertEqual(se.x, 110, accuracy: 1e-9)
    // 3 m tall is 75 pt, centred in 120: from 22.5 to 97.5, north at the top.
    XCTAssertEqual(nw.y, 22.5, accuracy: 1e-9)
    XCTAssertEqual(se.y, 97.5, accuracy: 1e-9)
  }

  func testNothingToFitIsNoFit() {
    XCTAssertNil(InsetFit(points: [], width: 120, height: 120, margin: 10))
    XCTAssertNil(InsetFit(points: [(0, 0)], width: 20, height: 120, margin: 10))
  }

  func testASinglePointStillHasAPlace() throws {
    let fit = try XCTUnwrap(InsetFit(points: [(2, 2)], width: 100, height: 100, margin: 10))
    let point = fit.point(x: 2, z: 2)
    XCTAssertEqual(point.x, 50, accuracy: 1e-6)
    XCTAssertEqual(point.y, 50, accuracy: 1e-6)
  }
}
