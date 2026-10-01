import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import VividHomeCore

/// Copies a session's photos into the camera roll, labelled (ADR-0028).
///
/// A copy, never a move: the session folder stays the record and stays
/// immutable (rule 6). The JPEG bytes go across unchanged; the label rides in
/// the metadata, and the EXIF orientation tag from the pose is what makes a
/// portrait capture show upright in Photos.
///
/// Add-only access is all this asks for. That is also why there is no album:
/// finding or creating one means reading the library, which the app has no
/// business doing. The capture's own time is set as the creation date, so
/// Photos files a copy on the day the room was walked rather than the day it
/// was saved.
enum PhotoExporter {

  struct Job {
    var url: URL
    var label: PhotoLabel
    var orientation: DisplayOrientation
  }

  enum Failure: LocalizedError {
    case notAllowed
    case unreadable(String)

    var errorDescription: String? {
      switch self {
      case .notAllowed:
        return "VividHome is not allowed to add to your photo library. "
          + "Settings → Privacy & Security → Photos → VividHome → Add Photos Only."
      case .unreadable(let name):
        return "\(name) could not be read as a JPEG."
      }
    }
  }

  /// Save every job. Returns how many were added.
  static func save(_ jobs: [Job]) async throws -> Int {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { throw Failure.notAllowed }

    let items: [(data: Data, takenAt: Date?)] = try jobs.map { job in
      (try labelled(job.url, label: job.label, orientation: job.orientation), job.label.takenAt)
    }
    try await PHPhotoLibrary.shared().performChanges {
      for item in items {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: item.data, options: nil)
        if let takenAt = item.takenAt {
          request.creationDate = takenAt
        }
      }
    }
    return items.count
  }

  /// The JPEG bytes unchanged, with the label and the orientation in the metadata.
  ///
  /// `CGImageDestinationCopyImageSource` copies the compressed data rather than
  /// decoding and re-encoding it, so what leaves the app is what the session
  /// holds. The label goes into the XMP Dublin Core fields Photos reads as the
  /// caption and keywords.
  static func labelled(_ url: URL, label: PhotoLabel, orientation: DisplayOrientation) throws
    -> Data
  {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw Failure.unreadable(url.lastPathComponent)
    }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw Failure.unreadable(url.lastPathComponent) }

    let metadata = CGImageMetadataCreateMutable()
    CGImageMetadataSetValueWithPath(
      metadata, nil, "dc:description" as CFString, label.caption as CFString)
    CGImageMetadataSetValueWithPath(metadata, nil, "dc:title" as CFString, label.headline as CFString)
    CGImageMetadataSetValueWithPath(metadata, nil, "dc:subject" as CFString, label.keywords as CFArray)

    var options: [CFString: Any] = [
      kCGImageDestinationMetadata: metadata,
      kCGImageDestinationMergeMetadata: true,
      kCGImageDestinationOrientation: orientation.exifOrientation,
    ]
    if let takenAt = label.takenAt {
      options[kCGImageDestinationDateTime] = exifDateText(takenAt) as CFString
    }

    var error: Unmanaged<CFError>?
    guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error)
    else {
      throw Failure.unreadable(url.lastPathComponent)
    }
    return output as Data
  }

  /// EXIF's own date form, `yyyy:MM:dd HH:mm:ss`, in the device's local time
  /// like every camera writes it.
  static func exifDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter.string(from: date)
  }
}
