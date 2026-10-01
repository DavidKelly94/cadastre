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
    case unreadable(String, String)
    case losslessRefused(String)

    var errorDescription: String? {
      switch self {
      case .notAllowed:
        return "VividHome is not allowed to add to your photo library. "
          + "Settings → Privacy & Security → Photos → VividHome → Add Photos Only."
      case .unreadable(let name, let reason):
        return "\(name) could not be saved: \(reason)"
      case .losslessRefused(let reason):
        return reason
      }
    }
  }

  /// How a photo's bytes were prepared, so the result can say what happened.
  enum Prepared: Equatable {
    /// The session's bytes unchanged, label and orientation in the metadata.
    case lossless
    /// Decoded and re-encoded, label and orientation in the metadata.
    case reencoded
    /// The session's bytes unchanged and nothing added; the label was lost.
    case plain
  }

  struct Outcome {
    var saved: Int
    var reencoded: Int
    var plain: Int
    /// Why the lossless path refused, the first time it did. For the next build.
    var firstRefusal: String?

    var summary: String {
      var text = saved == 1 ? "Saved to Photos." : "Saved \(saved) photos to Photos."
      if reencoded > 0 {
        text += " \(reencoded) re-encoded to attach the label."
      }
      if plain > 0 {
        text += " \(plain) saved without a label."
      }
      if let firstRefusal {
        text += " Lossless copy refused: \(firstRefusal)"
      }
      return text
    }
  }

  /// Save every job. Says how many were added and how they had to be prepared.
  static func save(_ jobs: [Job]) async throws -> Outcome {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { throw Failure.notAllowed }

    var outcome = Outcome(saved: 0, reencoded: 0, plain: 0, firstRefusal: nil)
    var items: [(data: Data, takenAt: Date?)] = []
    for job in jobs {
      let (data, how, refusal) = try prepare(job)
      items.append((data, job.label.takenAt))
      switch how {
      case .lossless: break
      case .reencoded: outcome.reencoded += 1
      case .plain: outcome.plain += 1
      }
      if outcome.firstRefusal == nil, let refusal {
        outcome.firstRefusal = refusal
      }
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
    outcome.saved = items.count
    return outcome
  }

  /// The bytes to hand to Photos, by the best path that works for this file.
  ///
  /// First the lossless copy with the label merged in. The first walk of this
  /// screen found a keyframe that path refused — the thumbnail of the same file
  /// decoded fine, so it was the copy and not the JPEG — and refusing to save
  /// at all was the wrong answer. Next a decode and re-encode with the same
  /// label, which costs a little quality. Last the bytes exactly as the session
  /// holds them, with nothing added, because a photo without its label is still
  /// the photo the owner asked for. Which path it took is reported, with the
  /// reason the first one gave, so the next build can narrow it.
  static func prepare(_ job: Job) throws -> (Data, Prepared, String?) {
    guard let source = CGImageSourceCreateWithURL(job.url as CFURL, nil) else {
      throw Failure.unreadable(job.url.lastPathComponent, "the file could not be opened")
    }
    var refusal: String?
    do {
      return (try lossless(source, label: job.label, orientation: job.orientation), .lossless, nil)
    } catch {
      refusal = error.localizedDescription
    }
    if let data = reencoded(source, label: job.label, orientation: job.orientation) {
      return (data, .reencoded, refusal)
    }
    guard let raw = try? Data(contentsOf: job.url) else {
      throw Failure.unreadable(job.url.lastPathComponent, refusal ?? "the file could not be read")
    }
    return (raw, .plain, refusal)
  }

  /// The JPEG bytes unchanged, with the orientation, the date and the label in
  /// the metadata.
  ///
  /// `CGImageDestinationCopyImageSource` copies the compressed data rather than
  /// decoding and re-encoding it, so what leaves the app is what the session
  /// holds. Two passes, because the first walk of this screen produced the
  /// exact refusal: *kCGImageDestinationMetadata cannot be used with
  /// kCGImageDestinationOrientation*. The orientation and the date go in on
  /// the first pass, the label is merged in on the second, and each pass is a
  /// combination ImageIO allows. The label goes into the XMP Dublin Core fields
  /// Photos reads as the caption and keywords.
  static func lossless(_ source: CGImageSource, label: PhotoLabel, orientation: DisplayOrientation)
    throws -> Data
  {
    var first: [CFString: Any] = [kCGImageDestinationOrientation: orientation.exifOrientation]
    if let takenAt = label.takenAt {
      first[kCGImageDestinationDateTime] = exifDateText(takenAt) as CFString
    }
    let oriented = try copy(source, options: first, pass: "orientation and date")

    guard let turned = CGImageSourceCreateWithData(oriented as CFData, nil) else {
      throw Failure.losslessRefused("the oriented copy could not be reopened")
    }
    let metadata = CGImageMetadataCreateMutable()
    CGImageMetadataSetValueWithPath(
      metadata, nil, "dc:description" as CFString, label.caption as CFString)
    CGImageMetadataSetValueWithPath(metadata, nil, "dc:title" as CFString, label.headline as CFString)
    CGImageMetadataSetValueWithPath(metadata, nil, "dc:subject" as CFString, label.keywords as CFArray)
    let second: [CFString: Any] = [
      kCGImageDestinationMetadata: metadata,
      kCGImageDestinationMergeMetadata: true,
    ]
    return try copy(turned, options: second, pass: "label")
  }

  /// One lossless pass of `CGImageDestinationCopyImageSource`, with the reason
  /// when ImageIO refuses it.
  private static func copy(_ source: CGImageSource, options: [CFString: Any], pass: String) throws
    -> Data
  {
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw Failure.losslessRefused("no JPEG destination for the \(pass) pass") }

    var error: Unmanaged<CFError>?
    guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error)
    else {
      let reason =
        error.map { ($0.takeRetainedValue() as Error).localizedDescription }
        ?? "CGImageDestinationCopyImageSource returned false"
      throw Failure.losslessRefused("\(pass) pass: \(reason)")
    }
    return output as Data
  }

  /// Decoded and written again, with the label in the classic TIFF, EXIF and
  /// IPTC fields that every reader understands. Costs one generation of JPEG
  /// quality, which is why it is the second choice and not the first.
  static func reencoded(_ source: CGImageSource, label: PhotoLabel, orientation: DisplayOrientation)
    -> Data?
  {
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }

    var exif: [CFString: Any] = [kCGImagePropertyExifUserComment: label.caption]
    if let takenAt = label.takenAt {
      exif[kCGImagePropertyExifDateTimeOriginal] = exifDateText(takenAt)
      exif[kCGImagePropertyExifDateTimeDigitized] = exifDateText(takenAt)
    }
    let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: 0.92,
      kCGImagePropertyOrientation: orientation.exifOrientation,
      kCGImagePropertyTIFFDictionary: [
        kCGImagePropertyTIFFImageDescription: label.caption,
        kCGImagePropertyTIFFOrientation: orientation.exifOrientation,
      ],
      kCGImagePropertyExifDictionary: exif,
      kCGImagePropertyIPTCDictionary: [
        kCGImagePropertyIPTCCaptionAbstract: label.caption,
        kCGImagePropertyIPTCObjectName: label.headline,
        kCGImagePropertyIPTCKeywords: label.keywords,
      ],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
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
