import Foundation

/// The earlier captures of a room, read together with the one being made
/// (ADR-0031, design §6): a top-up closes the gaps of the capture before it,
/// so the walls' coverage, the walk on the inset and the stills checklist all
/// start from what the room already has.
///
/// Every complete capture of the same room on the same level that shares a
/// trade with the new one counts. A capture with a placement beside the plans
/// contributes its keyframes, moved into the house frame by that placement;
/// one without contributes only its stills, since its keyframes cannot be put
/// against the outline. Raw sessions are read, never changed.
public struct RoomHistory: Sendable {
  public struct Entry: Sendable {
    public var sessionID: String
    /// Keyframe footprints in the house frame; empty when the capture has no
    /// placement.
    public var cameras: [WallCoverage.Camera]
    /// Where each keyframe was, in house metres; empty when unplaced.
    public var walk: [(x: Double, z: Double)]
    /// The `item` of every still that had one.
    public var stillItems: [String]
  }

  public var entries: [Entry]

  public init(entries: [Entry] = []) {
    self.entries = entries
  }

  public var sessionIDs: [String] { entries.map(\.sessionID) }
  public var cameras: [WallCoverage.Camera] { entries.flatMap(\.cameras) }
  public var walks: [[(x: Double, z: Double)]] { entries.filter { !$0.walk.isEmpty }.map(\.walk) }
  public var stillItems: [String] { entries.flatMap(\.stillItems) }

  /// The earlier captures of `room` on `level` in `project` that share a trade
  /// with `phases`, oldest first. `excluding` leaves one id out, for a capture
  /// that is itself being made.
  public static func gather(
    store: SessionStore, project: String, level: String, room: String, phases: [CapturePhase],
    excluding: String? = nil
  ) -> RoomHistory {
    let layouts = ((try? store.sessions(inProject: project)) ?? []).reversed()
    let projectDirectory = store.root.appendingPathComponent(project, isDirectory: true)
    let wanted = Set(phases)
    var entries: [Entry] = []
    for layout in layouts {
      let id = layout.root.lastPathComponent
      guard id != excluding, let manifest = store.manifest(at: layout), manifest.status != .incomplete,
        manifest.level.slug == level, manifest.room.slug == room,
        !wanted.isDisjoint(with: manifest.phases)
      else { continue }
      let items = JSONLReader.records(StillRecord.self, in: layout.stills).compactMap(\.item)
      var cameras: [WallCoverage.Camera] = []
      var walk: [(x: Double, z: Double)] = []
      if let placement = AlignmentFile.read(at: AlignmentFile.url(projectDirectory: projectDirectory, sessionID: id)),
        placement.tHs.count == 16
      {
        for frame in JSONLReader.records(FrameRecord.self, in: layout.frames) {
          let pose = frame.poseWorldFromCamera
          walk.append(housePoint(placement.tHs, x: pose.elements[12], z: pose.elements[14]))
          if let camera = WallCoverage.Camera(
            pose: pose, fx: frame.intrinsics.fx, fy: frame.intrinsics.fy, width: frame.width, height: frame.height)
          {
            cameras.append(camera.moved(byTHs: placement.tHs))
          }
        }
      }
      entries.append(Entry(sessionID: id, cameras: cameras, walk: walk, stillItems: items))
    }
    return RoomHistory(entries: entries)
  }

  /// A session point in the house frame through a stored `T_hs`, column-major.
  public static func housePoint(_ t: [Double], x: Double, z: Double) -> (x: Double, z: Double) {
    guard t.count == 16 else { return (x, z) }
    return (t[0] * x + t[8] * z + t[12], t[2] * x + t[10] * z + t[14])
  }
}
