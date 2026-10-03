import Foundation
import XCTest

@testable import VividHomeCore

/// A top-up reads the room's earlier captures with it: their keyframes in the
/// house frame through their own placements, and their stills.
final class RoomHistoryTests: XCTestCase {
  private var documents: URL!
  private var store: SessionStore!
  private let project = "our-house"

  override func setUpWithError() throws {
    documents = FileManager.default.temporaryDirectory
      .appendingPathComponent("vividhome-history-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    store = SessionStore(documents: documents)
  }

  override func tearDownWithError() throws {
    if let documents, FileManager.default.fileExists(atPath: documents.path) {
      try FileManager.default.removeItem(at: documents)
    }
  }

  /// A complete capture with two keyframes at (1, 0) and (2, 0) looking +x,
  /// stills for the given items, and optionally a placement shifting by (1, 2).
  private func makeSession(
    id: String, room: String = "kitchen", level: String = "main", phases: [CapturePhase] = [.electrical],
    complete: Bool = true, items: [String?] = [], placed: Bool = true
  ) throws {
    let layout = SessionLayout(
      root: documents.appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent(project, isDirectory: true).appendingPathComponent(id, isDirectory: true))
    try layout.createDirectories()
    let encoder = JSONLWriter.makeEncoder()

    var frames = ""
    for (index, x) in [1.0, 2.0].enumerated() {
      // Camera looking along +x: its -z axis is +x, so the z column is (-1, 0, 0).
      let pose = Transform(elements: [0, 0, 1, 0, 0, 1, 0, 0, -1, 0, 0, 0, x, 1.4, 0, 1])!
      let paths = FrameRecord.paths(forKeyframe: index)
      let record = FrameRecord(
        index: index, time: Double(index) * 0.5, poseWorldFromCamera: pose,
        intrinsics: Intrinsics(fx: 1400, fy: 1400, cx: 960, cy: 720), width: 1920, height: 1440,
        depthWidth: 256, depthHeight: 192, exposureDuration: 0.008, exposureOffset: 0,
        tracking: .normal, reason: .none, thermal: .nominal, rgb: paths.rgb, depth: paths.depth, conf: paths.conf)
      frames += String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
    try frames.write(to: layout.frames, atomically: true, encoding: .utf8)

    var stills = ""
    for (index, item) in items.enumerated() {
      let record = StillRecord(
        stillIndex: index, index: 0, time: 1, poseWorldFromCamera: .identity,
        intrinsics: Intrinsics(fx: 1, fy: 1, cx: 0, cy: 0), width: 4032, height: 3024,
        exposureDuration: 0.01, exposureOffset: 0, tracking: .normal, reason: .none, thermal: .nominal,
        path: StillRecord.path(forStill: index), item: item)
      stills += String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
    try stills.write(to: layout.stills, atomically: true, encoding: .utf8)

    var manifest = Manifest.starting(
      sessionID: SessionID(id)!, project: SlugRef(slug: project, name: "Our House"),
      level: LevelRef(slug: level, name: level, index: 1), room: SlugRef(slug: room, name: room),
      phases: phases, device: DeviceInfo(model: "x", iosVersion: "26", appVersion: "0.1.0", appBuild: "1"),
      startedAt: "2026-11-03T14:15:02-05:00", videoFormat: VideoFormat(w: 1920, h: 1440, fps: 30),
      keyframePolicy: KeyframePolicySettings(minDt: 0.1, minTranslation: 0.1, minRotationDegrees: 5),
      depth: DepthFormat(w: 256, h: 192), jpegQuality: 0.85, markerPhysicalWidth: 0.2,
      sceneReconstruction: "meshWithClassification")
    if complete {
      manifest = manifest.finalized(endedAt: "2026-11-03T14:19:48-05:00", duration: 286, stats: SessionStats())
    }
    try JSONEncoder().encode(manifest).write(to: layout.manifest)

    if placed {
      let pairs = [
        PlanAlignment.Pair(label: "corner-nw", sessionXZ: (0, 0), houseXZ: (1, 2)),
        PlanAlignment.Pair(label: "corner-ne", sessionXZ: (4, 0), houseXZ: (5, 2)),
      ]
      let solution = try XCTUnwrap(PlanAlignment.solve(pairs: pairs, floorY: 0, floorSource: "x", floorHeight: 0))
      let file = AlignmentFile(sessionID: id, level: level, solution: solution)
      try file.write(to: AlignmentFile.url(projectDirectory: store.root.appendingPathComponent(project), sessionID: id))
    }
  }

  func testEarlierCapturesOfTheRoomComeThroughTheirOwnPlacements() throws {
    try makeSession(id: "20261103-141502_main_kitchen_aaaaaa", items: ["panel", nil, "boxes"])
    try makeSession(id: "20261103-151502_main_kitchen_bbbbbb", items: ["wall"], placed: false)

    let history = RoomHistory.gather(
      store: store, project: project, level: "main", room: "kitchen", phases: [.electrical, .plumbing])
    XCTAssertEqual(history.sessionIDs, ["20261103-141502_main_kitchen_aaaaaa", "20261103-151502_main_kitchen_bbbbbb"], "oldest first")
    XCTAssertEqual(history.stillItems, ["panel", "boxes", "wall"])

    // The placed capture's keyframes, shifted by (1, 2) into the house frame, still looking +x.
    XCTAssertEqual(history.cameras.count, 2)
    XCTAssertEqual(history.cameras[0].x, 2, accuracy: 1e-9)
    XCTAssertEqual(history.cameras[0].z, 2, accuracy: 1e-9)
    XCTAssertEqual(history.cameras[1].x, 3, accuracy: 1e-9)
    XCTAssertEqual(history.cameras[0].forwardX, 1, accuracy: 1e-9)
    XCTAssertEqual(history.cameras[0].forwardZ, 0, accuracy: 1e-9)
    XCTAssertEqual(history.walks.count, 1, "the unplaced capture has no walk to draw")
    XCTAssertEqual(history.walks[0].count, 2)
    XCTAssertEqual(history.walks[0][1].x, 3, accuracy: 1e-9)
    XCTAssertEqual(history.walks[0][1].z, 2, accuracy: 1e-9)
    XCTAssertEqual(history.entries[1].cameras.count, 0)
  }

  func testOtherRoomsTradesLevelsAndUnfinishedCapturesAreLeftOut() throws {
    try makeSession(id: "20261103-141502_main_kitchen_aaaaaa", items: ["panel"])
    try makeSession(id: "20261103-141502_main_pantry_cccccc", room: "pantry", items: ["panel"])
    try makeSession(id: "20261103-141502_main_kitchen_dddddd", phases: [.framing], items: ["headers"])
    try makeSession(id: "20261103-141502_upper_kitchen_eeeeee", level: "upper", items: ["panel"])
    try makeSession(id: "20261103-141502_main_kitchen_ffffff", complete: false, items: ["panel"])

    let history = RoomHistory.gather(store: store, project: project, level: "main", room: "kitchen", phases: [.electrical])
    XCTAssertEqual(history.sessionIDs, ["20261103-141502_main_kitchen_aaaaaa"])

    let without = RoomHistory.gather(
      store: store, project: project, level: "main", room: "kitchen", phases: [.electrical],
      excluding: "20261103-141502_main_kitchen_aaaaaa")
    XCTAssertTrue(without.entries.isEmpty)
    XCTAssertTrue(RoomHistory.gather(store: store, project: "elsewhere", level: "main", room: "kitchen", phases: [.electrical]).entries.isEmpty)
  }

  func testAStoredTransformMovesACameraAsTheLivePlacementDoes() throws {
    let pairs = [
      PlanAlignment.Pair(label: "a", sessionXZ: (0, 0), houseXZ: (1, 2)),
      PlanAlignment.Pair(label: "b", sessionXZ: (1, 0), houseXZ: (1, 3)),
      PlanAlignment.Pair(label: "c", sessionXZ: (0, 1), houseXZ: (0, 2)),
    ]
    let placement = try XCTUnwrap(PlanAlignment.solve(pairs: pairs, floorY: 0, floorSource: "x", floorHeight: 0))
    let camera = WallCoverage.Camera(x: 1, z: 0, forwardX: 1, forwardZ: 0, spread: 0.5)
    let live = camera.moved(by: placement)
    let stored = camera.moved(byTHs: placement.tHs)
    XCTAssertEqual(live, stored)
    let point = RoomHistory.housePoint(placement.tHs, x: 1, z: 0)
    XCTAssertEqual(point.x, live.x, accuracy: 1e-12)
    XCTAssertEqual(point.z, live.z, accuracy: 1e-12)
    XCTAssertEqual(camera.moved(byTHs: [1, 2, 3]), camera, "a malformed transform moves nothing")
  }
}
