import ImageIO
import UIKit
import VividHomeCore

/// Decoding a session's JPEGs for display, turned the way the phone was held.
///
/// The files are landscape sensor orientation and are never rotated on disk
/// (`docs/session-format.md` §3). The turn comes from the pose through
/// `DisplayOrientation` in the core package, and is applied here as the
/// `UIImage` orientation, which costs nothing: the pixels stay as decoded.
enum PhotoLoader {

  /// A downsampled image for a grid cell.
  static func thumbnail(at url: URL, maxPixel: Int, orientation: DisplayOrientation) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
      kCGImageSourceCreateThumbnailWithTransform: false,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image, scale: 1, orientation: orientation.uiImageOrientation)
  }

  /// The full image.
  static func full(at url: URL, orientation: DisplayOrientation) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image, scale: 1, orientation: orientation.uiImageOrientation)
  }
}

extension DisplayOrientation {
  /// `UIImage.Orientation` names the turn the pixels have undergone; the EXIF
  /// value names the turn to apply. `.right` is "rotated 90° clockwise from the
  /// pixel data", which is what EXIF 6 asks a viewer to do.
  var uiImageOrientation: UIImage.Orientation {
    switch self {
    case .upright: return .up
    case .rotate180: return .down
    case .rotate90Clockwise: return .right
    case .rotate90Counterclockwise: return .left
    }
  }
}
