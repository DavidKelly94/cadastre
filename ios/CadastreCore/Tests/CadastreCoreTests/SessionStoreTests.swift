import Foundation
import XCTest

@testable import CadastreCore

/// Repair is what turns a crashed capture into a usable one, so it is tested
/// against sessions that were deliberately left in a bad state.
final class SessionStoreTests: XCTestCase {
  private var documents: URL!
  private var store: SessionStore!

  override func setUpWithError() throws {
    documents = FileManager.default.temporaryDirectory
      .appendingPathComponent("cadastre-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    store = SessionStore(documents: documents)
  }

  override func tearDownWithError() throws {
    if let documents, FileManager.default.fileExists(atPath: documents.path) {
      try FileManager.default.removeItem(at: documents)
    }
  }

  @discardableResult
  private func makeSession(
    project: String = "our-house",
    id: String = "20261103-141502_main_kitchen_electrical_k3x7qa",
    status: SessionStatus = .incomplete,
    keyframes: Int = 3,
    trailingNewline: Bool = true
  ) throws -> SessionLayout {
    let layout = SessionLayout(
      root: documents
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent(project, isDirectory: true)
        .appendingPathComponent(id, isDirectory: true))
    try layout.createDirectories()

    var lines = ""
    let encoder = JSONLWriter.makeEncoder()
    for index in 0..<keyframes {
      let paths = FrameRecord.paths(forKeyframe: index)
      let record = FrameRecord(
        index: index,
        time: Double(index) * 0.5,
        poseWorldFromCamera: .identity,
        intrinsics: Intrinsics(fx: 48, fy: 48, cx: 32, cy: 24),
        width: 64, height: 48, depthWidth: 8, depthHeight: 6,
        exposureDuration: 0.008, exposureOffset: 0,
        tracking: .normal, reason: .none, thermal: .nominal,
        rgb: paths.rgb, depth: paths.depth, conf: paths.conf)
      lines += String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
      // Some real bytes, so the counted size is not zero.
      try Data(repeating: 0, count: 100).write(to: layout.depth(keyframe: index))
    }
    if !trailingNewline, lines.hasSuffix("\n") {
      lines.removeLast()
    }
    try lines.write(to: layout.frames, atomically: true, encoding: .utf8)

    var manifest = Manifest.starting(
      sessionID: SessionID(id)!,
      project: SlugRef(slug: project, name: project),
      level: LevelRef(slug: "main", name: "Main", index: 1),
      room: SlugRef(slug: "kitchen", name: "Kitchen"),
      device: DeviceInfo(model: "x", iosVersion: "26", appVersion: "0.1.0", appBuild: "1"),
      startedAt: "2026-11-03T14:15:02-05:00",
      videoFormat: VideoFormat(w: 64, h: 48, fps: 30),
      keyframePolicy: KeyframePolicy.documentedDefault,
      depth: DepthFormat(w: 8, h: 6),
      jpegQuality: 0.85,
      markerPhysicalWidth: 0.2,
      sceneReconstruction: "meshWithClassification")
    if status != .incomplete {
      manifest = manifest.finalized(
        endedAt: "2026-11-03T14:15:04-05:00", duration: 2.0,
        stats: SessionStats(keyframes: 99))
    }
    try JSONLWriter.makeEncoder().encode(manifest).write(to: layout.manifest)
    return layout
  }

  // MARK: - Listing

  func testAnEmptyDocumentsDirectoryListsNothing() throws {
    XCTAssertEqual(try store.projects(), [])
    XCTAssertEqual(try store.sessions(inProject: "our-house").count, 0)
  }

  func testProjectsAndSessionsAreListed() throws {
    try makeSession(project: "our-house")
    try makeSession(project: "cabin", id: "20261104-090000_main_hall_framing_bbbbbb")

    XCTAssertEqual(try store.projects(), ["cabin", "our-house"])
    XCTAssertEqual(try store.sessions(inProject: "our-house").count, 1)
  }

  func testSessionsAreNewestFirstByIdNotByFileDate() throws {
    // The id starts with a timestamp, so the name is the capture order. A file
    // date is whenever the bytes landed, which copying off the phone changes.
    try makeSession(id: "20261101-090000_main_a_framing_aaaaaa")
    try makeSession(id: "20261105-090000_main_b_framing_bbbbbb")
    try makeSession(id: "20261103-090000_main_c_framing_cccccc")

    let ids = try store.sessions(inProject: "our-house").map(\.root.lastPathComponent)
    XCTAssertEqual(ids.first, "20261105-090000_main_b_framing_bbbbbb")
    XCTAssertEqual(ids.last, "20261101-090000_main_a_framing_aaaaaa")
  }

  func testHiddenDirectoriesAreIgnored() throws {
    try makeSession()
    let hidden = documents.appendingPathComponent("sessions/.DS_Store_dir", isDirectory: true)
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    XCTAssertEqual(try store.projects(), ["our-house"])
  }

  // MARK: - Repair

  func testAnIncompleteSessionIsRepairedFromWhatIsOnDisk() throws {
    let layout = try makeSession(status: .incomplete, keyframes: 4)

    let repaired = try store.repairIfNeeded(at: layout, endedAt: "2026-11-03T14:20:00-05:00")
    XCTAssertNotNil(repaired)
    XCTAssertEqual(repaired?.status, .repaired)
    XCTAssertEqual(repaired?.stats.keyframes, 4)
    XCTAssertEqual(repaired?.capture.endedAt, "2026-11-03T14:20:00-05:00")
    // Duration comes from the last frame's timestamp: 3 * 0.5.
    XCTAssertEqual(repaired?.capture.duration ?? 0, 1.5, accuracy: 1e-9)
    XCTAssertGreaterThan(repaired?.stats.bytes ?? 0, 0)

    // And it was written, not only returned.
    XCTAssertEqual(store.manifest(at: layout)?.status, .repaired)
  }

  func testACleanSessionIsLeftExactlyAsItIs() throws {
    // Rewriting a good manifest could only lose information.
    let layout = try makeSession(status: .complete)
    let before = try Data(contentsOf: layout.manifest)

    XCTAssertNil(try store.repairIfNeeded(at: layout))
    XCTAssertEqual(try Data(contentsOf: layout.manifest), before)
    XCTAssertEqual(store.manifest(at: layout)?.stats.keyframes, 99)
  }

  func testRepairIsIdempotent() throws {
    let layout = try makeSession(status: .incomplete)
    XCTAssertNotNil(try store.repairIfNeeded(at: layout))
    XCTAssertNil(try store.repairIfNeeded(at: layout), "a repaired session is not incomplete")
  }

  func testATruncatedFinalLineIsNotCounted() throws {
    // A session that died mid-write leaves a half-written line. Counting it
    // would claim a keyframe whose record cannot be parsed.
    let layout = try makeSession(status: .incomplete, keyframes: 5, trailingNewline: false)
    let repaired = try store.repairIfNeeded(at: layout)
    XCTAssertEqual(repaired?.stats.keyframes, 4, "the partial last line must not count")
  }

  func testRepairAllFindsEverySessionThatNeedsIt() throws {
    try makeSession(id: "20261101-090000_main_a_framing_aaaaaa", status: .incomplete)
    try makeSession(id: "20261102-090000_main_b_framing_bbbbbb", status: .complete)
    try makeSession(project: "cabin", id: "20261103-090000_main_c_framing_cccccc", status: .incomplete)

    let repaired = try store.repairAll()
    XCTAssertEqual(
      repaired.sorted(),
      ["20261101-090000_main_a_framing_aaaaaa", "20261103-090000_main_c_framing_cccccc"])
  }

  func testASessionWithNoManifestIsSkippedRatherThanCrashing() throws {
    let layout = try makeSession(status: .incomplete)
    try FileManager.default.removeItem(at: layout.manifest)
    XCTAssertNil(try store.repairIfNeeded(at: layout))
    XCTAssertNil(store.manifest(at: layout))
  }

  func testAnUnreadableManifestIsSkippedRatherThanCrashing() throws {
    let layout = try makeSession(status: .incomplete)
    try "{not json".write(to: layout.manifest, atomically: true, encoding: .utf8)
    XCTAssertNil(try store.repairIfNeeded(at: layout))
  }

  // MARK: - Counting

  func testLineCounting() throws {
    let file = documents.appendingPathComponent("lines.jsonl")
    try "".write(to: file, atomically: true, encoding: .utf8)
    XCTAssertEqual(SessionStore.completeLines(in: file), 0)

    try "{\"a\":1}\n".write(to: file, atomically: true, encoding: .utf8)
    XCTAssertEqual(SessionStore.completeLines(in: file), 1)

    try "{\"a\":1}\n{\"a\":2}\n".write(to: file, atomically: true, encoding: .utf8)
    XCTAssertEqual(SessionStore.completeLines(in: file), 2)

    try "{\"a\":1}\n{\"a\":2".write(to: file, atomically: true, encoding: .utf8)
    XCTAssertEqual(SessionStore.completeLines(in: file), 1)
  }

  func testCountingAMissingFileIsZeroNotAnError() {
    XCTAssertEqual(
      SessionStore.completeLines(in: documents.appendingPathComponent("nope.jsonl")), 0)
  }

  func testDeleteRemovesTheWholeSession() throws {
    let layout = try makeSession()
    try store.delete(at: layout)
    XCTAssertFalse(FileManager.default.fileExists(atPath: layout.root.path))
  }
}
