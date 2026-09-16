import XCTest

@testable import VividHomeCore

/// The failure this guards against is quiet: an identifier that carries its
/// buffer's trailing NULs still prints as "iPhone16,1" in a console and still
/// fails every comparison against it.
final class HardwareIdentifierTests: XCTestCase {

  /// A real `utsname.machine`: the text, a NUL, then whatever the buffer held.
  func testStopsAtTheFirstNul() {
    var buffer = Array("iPhone16,1".utf8)
    buffer.append(0)
    buffer.append(contentsOf: [0, 0, 0, 0, 0, 0])
    XCTAssertEqual(HardwareIdentifier.decode(buffer), "iPhone16,1")
  }

  /// Trailing bytes after the terminator are not text and are not included,
  /// even when they are printable. A buffer is not always zeroed.
  func testIgnoresBytesAfterTheTerminator() {
    var buffer = Array("iPad8,12".utf8)
    buffer.append(0)
    buffer.append(contentsOf: Array("junk".utf8))
    XCTAssertEqual(HardwareIdentifier.decode(buffer), "iPad8,12")
  }

  /// A buffer exactly filled, with no room for a terminator.
  func testAcceptsABufferWithNoTerminator() {
    XCTAssertEqual(HardwareIdentifier.decode(Array("iPhone17,2".utf8)), "iPhone17,2")
  }

  func testAZeroedBufferIsNil() {
    XCTAssertNil(HardwareIdentifier.decode([UInt8](repeating: 0, count: 16)))
  }

  func testAnEmptyBufferIsNil() {
    XCTAssertNil(HardwareIdentifier.decode([UInt8]()))
  }

  /// The identifier is ASCII in practice, but decoding must not corrupt the
  /// string if it ever is not; `String(decoding:as:)` substitutes rather than
  /// failing, which is the behaviour this pins.
  func testInvalidUTF8DoesNotProduceNil() {
    let decoded = HardwareIdentifier.decode([0xFF, 0xFE, 0])
    XCTAssertNotNil(decoded)
    XCTAssertFalse(decoded!.isEmpty)
  }
}
