import Foundation
import XCTest

@testable import CadastreCore

/// Row padding is the top pitfall in the iOS design, so it is tested where tests
/// actually run rather than only on a phone.
final class RowPackerTests: XCTestCase {
  /// A buffer of `height` rows, each `rowBytes` of real data followed by padding.
  /// Real bytes count up from 1; padding is 0xFF so a leak is obvious.
  private func padded(rowBytes: Int, bytesPerRow: Int, height: Int) -> [UInt8] {
    var out = [UInt8]()
    var value: UInt8 = 1
    for _ in 0..<height {
      for _ in 0..<rowBytes {
        out.append(value)
        value = value &+ 1
      }
      out.append(contentsOf: [UInt8](repeating: 0xFF, count: bytesPerRow - rowBytes))
    }
    return out
  }

  func testPaddingIsDiscarded() throws {
    // 4 pixels of Float32 is 16 bytes per row, padded to 32.
    let source = padded(rowBytes: 16, bytesPerRow: 32, height: 3)
    let packed = try RowPacker.pack(source, bytesPerRow: 32, rowBytes: 16, height: 3)

    XCTAssertEqual(packed.count, 48)
    XCTAssertFalse(packed.contains(0xFF), "padding leaked into the packed data")
    XCTAssertEqual(Array(packed[0..<16]), Array(1...16))
    XCTAssertEqual(Array(packed[16..<32]), Array(17...32))
  }

  func testAnUnpaddedBufferCopiesThrough() throws {
    let source = padded(rowBytes: 8, bytesPerRow: 8, height: 4)
    let packed = try RowPacker.pack(source, bytesPerRow: 8, rowBytes: 8, height: 4)
    XCTAssertEqual(packed, source)
  }

  func testTheResultIsExactlyTheSizeTheFormatRequires() throws {
    // session-format.md §11 rule 3: depth is dw*dh*4 bytes, confidence dw*dh.
    let width = 256
    let height = 192
    let depthRow = RowPacker.depthRowBytes(width: width)
    let confidenceRow = RowPacker.confidenceRowBytes(width: width)
    XCTAssertEqual(depthRow, 1024)
    XCTAssertEqual(confidenceRow, 256)

    let depth = try RowPacker.pack(
      padded(rowBytes: depthRow, bytesPerRow: 1088, height: height),
      bytesPerRow: 1088, rowBytes: depthRow, height: height)
    XCTAssertEqual(depth.count, width * height * 4)

    let confidence = try RowPacker.pack(
      padded(rowBytes: confidenceRow, bytesPerRow: 320, height: height),
      bytesPerRow: 320, rowBytes: confidenceRow, height: height)
    XCTAssertEqual(confidence.count, width * height)
  }

  func testTheLastRowNeedNotBePadded() throws {
    // A buffer may end at the last real byte rather than carrying trailing padding.
    var source = padded(rowBytes: 4, bytesPerRow: 8, height: 3)
    source.removeLast(4)
    let packed = try RowPacker.pack(source, bytesPerRow: 8, rowBytes: 4, height: 3)
    XCTAssertEqual(packed.count, 12)
  }

  func testAStrideSmallerThanARowIsRejected() {
    XCTAssertThrowsError(
      try RowPacker.pack([UInt8](repeating: 0, count: 100), bytesPerRow: 4, rowBytes: 8, height: 2)
    ) { error in
      XCTAssertEqual(
        error as? RowPacker.Failure,
        .strideSmallerThanRow(bytesPerRow: 4, rowBytes: 8))
    }
  }

  func testATruncatedSourceIsRejectedRatherThanPaddedWithRubbish() {
    XCTAssertThrowsError(
      try RowPacker.pack([UInt8](repeating: 1, count: 10), bytesPerRow: 8, rowBytes: 8, height: 4)
    ) { error in
      guard case .sourceTooShort = error as? RowPacker.Failure else {
        return XCTFail("expected sourceTooShort, got \(error)")
      }
    }
  }

  func testNonsenseGeometryIsRejected() {
    for (stride, row, height) in [(0, 4, 2), (8, 0, 2), (8, 4, 0)] {
      XCTAssertThrowsError(
        try RowPacker.pack(
          [UInt8](repeating: 0, count: 64), bytesPerRow: stride, rowBytes: row, height: height))
    }
  }

  func testThePointerPathAgreesWithTheArrayPath() throws {
    let source = padded(rowBytes: 12, bytesPerRow: 20, height: 5)
    let expected = try RowPacker.pack(source, bytesPerRow: 20, rowBytes: 12, height: 5)

    let packed = try source.withUnsafeBytes { raw in
      try RowPacker.pack(
        baseAddress: raw.baseAddress!, bytesPerRow: 20, rowBytes: 12, height: 5)
    }
    XCTAssertEqual(Array(packed), expected)
  }

  func testPackedCount() {
    XCTAssertEqual(RowPacker.packedCount(rowBytes: 1024, height: 192), 196_608)
    XCTAssertEqual(RowPacker.packedCount(rowBytes: 256, height: 192), 49_152)
  }
}
