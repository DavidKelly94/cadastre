import Foundation

/// The projects on this phone (ADR-0033): each a folder under `sessions/`,
/// holding its captures and its `plans/`, with its name in `project.json`.
///
/// The slug is the folder's name and never changes, because it is in every
/// capture's manifest and in the PC's store. The name is what the owner
/// reads, and can be changed. A folder with no `project.json` is a project
/// from before there was one, and reads under its slug.
public enum ProjectCatalog {
  public static let fileName = "project.json"

  /// What `project.json` holds (section 13). Both fields optional to a
  /// reader: a file that says less still names a project.
  public struct Info: Codable, Equatable, Sendable {
    public var name: String
    public var createdAt: String?

    public init(name: String, createdAt: String? = nil) {
      self.name = name
      self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
      case name
      case createdAt = "created_at"
    }
  }

  public struct Entry: Equatable, Sendable, Identifiable {
    public var slug: String
    public var name: String
    /// The ids of its captures, newest first.
    public var captures: [String]
    /// How many levels have a plan.
    public var plans: Int

    public var id: String { slug }
    public var ref: SlugRef { SlugRef(slug: slug, name: name) }
  }

  public enum Failure: Error, Equatable {
    /// The name has no letters or digits to make a slug from.
    case unusableName
    /// A project with that slug is already here.
    case exists(String)
    case missing(String)
  }

  /// Every project under `root` (the `sessions` folder), by name.
  public static func list(in root: URL) -> [Entry] {
    let manager = FileManager.default
    guard
      let children = try? manager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey])
    else { return [] }
    var out: [Entry] = []
    for child in children {
      let slug = child.lastPathComponent
      guard isDirectory(child), SessionID.slug(slug) == slug else { continue }
      out.append(entry(slug: slug, at: child))
    }
    return out.sorted {
      $0.name.lowercased() == $1.name.lowercased() ? $0.slug < $1.slug : $0.name.lowercased() < $1.name.lowercased()
    }
  }

  /// One project, or nil when it is not there.
  public static func project(_ slug: String, in root: URL) -> Entry? {
    let folder = root.appendingPathComponent(slug, isDirectory: true)
    guard SessionID.slug(slug) == slug, isDirectory(folder) else { return nil }
    return entry(slug: slug, at: folder)
  }

  /// Make a project from a name. The folder is made now, so the project
  /// exists before it has a plan or a capture.
  @discardableResult
  public static func create(name: String, in root: URL, at date: Date = Date()) throws -> Entry {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let slug = SessionID.slug(trimmed) else { throw Failure.unusableName }
    let folder = root.appendingPathComponent(slug, isDirectory: true)
    guard !FileManager.default.fileExists(atPath: folder.path) else { throw Failure.exists(slug) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try write(Info(name: trimmed, createdAt: PlanRoom.iso8601(date)), to: folder)
    return entry(slug: slug, at: folder)
  }

  /// Change what a project is called. Its slug, and so its folder, every
  /// capture in it and the PC's copy, stay as they are.
  public static func rename(_ slug: String, to name: String, in root: URL) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw Failure.unusableName }
    let folder = root.appendingPathComponent(slug, isDirectory: true)
    guard isDirectory(folder) else { throw Failure.missing(slug) }
    var info = read(from: folder) ?? Info(name: trimmed)
    info.name = trimmed
    try write(info, to: folder)
  }

  /// Remove a project from this phone: every capture in it and its plans.
  /// Nothing on the PC is touched.
  public static func delete(_ slug: String, in root: URL) throws {
    let folder = root.appendingPathComponent(slug, isDirectory: true)
    guard SessionID.slug(slug) == slug, isDirectory(folder) else { throw Failure.missing(slug) }
    try FileManager.default.removeItem(at: folder)
  }

  /// Of a project's captures, the ones the PC has not said it holds and has
  /// validated: what deleting the project here would lose for good.
  public static func unconfirmed(_ entry: Entry, validatedOnPC: Set<String>) -> [String] {
    entry.captures.filter { !validatedOnPC.contains($0) }
  }

  // MARK: - Files

  private static func entry(slug: String, at folder: URL) -> Entry {
    let manager = FileManager.default
    let children = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    let captures = children
      .filter { manager.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
      .map(\.lastPathComponent)
      .sorted(by: >)
    let plansFolder = folder.appendingPathComponent("plans", isDirectory: true)
    let plans = ((try? manager.contentsOfDirectory(at: plansFolder, includingPropertiesForKeys: nil)) ?? [])
      .filter { $0.pathExtension == "json" }.count
    let name = read(from: folder)?.name ?? SessionID.displayName(slug: slug)
    return Entry(slug: slug, name: name, captures: captures, plans: plans)
  }

  private static func read(from folder: URL) -> Info? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
    return try? JSONDecoder().decode(Info.self, from: data)
  }

  private static func write(_ info: Info, to folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(info).write(to: folder.appendingPathComponent(fileName), options: .atomic)
  }

  private static func isDirectory(_ url: URL) -> Bool {
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
  }
}
