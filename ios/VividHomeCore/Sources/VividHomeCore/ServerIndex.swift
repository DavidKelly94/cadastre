import Foundation

/// What the PC says it holds: `GET /index.json`, `docs/session-format.md` §14.
///
/// The app never lists the PC's directories or guesses file names; it reads
/// this and follows the paths in it. Every path is relative to the server root,
/// which is the store. Unknown fields decode away, as §12 asks of a reader.
public struct ServerIndex: Codable, Equatable, Sendable {
  public var vividhome: String
  /// When the PC answered, UTC, ISO 8601. The index is generated on request,
  /// so this is the age of what the app holds once it has been fetched.
  public var generatedAt: String
  public var store: String
  public var projects: [Project]

  public struct Project: Codable, Equatable, Sendable {
    public var slug: String
    public var levels: [Level]
    public var sessions: [Session]

    public init(slug: String, levels: [Level], sessions: [Session]) {
      self.slug = slug
      self.levels = levels
      self.sessions = sessions
    }
  }

  public struct Level: Codable, Equatable, Sendable {
    public var level: String
    public var plan: String
    public var calibrated: Bool
    /// `inspect/<level>.html` once `vividhome inspect` has written it, else nil.
    public var inspect: String?
    /// Session ids aligned onto this level.
    public var sessions: [String]

    public init(level: String, plan: String, calibrated: Bool, inspect: String?, sessions: [String]) {
      self.level = level
      self.plan = plan
      self.calibrated = calibrated
      self.inspect = inspect
      self.sessions = sessions
    }
  }

  public struct Session: Codable, Equatable, Sendable {
    public var sessionID: String
    public var path: String
    public var level: String?
    public var aligned: Bool
    /// True or false from the PC's validate report; nil when none was written.
    public var validated: Bool?

    public init(sessionID: String, path: String, level: String?, aligned: Bool, validated: Bool?) {
      self.sessionID = sessionID
      self.path = path
      self.level = level
      self.aligned = aligned
      self.validated = validated
    }

    enum CodingKeys: String, CodingKey {
      case sessionID = "session_id"
      case path
      case level
      case aligned
      case validated
    }
  }

  public init(vividhome: String, generatedAt: String, store: String, projects: [Project]) {
    self.vividhome = vividhome
    self.generatedAt = generatedAt
    self.store = store
    self.projects = projects
  }

  enum CodingKeys: String, CodingKey {
    case vividhome
    case generatedAt = "generated_at"
    case store
    case projects
  }

  public func project(_ slug: String) -> Project? {
    projects.first { $0.slug == slug }
  }

  /// The rendered page for a level of a project, relative to the server root.
  public func inspectPage(project: String, level: String) -> String? {
    self.project(project)?.levels.first { $0.level == level }?.inspect
  }

  public var generated: Date? { ISO8601Text.date(from: generatedAt) }

  /// How old the index is, or nil when its timestamp does not parse.
  public func age(now: Date) -> TimeInterval? {
    generated.map { now.timeIntervalSince($0) }
  }

  public var sessionCount: Int { projects.reduce(0) { $0 + $1.sessions.count } }
  public var renderedLevelCount: Int {
    projects.reduce(0) { $0 + $1.levels.filter { $0.inspect != nil }.count }
  }
}

/// Where the PC is, from whatever the owner typed or Bonjour found.
public enum PCAddress {
  /// The port `vividhome serve` listens on unless told otherwise.
  public static let defaultPort = 8765

  /// A base URL from a typed address: `192.168.1.20`, `192.168.1.20:9000`,
  /// `pc.local`, `http://pc.local:8765/`. Only the scheme, host and port
  /// survive; a pasted page path is dropped. Nil when there is no host.
  public static func url(from text: String, defaultPort: Int = defaultPort) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if !trimmed.contains("://") {
      trimmed = "http://" + trimmed
    }
    guard let components = URLComponents(string: trimmed),
      let host = components.host, !host.isEmpty
    else { return nil }
    let scheme = components.scheme?.lowercased() ?? "http"
    guard scheme == "http" || scheme == "https" else { return nil }
    let port = components.port ?? defaultPort
    return URL(string: "\(scheme)://\(host):\(port)")
  }
}
