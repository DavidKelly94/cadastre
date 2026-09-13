import XCTest

@testable import CadastreCore

final class CadastreCoreTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(CadastreCore.version.isEmpty)
  }

  func testSessionFormatVersionMatchesTheContract() {
    XCTAssertEqual(CadastreCore.sessionFormatVersion, 1)
  }
}
