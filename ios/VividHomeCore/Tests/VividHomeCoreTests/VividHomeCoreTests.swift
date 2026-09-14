import XCTest

@testable import VividHomeCore

final class VividHomeCoreTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(VividHomeCore.version.isEmpty)
  }

  /// The version in `docs/session-format.md`'s title, pinned here so the two
  /// cannot drift. Went to 2 when a session gained a set of phases (ADR-0022).
  func testSessionFormatVersionMatchesTheContract() {
    XCTAssertEqual(VividHomeCore.sessionFormatVersion, 3)
  }
}
