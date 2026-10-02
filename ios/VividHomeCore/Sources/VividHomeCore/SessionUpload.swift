import Foundation

/// The app's half of sending a capture to the PC: `docs/session-format.md` §14.1
/// (ADR-0029).
///
/// What to send is decided here, from the files on disk and the PC's listing of
/// what its inbox already holds, so it is tested on Linux. Moving the bytes is
/// `URLSession` in the app. The rules for a path mirror the server's, so a file
/// the server would refuse is never offered.
public enum SessionUpload {
  /// One file to send: its session-relative path as the `PUT` names it, where
  /// it is on the phone, and its size.
  public struct File: Equatable, Sendable {
    public var path: String
    public var url: URL
    public var bytes: Int

    public init(path: String, url: URL, bytes: Int) {
      self.path = path
      self.url = url
      self.bytes = bytes
    }
  }

  /// Every file of a session the server accepts: what is under the session
  /// folder except `derived/` (the pipeline's, never the app's) and dotted
  /// names, plus the project's plan files as `plans/<file>` when a plans folder
  /// is given, because the plan travels with the capture (ADR-0025, §13).
  /// Sorted by path, so a resumed send walks the same order.
  public static func files(
    of layout: SessionLayout, plans: URL? = nil, manager: FileManager = .default
  ) throws -> [File] {
    var out: [File] = []
    let root = layout.root.standardizedFileURL
    let rootPath = root.path.hasSuffix("/") ? String(root.path.dropLast()) : root.path
    if let enumerator = manager.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
    {
      for case let url as URL in enumerator {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { continue }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { continue }
        let relative = String(path.dropFirst(rootPath.count + 1))
        guard isSendable(relative) else { continue }
        out.append(File(path: relative, url: url, bytes: values?.fileSize ?? 0))
      }
    }
    if let plans, manager.fileExists(atPath: plans.path) {
      let urls = try manager.contentsOfDirectory(
        at: plans, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
      for url in urls {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let path = "plans/\(url.lastPathComponent)"
        guard values?.isRegularFile == true, isSendable(path) else { continue }
        out.append(File(path: path, url: url, bytes: values?.fileSize ?? 0))
      }
    }
    return out.sorted { $0.path < $1.path }
  }

  /// The server's rule for a path, mirrored (§14.1): one or two segments of
  /// plain characters, none starting with a dot, and never `derived/`.
  public static func isSendable(_ path: String) -> Bool {
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard (1...2).contains(segments.count), segments[0] != "derived" else { return false }
    return segments.allSatisfy(isSegment)
  }

  private static func isSegment(_ segment: Substring) -> Bool {
    guard let first = segment.first, first != "." else { return false }
    return segment.allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "_" || character == "-"
          || character == ".")
    }
  }

  /// What is still to send, given the PC's listing: a file whose size the inbox
  /// already reports is skipped, which is what makes a dropped send resume.
  public static func remaining(_ files: [File], given listing: Listing) -> [File] {
    files.filter { listing.files[$0.path] != $0.bytes }
  }

  public static func totalBytes(_ files: [File]) -> Int {
    files.reduce(0) { $0 + $1.bytes }
  }

  /// `GET /upload/<session-id>`: what the inbox holds for a session so far.
  public struct Listing: Codable, Equatable, Sendable {
    public var sessionID: String
    /// `none`, `partial` or `ingested`; kept as text so a newer server's word
    /// decodes rather than fails (§12).
    public var state: String
    public var files: [String: Int]

    public static let ingested = "ingested"

    public init(sessionID: String, state: String, files: [String: Int]) {
      self.sessionID = sessionID
      self.state = state
      self.files = files
    }

    public var isIngested: Bool { state == Self.ingested }

    enum CodingKeys: String, CodingKey {
      case sessionID = "session_id"
      case state
      case files
    }
  }

  /// `POST /upload/<session-id>/done`: what became of the capture.
  public struct Receipt: Codable, Equatable, Sendable {
    public var sessionID: String
    public var ingested: Bool
    public var validated: Bool
    public var destination: String
    public var errors: [String]
    public var warnings: Int
    public var plans: [PlanOutcome]

    public struct PlanOutcome: Codable, Equatable, Sendable {
      public var level: String
      public var imported: Bool
      public var reason: String

      public init(level: String, imported: Bool, reason: String) {
        self.level = level
        self.imported = imported
        self.reason = reason
      }
    }

    public init(
      sessionID: String, ingested: Bool, validated: Bool, destination: String,
      errors: [String], warnings: Int, plans: [PlanOutcome]
    ) {
      self.sessionID = sessionID
      self.ingested = ingested
      self.validated = validated
      self.destination = destination
      self.errors = errors
      self.warnings = warnings
      self.plans = plans
    }

    enum CodingKeys: String, CodingKey {
      case sessionID = "session_id"
      case ingested
      case validated
      case destination
      case errors
      case warnings
      case plans
    }

    /// One line for the owner, under the capture's name.
    public var summary: String {
      if validated {
        let imported = plans.filter(\.imported).map(\.level)
        if imported.isEmpty { return "On the PC and validated." }
        return "On the PC and validated; plan for \(imported.joined(separator: ", ")) imported."
      }
      let count = "\(errors.count) error\(errors.count == 1 ? "" : "s")"
      let first = errors.first.map { " " + $0 } ?? ""
      return "On the PC, but validation failed (\(count)).\(first)"
    }
  }

  /// `{"error": "..."}`, the body of every refusal under `/upload/`.
  public struct Refusal: Codable, Equatable, Sendable {
    public var error: String

    public init(error: String) {
      self.error = error
    }
  }
}
