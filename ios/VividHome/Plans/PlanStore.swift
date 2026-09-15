import Foundation
import UIKit
import VividHomeCore

/// Reading and writing `plans/` beside the sessions, per `docs/session-format.md` §13.
///
/// Project scope, not session scope: a plan belongs to the building, it is
/// imported rather than captured, and it is edited afterwards — so it sits next
/// to the sessions and never inside one (rule 6 keeps raw sessions immutable).
final class PlanStore: ObservableObject {

  enum Failure: LocalizedError {
    case badLevel
    case couldNotRead
    case couldNotRasterize
    case tooLarge

    var errorDescription: String? {
      switch self {
      case .badLevel: return "That level name has no usable slug. Try plain letters."
      case .couldNotRead: return "That file could not be opened."
      case .couldNotRasterize: return "That page could not be turned into an image."
      case .tooLarge: return "That image is too large to store."
      }
    }
  }

  /// The longest edge a stored raster may have, from §13.
  ///
  /// A phone photo of a drawing is 4032 px on its long edge and a plan is mostly
  /// flat colour, so downsampling costs nothing legible and halves what has to
  /// be copied to the PC beside 800 MB of session per room.
  static let maxEdge: CGFloat = 4096

  @Published private(set) var plans: [String: PlanFile] = [:]
  /// Room labels read off each level's drawing, by level.
  ///
  /// Deliberately **not** written to `plans/<level>.json`. A candidate is an
  /// inference and the file is a record of what a human accepted (rule 9), and
  /// keeping them apart means the contract needs no "confirmed" flag that could
  /// drift from the thing it describes. They are cheap to recompute and are
  /// gone when the app restarts, which is correct: an unaccepted suggestion is
  /// not data.
  @Published private(set) var candidates: [String: [PlanLabelReader.Candidate]] = [:]

  private let project: String
  private let fileManager = FileManager.default

  init(project: String) {
    self.project = project
    reload()
  }

  // MARK: - Locations

  private var documents: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  var directory: URL {
    documents
      .appendingPathComponent("sessions", isDirectory: true)
      .appendingPathComponent(project, isDirectory: true)
      .appendingPathComponent("plans", isDirectory: true)
  }

  func imageURL(for plan: PlanFile) -> URL {
    directory.appendingPathComponent(plan.image)
  }

  // MARK: - Reading

  func reload() {
    var found: [String: PlanFile] = [:]
    let decoder = JSONDecoder()
    let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for url in contents where url.pathExtension == "json" {
      guard let data = try? Data(contentsOf: url),
        let plan = try? decoder.decode(PlanFile.self, from: data)
      else { continue }
      // The stem is the identity; a file whose `level` disagrees is rule 1's
      // error and is left for `validate --project` to report rather than
      // silently corrected here.
      found[url.deletingPathExtension().lastPathComponent] = plan
    }
    plans = found
  }

  func image(for plan: PlanFile) -> UIImage? {
    UIImage(contentsOfFile: imageURL(for: plan).path)
  }

  // MARK: - Writing

  /// Import an image as the plan for a level, keeping the original beside it.
  @discardableResult
  func importPlan(image: UIImage, levelName: String, source: PlanSource?, originalData: Data?)
    throws -> PlanFile
  {
    guard let level = SessionID.slug(levelName) else { throw Failure.badLevel }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let scaled = Self.downsampled(image)
    guard let png = scaled.pngData() else { throw Failure.couldNotRasterize }

    let name = "\(level).png"
    try png.write(to: directory.appendingPathComponent(name), options: .atomic)

    var storedSource = source
    if let data = originalData, let source {
      // Keeping the original costs storage and buys the one thing a rasterised
      // copy cannot: re-rendering the page at a higher resolution later, and
      // perspective-correcting from the real pixels rather than from a resample.
      try? data.write(to: directory.appendingPathComponent(source.file), options: .atomic)
      storedSource = source
    } else if originalData == nil {
      storedSource = nil
    }

    // Placements survive a re-import: the plan is the same drawing rescanned,
    // and making the owner re-place every room because they retook the photo
    // would be the app losing their work over its own file handling.
    var plan = plans[level] ?? PlanFile(level: level, image: name)
    plan.image = name
    plan.source = storedSource
    plans[level] = plan
    try save(plan)

    // Read the drawing's own labels. A plan names its rooms — that is what it
    // is for — so retyping them while looking at the sheet is work the sheet
    // already did. Scaled from the stored raster, so the points are in the same
    // pixels a placement uses.
    candidates[level] = PlanLabelReader.candidates(in: scaled)
      .filter { plan.placement(of: $0.slug) == nil }

    return plan
  }

  func place(room: String, at point: CGPoint, on level: String, size: CGSize) throws {
    guard var plan = plans[level] else { return }
    let ok = plan.place(
      room: room, x: Double(point.x), y: Double(point.y),
      in: (width: Int(size.width), height: Int(size.height)))
    guard ok else { return }
    plans[level] = plan
    // An accepted candidate stops being a candidate.
    candidates[level]?.removeAll { $0.slug == room }
    try save(plan)
  }

  func unplace(room: String, on level: String) throws {
    guard var plan = plans[level] else { return }
    plan.unplace(room: room)
    plans[level] = plan
    try save(plan)
  }

  private func save(_ plan: PlanFile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(plan)
    try data.write(to: directory.appendingPathComponent("\(plan.level).json"), options: .atomic)
  }

  // MARK: - Coverage

  /// Captured phases per room on a level, read from the session directories.
  ///
  /// From the directory names rather than by opening every manifest: section 1
  /// puts the level and room in the session id precisely so this is cheap, and
  /// this runs every time the coverage screen appears. The phases a session
  /// carries are in its manifest, so `done` counts *sessions*, not distinct
  /// trades — an honest under-count is better here than an expensive exact one,
  /// and the screen says `2/6` rather than claiming which two.
  func coverage(forLevel level: String, phasesPerRoom: Int = CapturePhase.allCases.count)
    -> [String: (done: Int, total: Int)]
  {
    let sessions = documents
      .appendingPathComponent("sessions", isDirectory: true)
      .appendingPathComponent(project, isDirectory: true)
    let contents = (try? fileManager.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)) ?? []

    var counts: [String: Int] = [:]
    for url in contents where url.hasDirectoryPath {
      let parts = url.lastPathComponent.split(separator: "_")
      guard parts.count == 4, String(parts[1]) == level else { continue }
      counts[String(parts[2]), default: 0] += 1
    }
    return counts.mapValues { (done: $0, total: phasesPerRoom) }
  }

  // MARK: - Helpers

  static func downsampled(_ image: UIImage, maxEdge: CGFloat = PlanStore.maxEdge) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxEdge else { return image }
    let scale = maxEdge / longest
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
