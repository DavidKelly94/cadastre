import Foundation

/// What has been captured in a project, assembled from the manifests on disk.
///
/// This is the thing the Project screen shows, and it is pure so that Linux CI
/// covers it (rule 3 of `AGENTS.md`): it takes manifests and returns a
/// structure, touching no file system.
///
/// It reads manifests rather than parsing session directory names. The name
/// carries the level and room but not the phases, and a single pass can expose
/// several trades at once (ADR-0022), so a name-based count cannot see what a
/// session actually recorded.
public struct ProjectDigest: Equatable, Sendable {
  public var project: String
  public var name: String
  public var levels: [LevelDigest]

  /// Rooms that have at least one capture. There is no denominator here on
  /// purpose — see `RoomDigest.phases`.
  public var capturedRooms: Int { levels.reduce(0) { $0 + $1.rooms.count } }
  public var sessions: Int { levels.reduce(0) { $0 + $1.rooms.reduce(0) { $0 + $1.sessions } } }

  public init(project: String, name: String, levels: [LevelDigest]) {
    self.project = project
    self.name = name
    self.levels = levels
  }

  /// Build the digest from every manifest in one project.
  ///
  /// Manifests naming a different project are ignored rather than merged, so a
  /// caller handing over the wrong directory gets an empty digest instead of a
  /// plausible wrong one.
  public static func make(project: String, from manifests: [Manifest]) -> ProjectDigest {
    let mine = manifests.filter { $0.project.slug == project }
    let name = mine.first?.project.name ?? project

    // Written as plain statements rather than a map-then-sort chain: the chained
    // version, with a ternary inside the sort closure, made the type checker
    // give up ("unable to type-check this expression in reasonable time"). It
    // is also easier to read.
    var byLevel: [String: Accumulator] = [:]
    for manifest in mine {
      let levelSlug = manifest.level.slug
      var entry = byLevel[levelSlug] ?? Accumulator(ref: manifest.level)
      let roomSlug = manifest.room.slug
      var room = entry.rooms[roomSlug] ?? RoomDigest(room: roomSlug, name: manifest.room.name)
      room.phases.formUnion(manifest.phases)
      room.sessions += 1
      // Latest wins, compared as ISO 8601 strings: they are fixed-width, so
      // lexical order is chronological order and no date parsing is needed.
      let startedAt: String = manifest.capture.startedAt
      if let known = room.lastCaptured {
        room.lastCaptured = known > startedAt ? known : startedAt
      } else {
        room.lastCaptured = startedAt
      }
      entry.rooms[roomSlug] = room
      byLevel[levelSlug] = entry
    }

    var levels: [LevelDigest] = []
    for entry in byLevel.values {
      var rooms: [RoomDigest] = Array(entry.rooms.values)
      rooms.sort { (a: RoomDigest, b: RoomDigest) -> Bool in a.name < b.name }
      levels.append(
        LevelDigest(
          level: entry.ref.slug, name: entry.ref.name, index: entry.ref.index, rooms: rooms))
    }
    // Storey order, then name, so a basement reads under the floor above it
    // rather than alphabetically above it.
    //
    // Plain `<` rather than localizedStandardCompare, which is not used
    // anywhere else in this package and so is unproven on Linux. These tests
    // run on Linux and the app runs on Darwin, so a comparison that can differ
    // between them would assert one order in CI and show another on the phone —
    // the same shape as every cross-half bug this week. The cost is that
    // "Bedroom 10" sorts before "Bedroom 2"; the ordering is at least identical
    // everywhere, and a natural sort can be added later with a comparison this
    // package owns and tests.
    levels.sort { (a: LevelDigest, b: LevelDigest) -> Bool in
      if a.index != b.index { return a.index > b.index }
      return a.name < b.name
    }

    return ProjectDigest(project: project, name: name, levels: levels)
  }
}

/// Scratch space while grouping manifests. A named type rather than a tuple in
/// a dictionary, which is what the type checker was choking on.
private struct Accumulator {
  var ref: LevelRef
  var rooms: [String: RoomDigest] = [:]
}

public struct LevelDigest: Equatable, Sendable {
  public var level: String
  public var name: String
  public var index: Int
  public var rooms: [RoomDigest]

  public init(level: String, name: String, index: Int, rooms: [RoomDigest]) {
    self.level = level
    self.name = name
    self.index = index
    self.rooms = rooms
  }
}

public struct RoomDigest: Equatable, Sendable {
  public var room: String
  public var name: String

  /// The distinct trades this room has been walked for.
  ///
  /// A set, not a count of sessions: walking the kitchen twice during framing
  /// is one trade recorded, not two, and one pass can expose several trades at
  /// once. This is deliberately not expressed as a fraction of all phases —
  /// `CapturePhase` has eight cases including `other`, and no room needs all of
  /// them. A garage has no plumbing; a closet has no HVAC. A denominator that
  /// counts trades the room will never have reports a job as permanently
  /// half-finished, so what is shown is what was captured.
  public var phases: Set<CapturePhase> = []
  public var sessions: Int = 0
  public var lastCaptured: String?

  public init(
    room: String, name: String, phases: Set<CapturePhase> = [], sessions: Int = 0,
    lastCaptured: String? = nil
  ) {
    self.room = room
    self.name = name
    self.phases = phases
    self.sessions = sessions
    self.lastCaptured = lastCaptured
  }

  /// The trades in the order `CapturePhase` declares them, which is the order
  /// the work happens in, so a room reads as a timeline rather than a set.
  public var orderedPhases: [CapturePhase] {
    CapturePhase.allCases.filter { phases.contains($0) }
  }
}
