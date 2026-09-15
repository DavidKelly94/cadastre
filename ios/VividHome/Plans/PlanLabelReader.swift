import UIKit
import Vision
import VividHomeCore

/// Reads room names off a floor plan.
///
/// Plans label their rooms — that is what a plan is for — so asking the owner to
/// retype "KITCHEN" while looking at a drawing that says KITCHEN is asking them
/// to do work the sheet already did.
///
/// This is `Vision`, on device, no model download and no network. It is not a
/// language model and does not interpret the drawing: it finds text and where
/// that text sits. Everything it returns is a **candidate** (rule 9 of
/// `AGENTS.md`): nothing reaches `plans/<level>.json` until the owner accepts
/// it, and accepting is a drag into place, so confirming and correcting are the
/// same gesture.
enum PlanLabelReader {

  struct Candidate: Identifiable, Equatable {
    let id = UUID()
    /// The text as printed, for showing.
    var text: String
    /// The slug it would become, which is what a session would use.
    var slug: String
    /// Centre of the text, in pixels of the raster, origin top-left.
    var point: CGPoint
    /// Vision's own confidence in the recognition, 0 to 1.
    var confidence: Float
  }

  /// Words that appear on plans and are never a room.
  ///
  /// Kept deliberately short. A stop list that tries to be clever throws away
  /// real rooms — "STORE" and "OFFICE" are rooms in a house — so this only
  /// covers title-block and dimension furniture that is unambiguous.
  private static let notRooms: Set<String> = [
    "scale", "plan", "floor", "north", "date", "drawn", "sheet", "rev", "revision",
    "project", "client", "architect", "drawing", "title", "notes", "level", "general",
    "typ", "typical", "min", "max", "approx", "existing", "new", "do", "not",
  ]

  /// Find plausible room labels in a plan raster.
  ///
  /// Synchronous on purpose: it runs once, on an image the owner just chose,
  /// behind a progress indicator. A few hundred milliseconds on a plan-sized
  /// raster is not worth an async surface.
  static func candidates(in image: UIImage) -> [Candidate] {
    guard let cgImage = image.cgImage else { return [] }

    let request = VNRecognizeTextRequest()
    // `accurate` over `fast`: plan labels are small, often rotated, and this
    // runs once rather than per frame.
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false  // room names are not prose
    request.recognitionLanguages = ["en-US"]

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }

    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    var found: [Candidate] = []
    var seen: Set<String> = []

    for observation in request.results ?? [] {
      guard let top = observation.topCandidates(1).first else { continue }
      guard let slug = plausibleRoom(top.string) else { continue }
      // Two labels slugging the same way is one room read twice, or a legend
      // repeating it. Keep the first, which reading order puts nearer the top.
      guard seen.insert(slug).inserted else { continue }

      // Vision's boxes are normalised with the origin at the BOTTOM left; plan
      // pixels have it at the top left, so y inverts. Getting this wrong puts
      // every room in the mirror image of the right place, which looks
      // plausible on a symmetric plan and is not.
      let box = observation.boundingBox
      found.append(
        Candidate(
          text: top.string.trimmingCharacters(in: .whitespacesAndNewlines),
          slug: slug,
          point: CGPoint(
            x: box.midX * width,
            y: (1 - box.midY) * height),
          confidence: top.confidence))
    }
    return found.sorted { $0.confidence > $1.confidence }
  }

  /// The slug a piece of recognised text would become, or nil if it is not
  /// plausibly a room name.
  static func plausibleRoom(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 24 else { return nil }

    // A label that is mostly digits is a dimension or a sheet number.
    let letters = trimmed.filter { $0.isLetter }.count
    guard letters >= 3, letters * 2 >= trimmed.count else { return nil }

    // Dimension strings survive the letter test via their units.
    if trimmed.contains("'") || trimmed.contains("\"") { return nil }

    let words = trimmed.lowercased().split { !$0.isLetter }
    guard let first = words.first, !notRooms.contains(String(first)) else { return nil }

    return SessionID.slug(trimmed)
  }
}
