import Foundation
import XCTest

@testable import VividHomeCore

/// The photos a session holds are what the owner reviews on the phone and what
/// travels into the camera roll, so what the reader says about them has to
/// match the files, and the label has to say only what the session knows.
final class SessionPhotosTests: XCTestCase {
  private var documents: URL!
  private var layout: SessionLayout!

  private let manifestJSON = """
    {"format_version":3,"session_id":"20261103-141502_main_kitchen_k3x7qa","status":"complete",
     "project":{"slug":"our-house","name":"Our House"},
     "level":{"slug":"main","name":"Main Floor","index":1},
     "room":{"slug":"kitchen","name":"Kitchen"},
     "phases":["electrical","plumbing"],"expected_markers":[],
     "device":{"model":"x","ios_version":"26","app_version":"0.1.0","app_build":"1"},
     "capture":{"started_at":"2026-11-03T14:15:02-05:00","ended_at":"2026-11-03T14:15:04-05:00",
       "duration_s":2.0,"video_format":{"w":64,"h":48,"fps":30},
       "keyframe_policy":{"min_dt_s":0.1,"min_translation_m":0.1,"min_rotation_deg":5},
       "depth":{"w":8,"h":6,"dtype":"float32","units":"m"},"jpeg_quality":0.85,
       "marker_physical_width_m":0.2,"scene_reconstruction":"meshWithClassification"},
     "coordinate_frame":{"name":"arkit-session","up":"+y","units":"m","matrix_order":"column-major"},
     "stats":{"keyframes":3,"dropped":0,"stills":1,"marker_observations":0,"landmarks":3,
       "tracking_limited_s":0,"thermal_max":"nominal","bytes":0}}
    """

  override func setUpWithError() throws {
    documents = FileManager.default.temporaryDirectory
      .appendingPathComponent("vividhome-photos-\(UUID().uuidString)", isDirectory: true)
    layout = SessionLayout(
      documents: documents, project: "our-house",
      sessionID: SessionID("20261103-141502_main_kitchen_k3x7qa")!)
    try layout.createDirectories()
    try manifestJSON.write(to: layout.manifest, atomically: true, encoding: .utf8)
  }

  override func tearDownWithError() throws {
    if let documents, FileManager.default.fileExists(atPath: documents.path) {
      try FileManager.default.removeItem(at: documents)
    }
  }

  private func frameLine(_ index: Int, time: Double, pose: Transform = .identity) throws -> String {
    let paths = FrameRecord.paths(forKeyframe: index)
    let record = FrameRecord(
      index: index, time: time, poseWorldFromCamera: pose,
      intrinsics: Intrinsics(fx: 48, fy: 48, cx: 32, cy: 24),
      width: 64, height: 48, depthWidth: 8, depthHeight: 6,
      exposureDuration: 0.008, exposureOffset: 0,
      tracking: .normal, reason: .none, thermal: .nominal,
      rgb: paths.rgb, depth: paths.depth, conf: paths.conf)
    return String(decoding: try JSONLWriter.makeEncoder().encode(record), as: UTF8.self)
  }

  private func writeSession(truncatedTail: Bool = false) throws {
    var frames = try [
      frameLine(0, time: 0.0), frameLine(1, time: 0.5), frameLine(2, time: 1.0),
    ].joined(separator: "\n") + "\n"
    if truncatedTail {
      frames += "{\"i\":3,\"t\":1.5,\"T_wc\":[1,0,0,0,0,1"
    }
    try frames.write(to: layout.frames, atomically: true, encoding: .utf8)

    let still = StillRecord(
      stillIndex: 0, index: 1, time: 0.7, poseWorldFromCamera: .identity,
      intrinsics: Intrinsics(fx: 96, fy: 96, cx: 64, cy: 48), width: 128, height: 96,
      exposureDuration: 0.008, exposureOffset: 0, tracking: .normal, reason: .none,
      thermal: .nominal, path: StillRecord.path(forStill: 0))
    let stillLine = String(decoding: try JSONLWriter.makeEncoder().encode(still), as: UTF8.self)
    try (stillLine + "\n").write(to: layout.stills, atomically: true, encoding: .utf8)

    let landmarks = [
      LandmarkRecord(
        time: 0.4, index: 1, label: "kitchen corner 1", kind: .corner,
        position: Vector3(1, 0, 2), method: "raycast-estimatedPlane"),
      LandmarkRecord(
        time: 0.45, index: 1, label: "kitchen door 1", kind: .door,
        position: Vector3(1, 0, 3), method: "raycast-estimatedPlane"),
      LandmarkRecord(
        time: 0.9, index: 2, label: "kitchen corner 2", kind: .corner,
        position: Vector3(3, 0, 2), method: "raycast-estimatedPlane"),
    ]
    let encoder = JSONLWriter.makeEncoder()
    let lines = try landmarks.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
    try (lines.joined(separator: "\n") + "\n").write(
      to: layout.landmarks, atomically: true, encoding: .utf8)
  }

