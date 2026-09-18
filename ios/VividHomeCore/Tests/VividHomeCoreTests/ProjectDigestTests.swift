import XCTest

@testable import VividHomeCore

final class ProjectDigestTests: XCTestCase {

  private func manifest(
    project: String = "our-house", projectName: String = "Our house",
    level: String = "level-1", levelName: String = "Level 1", levelIndex: Int = 1,
    room: String = "kitchen", roomName: String = "Kitchen",
    phases: [CapturePhase] = [.framing], startedAt: String = "2026-09-15T10:00:00Z"
  ) -> Manifest {
    Manifest(
      sessionID: "20260915-100000_\(level)_\(room)_aaaaaa",
      status: .complete,
      project: SlugRef(slug: project, name: projectName),
      level: LevelRef(slug: level, name: levelName, index: levelIndex),
      room: SlugRef(slug: room, name: roomName),
      phases: phases,
      device: DeviceInfo(model: "iPhone16,1", iosVersion: "26", appVersion: "0.1.0", appBuild: "38"),
      capture: CaptureInfo(
        startedAt: startedAt, duration: 40,
        videoFormat: VideoFormat(w: 1920, h: 1440, fps: 60),
        keyframePolicy: KeyframePolicySettings(
          minDt: 0.25, minTranslation: 0.15, minRotationDegrees: 10),
        depth: DepthFormat(w: 256, h: 192), jpegQuality: 0.85, markerPhysicalWidth: 0.2,
        sceneReconstruction: "meshWithClassification"))
  }

  func testAnEmptyProjectHasNoLevels() {
    let digest = ProjectDigest.make(project: "our-house", from: [])
    XCTAssertEqual(digest.levels, [])
    XCTAssertEqual(digest.capturedRooms, 0)
    XCTAssertEqual(digest.name, "our-house")
  }

  /// The bug the directory-name count has: two passes in one trade is one trade
  /// recorded, not two, and a fraction built from session count over-reports it.
  func testWalkingOneRoomTwiceInOneTradeIsOneTrade() {
    let digest = ProjectDigest.make(
      project: "our-house",
      from: [
        manifest(phases: [.framing], startedAt: "2026-09-15T10:00:00Z"),
        manifest(phases: [.framing], startedAt: "2026-09-15T14:00:00Z"),
      ])
    let room = digest.levels[0].rooms[0]
    XCTAssertEqual(room.phases, [.framing])
    XCTAssertEqual(room.sessions, 2)
  }

  /// The other half the name cannot see: one pass can expose several trades.
  func testOneSessionContributesEveryPhaseItRecorded() {
    let digest = ProjectDigest.make(
      project: "our-house", from: [manifest(phases: [.framing, .electrical, .plumbing])])
    XCTAssertEqual(digest.levels[0].rooms[0].phases, [.framing, .electrical, .plumbing])
    XCTAssertEqual(digest.levels[0].rooms[0].sessions, 1)
  }

  func testPhasesReadInTheOrderTheWorkHappens() {
    let digest = ProjectDigest.make(
      project: "our-house", from: [manifest(phases: [.drywall, .framing, .electrical])])
    XCTAssertEqual(digest.levels[0].rooms[0].orderedPhases, [.framing, .electrical, .drywall])
  }

  func testLevelsSortByStoreyThenName() {
    let digest = ProjectDigest.make(
      project: "our-house",
      from: [
        manifest(level: "basement", levelName: "Basement", levelIndex: 0, room: "plant"),
        manifest(level: "level-2", levelName: "Level 2", levelIndex: 2, room: "bed"),
        manifest(level: "level-1", levelName: "Level 1", levelIndex: 1, room: "kitchen"),
      ])
    XCTAssertEqual(digest.levels.map(\.name), ["Level 2", "Level 1", "Basement"])
  }

  func testRoomsAreGroupedUnderTheirLevel() {
    let digest = ProjectDigest.make(
      project: "our-house",
      from: [
        manifest(room: "kitchen", roomName: "Kitchen"),
        manifest(room: "entry", roomName: "Entry"),
        manifest(level: "basement", levelName: "Basement", levelIndex: 0, room: "store", roomName: "Store"),
      ])
    XCTAssertEqual(digest.levels.count, 2)
    XCTAssertEqual(digest.levels[0].rooms.map(\.name), ["Entry", "Kitchen"])
    XCTAssertEqual(digest.levels[1].rooms.map(\.name), ["Store"])
    XCTAssertEqual(digest.capturedRooms, 3)
  }

  func testTheLatestCaptureWins() {
    let digest = ProjectDigest.make(
      project: "our-house",
      from: [
        manifest(startedAt: "2026-09-15T10:00:00Z"),
        manifest(startedAt: "2026-09-16T09:00:00Z"),
        manifest(startedAt: "2026-09-14T23:00:00Z"),
      ])
    XCTAssertEqual(digest.levels[0].rooms[0].lastCaptured, "2026-09-16T09:00:00Z")
  }

  /// A caller handing over the wrong directory should get nothing, not a
  /// plausible merge of two houses.
  func testManifestsFromAnotherProjectAreIgnored() {
    let digest = ProjectDigest.make(
      project: "our-house",
      from: [
        manifest(project: "our-house", room: "kitchen"),
        manifest(project: "other-house", room: "garage"),
      ])
    XCTAssertEqual(digest.capturedRooms, 1)
    XCTAssertEqual(digest.levels[0].rooms.map(\.room), ["kitchen"])
  }

  func testTheProjectNameComesFromTheManifests() {
    let digest = ProjectDigest.make(
      project: "our-house", from: [manifest(projectName: "Willow Street")])
    XCTAssertEqual(digest.name, "Willow Street")
  }

  func testSessionsCountsEveryCaptureAcrossLevels() {
    let digest = ProjectDigest.make(
      project: "our-house",
      from: [
        manifest(room: "kitchen"), manifest(room: "kitchen"),
        manifest(level: "basement", levelIndex: 0, room: "store"),
      ])
    XCTAssertEqual(digest.sessions, 3)
  }
}
