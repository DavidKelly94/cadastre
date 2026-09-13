import Foundation

/// Copying a padded image buffer into the tightly packed form the format stores.
///
/// `CVPixelBufferGetBytesPerRow` can exceed `width * bytesPerPixel`: the buffer is
/// padded so each row starts on an alignment boundary. Writing the buffer out
/// wholesale therefore produces a file that is the right size only by accident,
/// and whose rows drift sideways when read back — a depth map that looks almost
/// right and is wrong everywhere.
///
/// `docs/session-format.md` §5 requires tightly packed rows, and this is the one
/// place that knows it. The ARKit layer locks the buffer and calls in here, so
/// the rule is tested on Linux rather than only on a phone.
public enum RowPacker {
  public enum Failure: Error, Equatable {
    /// A row of `rowBytes` cannot come from a buffer whose stride is smaller.
    case strideSmallerThanRow(bytesPerRow: Int, rowBytes: Int)
    /// The source is shorter than `height` rows of `bytesPerRow`.
    case sourceTooShort(expected: Int, actual: Int)
    case invalidGeometry
  }

  /// Number of bytes the packed result will hold.
  public static func packedCount(rowBytes: Int, height: Int) -> Int {
    rowBytes * height
  }

  /// Copy `height` rows of `rowBytes` out of a buffer whose rows are
  /// `bytesPerRow` apart, discarding the padding.
  ///
  /// A stride equal to the row length is the unpadded case and copies straight
  /// through; it is not special-cased for correctness, only for speed.
  public static func pack(
    _ source: [UInt8], bytesPerRow: Int, rowBytes: Int, height: Int
  ) throws -> [UInt8] {
    guard rowBytes > 0, height > 0, bytesPerRow > 0 else {
      throw Failure.invalidGeometry
    }
    guard bytesPerRow >= rowBytes else {
      throw Failure.strideSmallerThanRow(bytesPerRow: bytesPerRow, rowBytes: rowBytes)
    }
    // Only the last row must be complete; the source may legitimately end there.
    let required = bytesPerRow * (height - 1) + rowBytes
    guard source.count >= required else {
      throw Failure.sourceTooShort(expected: required, actual: source.count)
    }

    if bytesPerRow == rowBytes {
      return Array(source[0..<(rowBytes * height)])
    }

    var packed = [UInt8]()
    packed.reserveCapacity(rowBytes * height)
    for row in 0..<height {
      let start = row * bytesPerRow
      packed.append(contentsOf: source[start..<(start + rowBytes)])
    }
    return packed
  }

  /// The same copy, from a raw pointer, for a locked pixel buffer.
  ///
  /// The caller owns the lock: this reads `bytesPerRow * (height - 1) + rowBytes`
  /// bytes and nothing more.
  public static func pack(
    baseAddress: UnsafeRawPointer, bytesPerRow: Int, rowBytes: Int, height: Int
  ) throws -> Data {
    guard rowBytes > 0, height > 0, bytesPerRow > 0 else {
      throw Failure.invalidGeometry
    }
    guard bytesPerRow >= rowBytes else {
      throw Failure.strideSmallerThanRow(bytesPerRow: bytesPerRow, rowBytes: rowBytes)
    }

    if bytesPerRow == rowBytes {
      return Data(bytes: baseAddress, count: rowBytes * height)
    }

    var packed = Data(capacity: rowBytes * height)
    for row in 0..<height {
      packed.append(
        Data(bytes: baseAddress.advanced(by: row * bytesPerRow), count: rowBytes))
    }
    return packed
  }

  /// Bytes per row for a depth map: Float32 metres.
  public static func depthRowBytes(width: Int) -> Int {
    width * MemoryLayout<Float32>.size
  }

  /// Bytes per row for a confidence map: one byte per pixel.
  public static func confidenceRowBytes(width: Int) -> Int {
    width
  }
}
