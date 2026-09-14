import CoreVideo
import Foundation

import VividHomeCore

/// Reading a `CVPixelBuffer` into the tightly packed bytes the format stores.
///
/// This is the only place in the app that touches pixel-buffer padding, and it
/// does none of the arithmetic itself: `RowPacker` in VividHomeCore owns that, so
/// the rule is covered by tests that run on Linux. What is left here is the part
/// that genuinely needs CoreVideo — locking the buffer and reading its stride.
enum PixelBufferPacker {
  enum Failure: Error {
    case lockFailed(CVReturn)
    case noBaseAddress
  }

  /// Copy the whole buffer out, discarding row padding.
  ///
  /// `bytesPerPixel` is the caller's, not the buffer's: ARKit's depth map is
  /// `kCVPixelFormatType_DepthFloat32` and its confidence map is 8-bit, and the
  /// format stores each at exactly that width.
  static func packed(_ buffer: CVPixelBuffer, bytesPerPixel: Int) throws -> Data {
    let status = CVPixelBufferLockBaseAddress(buffer, .readOnly)
    guard status == kCVReturnSuccess else {
      throw Failure.lockFailed(status)
    }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw Failure.noBaseAddress
    }
    return try RowPacker.pack(
      baseAddress: base,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      rowBytes: CVPixelBufferGetWidth(buffer) * bytesPerPixel,
      height: CVPixelBufferGetHeight(buffer))
  }

  /// The depth map: Float32 metres, one value per pixel.
  static func depth(_ buffer: CVPixelBuffer) throws -> Data {
    try packed(buffer, bytesPerPixel: MemoryLayout<Float32>.size)
  }

  /// The confidence map: one byte per pixel, 0 low, 1 medium, 2 high.
  static func confidence(_ buffer: CVPixelBuffer) throws -> Data {
    try packed(buffer, bytesPerPixel: 1)
  }
}
