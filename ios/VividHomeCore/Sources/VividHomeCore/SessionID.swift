import Foundation

/// One construction phase. A session carries a set of these in its manifest,
/// because a single pass can expose several trades at once (ADR-0022).
///
/// The raw values are the vocabulary in `docs/session-format.md` §1; they appear
/// both in the session id and in `manifest.json`.
public enum CapturePhase: String, Codable, CaseIterable, Sendable {
  case framing
  case electrical
  case plumbing
  case hvac
  case insulation
  case drywall
  case finish
  case other
}

/// A session identifier: `<YYYYMMDD-HHMMSS>_<level>_<room>_<id6>`.
///
/// The format is specified in `docs/session-format.md` §1 and is also the
/// directory name on the phone, so it has to round-trip exactly. Parsing is
/// unambiguous because slugs cannot contain an underscore.
public struct SessionID: Equatable, Sendable {
  /// Characters allowed in `id6`: base-32 as `a-z` plus `2-7`.
  public static let id6Alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

  /// Length of the random suffix.
  public static let id6Length = 6

  /// Maximum length of a level or room slug.
  public static let maxSlugLength = 24

  /// Local time at session start, formatted `yyyyMMdd-HHmmss`.
  public let timestamp: String
  public let level: String
  public let room: String
  public let id6: String

  /// The identifier as it appears on disk.
  ///
  /// No phase. A pass can expose several trades at once, and a phase can be
  /// corrected after the capture — neither works in a string that is also a
  /// directory name. Phases live in `manifest.json` (ADR-0022).
  public var stringValue: String {
    "\(timestamp)_\(level)_\(room)_\(id6)"
  }

  /// Creates an identifier from already-valid parts, or nil if any part is not
  /// in the shape the format requires.
  public init?(timestamp: String, level: String, room: String, id6: String) {
    guard Self.isValidTimestamp(timestamp),
      Self.isValidSlug(level),
      Self.isValidSlug(room),
      Self.isValidID6(id6)
    else { return nil }
    self.timestamp = timestamp
    self.level = level
    self.room = room
    self.id6 = id6
  }

  /// Creates an identifier for a session starting at `date`, slugifying the
  /// level and room names the owner typed.
  ///
  /// Returns nil when a name slugifies to nothing, which the caller should treat
  /// as "ask for a different name" rather than inventing one.
  public init?(
    date: Date,
    timeZone: TimeZone = .current,
    levelName: String,
    roomName: String,
    id6: String
  ) {
    guard let level = Self.slug(levelName), let room = Self.slug(roomName) else { return nil }
    self.init(
      timestamp: Self.timestamp(for: date, timeZone: timeZone),
      level: level,
      room: room,
      id6: id6)
  }

  /// Parses an identifier, returning nil if it does not match the format.
  public init?(_ raw: String) {
    let parts = raw.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 4 else { return nil }
    self.init(timestamp: parts[0], level: parts[1], room: parts[2], id6: parts[3])
  }

  // MARK: - Building blocks

  /// Formats `date` as the timestamp component.
  ///
  /// The POSIX locale and an explicit Gregorian calendar keep the output stable
  /// whatever the phone's region settings are.
  public static func timestamp(for date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }

  /// Converts a typed name to a slug: lowercase `a-z0-9-`, at most 24 characters.
  ///
  /// Runs of anything else collapse to a single hyphen, and hyphens are trimmed
  /// from both ends, including after truncation. Returns nil when nothing is
  /// left, so `"!!!"` fails rather than producing an empty path component.
  public static func slug(_ raw: String, maxLength: Int = maxSlugLength) -> String? {
    var out = ""
    var pendingSeparator = false
    for character in raw.lowercased() {
      if character.isASCII, character.isLetter || character.isNumber {
        if pendingSeparator, !out.isEmpty {
          out.append("-")
        }
        pendingSeparator = false
        out.append(character)
      } else {
        pendingSeparator = true
      }
    }
    // Truncate after normalising rather than while building: appending a
    // separator and then a character can cross the limit in one step.
    if out.count > maxLength {
      out = String(out.prefix(maxLength))
    }
    while out.hasSuffix("-") {
      out.removeLast()
    }
    return out.isEmpty ? nil : out
  }

  /// Generates a random `id6` from the base-32 alphabet.
  public static func makeID6<G: RandomNumberGenerator>(using generator: inout G) -> String {
    String((0..<id6Length).map { _ in id6Alphabet.randomElement(using: &generator)! })
  }

  /// Generates a random `id6` using the system random source.
  public static func makeID6() -> String {
    var generator = SystemRandomNumberGenerator()
    return makeID6(using: &generator)
  }

  // MARK: - Validation

  public static func isValidSlug(_ value: String) -> Bool {
    guard (1...maxSlugLength).contains(value.count) else { return false }
    return value.allSatisfy { character in
      character == "-" || (character.isASCII && (character.isLowercase || character.isNumber))
    }
  }

  public static func isValidID6(_ value: String) -> Bool {
    value.count == id6Length && value.allSatisfy(id6Alphabet.contains)
  }

  /// Checks the `yyyyMMdd-HHmmss` shape: eight digits, a hyphen, six digits.
  public static func isValidTimestamp(_ value: String) -> Bool {
    let characters = Array(value)
    guard characters.count == 15, characters[8] == "-" else { return false }
    for (index, character) in characters.enumerated() where index != 8 {
      guard character.isASCII, character.isNumber else { return false }
    }
    return true
  }
}