  // MARK: - Reading

  func testPhotosAreReadInTimeOrderWithStillsAfterTheirKeyframe() throws {
    try writeSession()
    let photos = SessionPhotos.read(at: layout)
    XCTAssertEqual(photos.keyframeCount, 3)
    XCTAssertEqual(photos.stillCount, 1)
    XCTAssertEqual(photos.photos.map(\.id), ["keyframe-0", "keyframe-1", "still-0", "keyframe-2"])
    XCTAssertEqual(photos.photos[2].path, "stills/000.jpg")
    XCTAssertEqual(photos.photos[2].width, 128)
    XCTAssertEqual(photos.photos[1].path, "rgb/000001.jpg")
  }

  func testLandmarksTappedAtAKeyframeAreAttachedToIt() throws {
    try writeSession()
    let photos = SessionPhotos.read(at: layout).photos
    XCTAssertEqual(photos[0].landmarkLabels, [])
    XCTAssertEqual(photos[1].landmarkLabels, ["kitchen corner 1", "kitchen door 1"])
    XCTAssertEqual(photos[2].landmarkLabels, [], "a still carries no taps")
    XCTAssertEqual(photos[3].landmarkLabels, ["kitchen corner 2"])
  }

  func testATruncatedLastLineIsSkippedNotFatal() throws {
    try writeSession(truncatedTail: true)
    XCTAssertEqual(SessionPhotos.read(at: layout).keyframeCount, 3)
  }

  func testAMissingFileReadsAsNoPhotos() throws {
    XCTAssertEqual(SessionPhotos.read(at: layout).photos, [])
  }

  func testSamplingKeepsEveryStill() throws {
    try writeSession()
    let sampled = SessionPhotos.read(at: layout).sampled(stride: 2)
    XCTAssertEqual(sampled.map(\.id), ["keyframe-0", "still-0", "keyframe-2"])
    XCTAssertEqual(SessionPhotos.read(at: layout).sampled(stride: 0).count, 4, "stride 0 is 1")
  }

  // MARK: - Labels

  func testTheLabelSaysWhatTheSessionKnows() throws {
    try writeSession()
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(manifestJSON.utf8))
    let photos = SessionPhotos.read(at: layout).photos

    let label = PhotoLabel.make(
      for: photos[1], manifest: manifest, sessionID: "20261103-141502_main_kitchen_k3x7qa")
    XCTAssertEqual(label.headline, "Our House · Main Floor · Kitchen · electrical, plumbing")
    XCTAssertEqual(label.frame, "keyframe 1 · 0.5 s")
    XCTAssertEqual(label.landmarks, "kitchen corner 1, kitchen door 1 tapped here")
    XCTAssertEqual(
      label.caption,
      "Our House · Main Floor · Kitchen · electrical, plumbing\nkeyframe 1 · 0.5 s\n"
        + "kitchen corner 1, kitchen door 1 tapped here")
    XCTAssertEqual(
      label.keywords,
      ["VividHome", "20261103-141502_main_kitchen_k3x7qa", "keyframe 1", "our-house", "main", "kitchen"]
    )

