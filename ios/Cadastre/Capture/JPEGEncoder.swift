import CoreImage
import CoreVideo
import Foundation
import Metal

/// Encoding ARKit's captured image to JPEG.
///
/// One `CIContext` for the life of the app: building one per frame is the
/// expensive mistake here, since it recompiles its pipeline each time.
///
/// The image is written exactly as ARKit delivers it — landscape, unrotated —
/// because `docs/session-format.md` §3 makes the stored orientation part of the
/// contract and `K` describes that image. Rotating for display is the viewer's
/// job.
final class JPEGEncoder {
  enum Failure: Error {
    case encodingFailed
  }

  private let context: CIContext
  private let colorSpace: CGColorSpace

  init() {
    // A Metal-backed context where possible; the software path keeps the
    // simulator, and anything without a GPU device, working.
    if let device = MTLCreateSystemDefaultDevice() {
      context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
    } else {
      context = CIContext(options: [.cacheIntermediates: false])
    }
    colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
  }

  func encode(_ buffer: CVPixelBuffer, quality: Double) throws -> Data {
    let image = CIImage(cvPixelBuffer: buffer)
    guard
      let data = context.jpegRepresentation(
        of: image,
        colorSpace: colorSpace,
        options: [kCGImageDestinationLossyCompressionQuality as CIImageOption: quality])
    else {
      throw Failure.encodingFailed
    }
    return data
  }
}
