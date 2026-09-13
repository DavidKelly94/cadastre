import XCTest

@testable import CadastreCore

final class CadastreCoreTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(CadastreCore.version.isEmpty)
  }

  /// The version in `docs/session-format.md`'s title, pinned here so the two
  /// cannot drift. Went to 2 when a session gained a set of phases (ADR-0022).
  func testSessionFormatVersionMatchesTheContract() {
    XCTAssertEqual(CadastreCore.sessionFormatVersion, 2)
  }
}
