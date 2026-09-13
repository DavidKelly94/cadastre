import Foundation

/// Finding sessions on disk, and repairing the ones that did not stop cleanly.
///
/// The app writes `manifest.json` with `status: incomplete` the moment recording
/// starts, and rewrites it at the stop. Anything left as `incomplete` is a
/// session the app died during — a crash, a force quit, a battery. The files it
/// managed to write are usually fine; it is only the bookkeeping that was lost.
///
/// Repair rebuilds that bookkeeping by counting what is actually there, which is
/// why the pipeline treats `repaired` as a warning rather than an error.
public struct SessionStore: Sendable {
  /// `Documents/sessions`, holding one directory per project.
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public init(documents: URL) {
    self.root = documents.appendingPathComponent("sessions", isDirectory: true)
  }

  private var manager: FileManager { .default }

  /// Project slugs that have at least a directory.
  public func projects() throws -> [String] {
    guard manager.fileExists(atPath: root.path) else { return [] }
    return try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
      .filter(\.hasDirectoryPath)
      .map(\.lastPathComponent)
      .filter { !$0.hasPrefix(".") }
      .sorted()
  }

  /// Sessions in a project, newest first.
  ///
  /// Sorted by name rather than by file date: the id begins with a timestamp, so
  /// the name is the capture order, while a file date is whenever the bytes
  /// happened to land — which a copy off the phone would change.
  public func sessions(inProject project: String) throws -> [SessionLayout] {
    let directory = root.appendingPathComponent(project, isDirectory: true)
    guard manager.fileExists(atPath: directory.path) else { return [] }
    return try manager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isDirectoryKey]
    )
    .filter(\.hasDirectoryPath)
    .filter { !$0.lastPathComponent.hasPrefix(".") }
    .sorted { $0.lastPathComponent > $1.lastPathComponent }
    .map { SessionLayout(root: $0) }
  }

  /// Read a session's manifest, or nil if it has none or it cannot be parsed.
  public func manifest(at layout: SessionLayout) -> Manifest? {
    guard let data = try? Data(contentsOf: layout.manifest) else { return nil }
    return try? JSONDecoder().decode(Manifest.self, from: data)
  }

  /// Count what is actually on disk, ignoring whatever the manifest claims.
  ///
  /// Lines are counted rather than parsed: a session that died mid-write can
  /// leave a truncated final line, and refusing to count the eight hundred good
  /// ones because the last is half-written would be the wrong trade. A line is
  /// counted when it is non-empty and ends in a newline, so a partial tail is
  /// left out rather than counted as whole.
  public func countedStats(at layout: SessionLayout) -> SessionStats {
    var stats = SessionStats()
    stats.keyframes = Self.completeLines(in: layout.frames)
    stats.stills = Self.completeLines(in: layout.stills)
    stats.markerObservations = Self.completeLines(in: layout.markers)
    stats.landmarks = Self.completeLines(in: layout.landmarks)
    stats.bytes = Self.directorySize(layout.root)
    return stats
  }

  /// The last timestamp in `frames.jsonl`, which is how long the session ran.
  public func observedDuration(at layout: SessionLayout) -> Double {
    guard let text = try? String(contentsOf: layout.frames, encoding: .utf8) else { return 0 }
    var last = 0.0
    for line in text.split(separator: "\n") {
      guard let data = line.data(using: .utf8),
        let record = try? JSONDecoder().decode(FrameRecord.self, from: data)
      else { continue }
      last = max(last, record.time)
    }
    return last
  }

  /// Rewrite an `incomplete` manifest from what is on disk.
  ///
  /// Returns the repaired manifest, or nil when there was nothing to repair —
  /// a session that stopped cleanly is left exactly as it is, because rewriting
  /// a good manifest could only lose information.
  @discardableResult
  public func repairIfNeeded(at layout: SessionLayout, endedAt: String? = nil) throws -> Manifest? {
    guard let manifest = manifest(at: layout), manifest.status == .incomplete else {
      return nil
    }
    let repaired = manifest.repaired(
      endedAt: endedAt,
      duration: observedDuration(at: layout),
      stats: countedStats(at: layout))

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
    try encoder.encode(repaired).write(to: layout.manifest, options: .atomic)
    return repaired
  }

  /// Repair every incomplete session, which the app does once at launch.
  @discardableResult
  public func repairAll(endedAt: String? = nil) throws -> [String] {
    var repaired: [String] = []
    for project in try projects() {
      for layout in try sessions(inProject: project) {
        if try repairIfNeeded(at: layout, endedAt: endedAt) != nil {
          repaired.append(layout.root.lastPathComponent)
        }
      }
    }
    return repaired
  }

  /// Delete a session and everything under it.
  public func delete(at layout: SessionLayout) throws {
    try manager.removeItem(at: layout.root)
  }

  // MARK: - Counting

  /// Lines that are complete: non-empty and terminated.
  static func completeLines(in url: URL) -> Int {
    guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
      return 0
    }
    var count = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) where !line.isEmpty {
      count += 1
    }
    // A file not ending in a newline has a partial last line; do not count it.
    if !text.hasSuffix("\n") {
      count = max(0, count - 1)
    }
    return count
  }

  static func directorySize(_ url: URL) -> Int {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
    else { return 0 }

    var total = 0
    for case let item as URL in enumerator {
      let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true {
        total += values?.fileSize ?? 0
      }
    }
    return total
  }
}
