import XCTest

@testable import VividHomeCore

/// Lengths as the owner reads them. `units.py` writes the same text and the
/// contract job compares the two over a longer table.
final class UnitsTests: XCTestCase {
  func testASmallDistance() {
    let cases: [(Double, String, String)] = [
      (0.0, "0 in", "0 cm"),
      (0.006, "1/4 in", "1 cm"),
      (0.068, "2 3/4 in", "7 cm"),
      (0.0762, "3 in", "8 cm"),
      (0.18, "7 in", "18 cm"),
      (0.30, "11 3/4 in", "30 cm"),
      (0.314, "1 ft", "31 cm"),
    ]
    for (meters, imperial, metric) in cases {
      XCTAssertEqual(Units.imperial.small(meters), imperial, "\(meters)")
      XCTAssertEqual(Units.metric.small(meters), metric, "\(meters)")
    }
  }

  func testALength() {
    let cases: [(Double, String, String)] = [
      (0.2, "8 in", "0.2 m"),
      (0.3048, "1 ft", "0.3 m"),
      (0.8, "2 ft 7 in", "0.8 m"),
      (1.9, "6 ft 3 in", "1.9 m"),
      (3.1242, "10 ft 3 in", "3.1 m"),
      (33.2, "108 ft 11 in", "33.2 m"),
    ]
    for (meters, imperial, metric) in cases {
      XCTAssertEqual(Units.imperial.length(meters), imperial, "\(meters)")
      XCTAssertEqual(Units.metric.length(meters), metric, "\(meters)")
    }
  }

  func testAnAreaAndAPlanScale() {
    XCTAssertEqual(Units.imperial.area(10), "108 sq ft")
    XCTAssertEqual(Units.metric.area(10), "10.0 m²")
    XCTAssertEqual(Units.imperial.perPixel(0.0127), "0.50 in per pixel")
    XCTAssertEqual(Units.metric.perPixel(0.0127), "12.7 mm per pixel")
    XCTAssertEqual(Units.imperial.perPixel(0.0017), "0.07 in per pixel")
  }

  /// The leave check in the owner's units: the same numbers, read in feet.
  func testTheLeaveCheckSpeaksEitherWay() {
    let check = FieldCheck(
      placement: FieldCheck.Placement(status: "check", rmsM: 0.18, corners: 2),
      walls: FieldCheck.Walls(
        photographed: 4, total: 5,
        gaps: [FieldCheck.Walls.Gap(wall: "corner-nw->corner-ne", fromM: 1.9, lengthM: 0.8)]),
      stills: FieldCheck.Stills(done: 0, total: 0, missing: []), checkedAt: "2026-11-13T00:00:00Z")
    XCTAssertEqual(check.lines(in: .imperial)[0].text, "Check the corners: 7 in off")
    XCTAssertEqual(
      check.lines(in: .imperial)[1].text,
      "Walls photographed: 4 of 5; NW–NE wall, 2 ft 7 in not photographed from 6 ft 3 in past NW")
    XCTAssertEqual(check.lines(in: .metric)[0].text, "Check the corners: 18 cm off")
  }
}