    let still = PhotoLabel.make(for: photos[2], manifest: manifest, sessionID: "x")
    XCTAssertEqual(still.frame, "still 0 · 0.7 s")
    XCTAssertNil(still.landmarks)
  }

  func testTakenAtIsTheStartPlusTheFrameTime() throws {
    try writeSession()
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(manifestJSON.utf8))
    let photo = SessionPhotos.read(at: layout).photos[1]
    let label = PhotoLabel.make(for: photo, manifest: manifest, sessionID: "x")
    let start = PhotoLabel.date(fromISO8601: "2026-11-03T14:15:02-05:00")
    XCTAssertNotNil(start)
    XCTAssertEqual(label.takenAt, start.map { $0.addingTimeInterval(0.5) })
    XCTAssertEqual(start?.timeIntervalSince1970, 1793733302)
  }

  func testWithoutAManifestTheLabelFallsBackToTheSessionID() throws {
    try writeSession()
    let photo = SessionPhotos.read(at: layout).photos[0]
    let label = PhotoLabel.make(for: photo, manifest: nil, sessionID: "20261103-141502_main_kitchen_k3x7qa")
    XCTAssertEqual(label.headline, "20261103-141502_main_kitchen_k3x7qa")
    XCTAssertNil(label.takenAt)
    XCTAssertEqual(label.keywords.count, 3)
  }

  func testFractionalSecondsAndPlainTimestampsBothParse() {
    XCTAssertNotNil(PhotoLabel.date(fromISO8601: "2026-11-03T14:15:02.250-05:00"))
    XCTAssertNotNil(PhotoLabel.date(fromISO8601: "2026-11-03T19:15:02Z"))
    XCTAssertNil(PhotoLabel.date(fromISO8601: "yesterday"))
  }

  // MARK: - Orientation

  private func rotation(columns: [[Double]]) -> Transform {
    // Three rotation columns as camera axes in world; translation zero.
    var elements: [Double] = []
    for column in columns { elements += column + [0] }
    elements += [0, 0, 0, 1]
    return Transform(elements: elements)!
  }

  func testAnUprightLandscapeImageIsShownAsStored() {
    XCTAssertEqual(DisplayOrientation.from(pose: .identity), .upright)
    XCTAssertEqual(DisplayOrientation.upright.exifOrientation, 1)
    XCTAssertEqual(DisplayOrientation.upright.degreesClockwise, 0)
  }

  func testWorldUpOnTheImagesLeftTurnsItClockwise() {
    // Camera +x points down in the world, camera +y points along world +x:
    // the phone was held upright with the sensor's top on the left.
    let pose = rotation(columns: [[0, -1, 0], [1, 0, 0], [0, 0, 1]])
    XCTAssertEqual(pose[1, 0], -1)
    XCTAssertEqual(DisplayOrientation.from(pose: pose), .rotate90Clockwise)
    XCTAssertEqual(DisplayOrientation.rotate90Clockwise.exifOrientation, 6)
    XCTAssertEqual(DisplayOrientation.rotate90Clockwise.degreesClockwise, 90)
  }

  func testWorldUpOnTheImagesRightTurnsItCounterclockwise() {
    let pose = rotation(columns: [[0, 1, 0], [-1, 0, 0], [0, 0, 1]])
    XCTAssertEqual(pose[1, 0], 1)
    XCTAssertEqual(DisplayOrientation.from(pose: pose), .rotate90Counterclockwise)
    XCTAssertEqual(DisplayOrientation.rotate90Counterclockwise.exifOrientation, 8)
    XCTAssertEqual(DisplayOrientation.rotate90Counterclockwise.degreesClockwise, 270)
  }

  func testAnUpsideDownImageTurnsAHalfTurn() {
    let pose = rotation(columns: [[-1, 0, 0], [0, -1, 0], [0, 0, 1]])
    XCTAssertEqual(DisplayOrientation.from(pose: pose), .rotate180)
    XCTAssertEqual(DisplayOrientation.rotate180.exifOrientation, 3)
  }

  func testACameraPointedAtTheFloorHasNoRollToCorrect() {
    // Camera -z is world -y: looking straight down. World up lands on camera z.
    let pose = rotation(columns: [[1, 0, 0], [0, 0, -1], [0, 1, 0]])
    XCTAssertEqual(abs(pose[1, 2]), 1)
    XCTAssertEqual(DisplayOrientation.from(pose: pose), .upright)
  }

  func testASlightRollStillReadsAsUpright() {
    // 20 degrees of roll about the optical axis: y still dominates.
    let c = cos(20.0 * .pi / 180), s = sin(20.0 * .pi / 180)
    let pose = rotation(columns: [[c, s, 0], [-s, c, 0], [0, 0, 1]])
    XCTAssertEqual(DisplayOrientation.from(pose: pose), .upright)
  }
}
