import Foundation
import XCTest

@testable import CadastreCore

final class RecordsTests: XCTestCase {
  private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  private func encodedString<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try encoder().encode(value), as: UTF8.self)
  }

  /// The set of JSON keys `value` encodes to, for pinning field names.
  private func encodedKeys<T: Encodable>(_ value: T) throws -> Set<String> {
    let data = try encoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return Set(object?.keys ?? [:].keys)
  }

  private var sampleTransform: Transform {
    Transform(elements: (0..<16).map { Double($0) * 0.5 })!
  }

  private var sampleIntrinsics: Intrinsics {
    Intrinsics(fx: 1451.5, fy: 1451.5, cx: 960.5, cy: 720.5)
  }

  // MARK: - Golden strings where the encoding is unambiguous

  func testDeviceInfoGoldenString() throws {
    let device = DeviceInfo(
      model: "iPhone16,1", iosVersion: "26.6", appVersion: "0.1.0", appBuild: "37")
    XCTAssertEqual(
      try encodedString(device),
      #"{"app_build":"37","app_version":"0.1.0","ios_version":"26.6","model":"iPhone16,1"}"#)
  }

  func testCoordinateFrameGoldenString() throws {
    XCTAssertEqual(
      try encodedString(CoordinateFrame.arkitSession),
      #"{"matrix_order":"column-major","name":"arkit-session","units":"m","up":"+y"}"#)
  }

  func testKeyframePolicySettingsUsesSnakeCaseKeys() throws {
    let settings = KeyframePolicySettings(
      minDt: 0.125, minTranslation: 0.5, minRotationDegrees: 5.5)
    XCTAssertEqual(
      try encodedString(settings),
      #"{"min_dt_s":0.125,"min_rotation_deg":5.5,"min_translation_m":0.5}"#)
  }

  // MARK: - Field names, which are the part of the contract that can silently drift

  func testFrameRecordEncodesTheDocumentedKeys() throws {
    let frame = FrameRecord(
      index: 123, time: 12.5, poseWorldFromCamera: sampleTransform,
      intrinsics: sampleIntrinsics, width: 1920, height: 1440, depthWidth: 256, depthHeight: 192,
      exposureDuration: 0.0078125, exposureOffset: 0.5, tracking: .normal, reason: .none,
      thermal: .nominal, rgb: "rgb/000123.jpg", depth: "depth/000123.f32", conf: "conf/000123.u8")
    XCTAssertEqual(
      try encodedKeys(frame),
      [
        "i", "t", "T_wc", "K", "w", "h", "dw", "dh", "exp_s", "exp_off",
        "tracking", "reason", "thermal", "rgb", "depth", "conf",
      ])
  }

  func testStillRecordEncodesTheDocumentedKeysAndNoDepth() throws {
    let still = StillRecord(
      stillIndex: 0, index: -1, time: 1.5, poseWorldFromCamera: sampleTransform,
      intrinsics: sampleIntrinsics, width: 4032, height: 3024, exposureDuration: 0.0078125,
      exposureOffset: 0.5, tracking: .normal, reason: .none, thermal: .nominal,
      path: "stills/000.jpg")
    let keys = try encodedKeys(still)
    XCTAssertEqual(
      keys,
      [
        "s", "i", "t", "T_wc", "K", "w", "h", "exp_s", "exp_off",
        "tracking", "reason", "thermal", "path",
      ])
    for depthKey in ["dw", "dh", "depth", "conf"] {
      XCTAssertFalse(keys.contains(depthKey), "stills have no depth: \(depthKey)")
    }
  }

  func testManifestEncodesTheDocumentedKeys() throws {
    let manifest = Manifest(
      sessionID: "20261103-141502_main_kitchen_k3x7qa",
      status: .complete,
      project: SlugRef(slug: "our-house", name: "Our House"),
      level: LevelRef(slug: "main", name: "Main Floor", index: 1),
      room: SlugRef(slug: "kitchen", name: "Kitchen"),
      phases: [.electrical, .plumbing],
      notes: "Panel side rough-in done.",
      expectedMarkers: ["CD-012", "CD-013"],
      device: DeviceInfo(
        model: "iPhone16,1", iosVersion: "26.6", appVersion: "0.1.0", appBuild: "37"),
      capture: CaptureInfo(
        startedAt: "2026-11-03T14:15:02-05:00",
        endedAt: "2026-11-03T14:19:48-05:00",
        duration: 286.5,
        videoFormat: VideoFormat(w: 1920, h: 1440, fps: 30),
        keyframePolicy: KeyframePolicySettings(
          minDt: 0.125, minTranslation: 0.5, minRotationDegrees: 5.5),
        depth: DepthFormat(w: 256, h: 192),
        jpegQuality: 0.85,
        markerPhysicalWidth: 0.2,
        sceneReconstruction: "meshWithClassification"))
    XCTAssertEqual(
      try encodedKeys(manifest),
      [
        "format_version", "session_id", "status", "project", "level", "room", "phases",
        "notes", "expected_markers", "device", "capture", "coordinate_frame", "stats",
      ])
  }

  func testMarkerAndLandmarkKeys() throws {
    let marker = MarkerObservation(
      time: 31.25, index: 211, markerID: "CD-012", poseWorldFromAnchor: sampleTransform,
      tracked: true, physicalWidth: 0.2)
    XCTAssertEqual(
      try encodedKeys(marker), ["t", "i", "marker_id", "T_wa", "tracked", "physical_width_m"])

    let landmark = LandmarkRecord(
      time: 8.5, index: 60, label: "corner-ne", kind: .corner,
      position: Vector3(2.5, -1.25, -0.875), method: "raycast-estimatedPlane")
    XCTAssertEqual(try encodedKeys(landmark), ["t", "i", "label", "kind", "p_w", "method"])
  }

  // MARK: - Decoding the examples from the specification

  func testDecodesTheDocumentedFrameLine() throws {
    let line = """
      {"i":123,"t":12.345,"T_wc":[1,0,0,0,0,1,0,0,0,0,1,0,1.5,2.5,3.5,1],\
      "K":[1451.2,0,960.4,0,1451.2,720.1,0,0,1],\
      "w":1920,"h":1440,"dw":256,"dh":192,"exp_s":0.0083,"exp_off":0.0,\
      "tracking":"normal","reason":"none","thermal":"nominal",\
      "rgb":"rgb/000123.jpg","depth":"depth/000123.f32","conf":"conf/000123.u8"}
      """
    let frame = try JSONDecoder().decode(FrameRecord.self, from: Data(line.utf8))
    XCTAssertEqual(frame.index, 123)
    XCTAssertEqual(frame.time, 12.345)
    XCTAssertEqual(frame.poseWorldFromCamera.translation, Vector3(1.5, 2.5, 3.5))
    XCTAssertEqual(frame.intrinsics.fx, 1451.2)
    XCTAssertEqual(frame.intrinsics.cx, 960.4)
    XCTAssertEqual(frame.intrinsics.cy, 720.1)
    XCTAssertEqual(frame.tracking, .normal)
    XCTAssertEqual(frame.reason, TrackingReason.none)
    XCTAssertEqual(frame.thermal, .nominal)
    XCTAssertEqual(frame.conf, "conf/000123.u8")
  }

  func testDecodesTheDocumentedMarkerAndLandmarkLines() throws {
    let markerLine = """
      {"t":31.02,"i":211,"marker_id":"CD-012",\
      "T_wa":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"tracked":true,"physical_width_m":0.20}
      """
    let marker = try JSONDecoder().decode(MarkerObservation.self, from: Data(markerLine.utf8))
    XCTAssertEqual(marker.markerID, "CD-012")
    XCTAssertTrue(marker.tracked)
    XCTAssertEqual(marker.physicalWidth, 0.20)

    let landmarkLine = """
      {"t":8.7,"i":60,"label":"corner-ne","kind":"corner",\
      "p_w":[2.31,-1.42,-0.87],"method":"raycast-estimatedPlane"}
      """
    let landmark = try JSONDecoder().decode(LandmarkRecord.self, from: Data(landmarkLine.utf8))
    XCTAssertEqual(landmark.kind, .corner)
    XCTAssertEqual(landmark.position, Vector3(2.31, -1.42, -0.87))
  }

  func testUnknownFieldsAreIgnored() throws {
    // Section 12: additive fields keep format_version 2 and readers must ignore
    // what they do not recognise.
    let line = """
      {"t":8.7,"i":60,"label":"corner-ne","kind":"corner","p_w":[1,2,3],\
      "method":"raycast-estimatedPlane","confidence":0.9,"future_field":{"a":[1,2]}}
      """
    let landmark = try JSONDecoder().decode(LandmarkRecord.self, from: Data(line.utf8))
    XCTAssertEqual(landmark.label, "corner-ne")
  }

  func testTransformOfWrongLengthFailsToDecode() {
    let line = #"{"t":1,"i":0,"marker_id":"CD-000","T_wa":[1,0,0],"tracked":true,"physical_width_m":0.2}"#
    XCTAssertThrowsError(
      try JSONDecoder().decode(MarkerObservation.self, from: Data(line.utf8)))
  }

  // MARK: - Round trips

  func testEveryRecordRoundTrips() throws {
    let frame = FrameRecord(
      index: 7, time: 1.25, poseWorldFromCamera: sampleTransform, intrinsics: sampleIntrinsics,
      width: 1920, height: 1440, depthWidth: 256, depthHeight: 192, exposureDuration: 0.0078125,
      exposureOffset: 0.5, tracking: .limited, reason: .excessiveMotion, thermal: .fair,
      rgb: "rgb/000007.jpg", depth: "depth/000007.f32", conf: "conf/000007.u8")
    let decodedFrame = try JSONDecoder().decode(
      FrameRecord.self, from: try encoder().encode(frame))
    XCTAssertEqual(decodedFrame, frame)

    let landmark = LandmarkRecord(
      time: 8.5, index: 60, label: "door-front", kind: .door,
      position: Vector3(1.5, 0, -2.25), method: "raycast-estimatedPlane")
    let decodedLandmark = try JSONDecoder().decode(
      LandmarkRecord.self, from: try encoder().encode(landmark))
    XCTAssertEqual(decodedLandmark, landmark)
  }

  func testPathsAreZeroPadded() {
    let paths = FrameRecord.paths(forKeyframe: 123)
    XCTAssertEqual(paths.rgb, "rgb/000123.jpg")
    XCTAssertEqual(paths.depth, "depth/000123.f32")
    XCTAssertEqual(paths.conf, "conf/000123.u8")
    XCTAssertEqual(StillRecord.path(forStill: 0), "stills/000.jpg")
    XCTAssertEqual(StillRecord.path(forStill: 14), "stills/014.jpg")
  }

  // MARK: - Intrinsics

  func testDepthIntrinsicsScaleWithTheDepthResolution() {
    let frame = FrameRecord(
      index: 0, time: 0, poseWorldFromCamera: .identity,
      intrinsics: Intrinsics(fx: 1440, fy: 1440, cx: 960, cy: 720),
      width: 1920, height: 1440, depthWidth: 256, depthHeight: 192, exposureDuration: 0.008,
      exposureOffset: 0, tracking: .normal, reason: .none, thermal: .nominal,
      rgb: "a", depth: "b", conf: "c")
    let depth = frame.depthIntrinsics
    // 256/1920 and 192/1440 are both 2/15.
    XCTAssertEqual(depth.fx, 1440 * 2.0 / 15.0, accuracy: 1e-9)
    XCTAssertEqual(depth.cx, 960 * 2.0 / 15.0, accuracy: 1e-9)
    XCTAssertEqual(depth.fy, 1440 * 2.0 / 15.0, accuracy: 1e-9)
    XCTAssertEqual(depth.cy, 720 * 2.0 / 15.0, accuracy: 1e-9)
  }

  func testIntrinsicsPlausibilityIsValidationRuleFive() {
    XCTAssertTrue(sampleIntrinsics.isPlausible(width: 1920, height: 1440))
    XCTAssertFalse(
      Intrinsics(fx: 0, fy: 1451, cx: 960, cy: 720).isPlausible(width: 1920, height: 1440))
    XCTAssertFalse(
      Intrinsics(fx: 1451, fy: 1451, cx: 5000, cy: 720).isPlausible(width: 1920, height: 1440))
    XCTAssertFalse(
      Intrinsics(fx: 1451, fy: 1451, cx: 960, cy: -1).isPlausible(width: 1920, height: 1440))
  }

  func testIntrinsicsRejectWrongLength() {
    XCTAssertNil(Intrinsics(elements: [1, 2, 3]))
    XCTAssertNotNil(Intrinsics(elements: [1, 0, 2, 0, 1, 3, 0, 0, 1]))
  }

  // MARK: - Marker ids

  func testMarkerIDValidation() {
    XCTAssertTrue(MarkerID.isValid("CD-000"))
    XCTAssertTrue(MarkerID.isValid("CD-059"))
    XCTAssertFalse(MarkerID.isValid("IG-012"))
    XCTAssertFalse(MarkerID.isValid("CD-12"))
    XCTAssertFalse(MarkerID.isValid("CD-0123"))
    XCTAssertFalse(MarkerID.isValid("cd-012"))
    XCTAssertFalse(MarkerID.isValid("CD-01a"))
    XCTAssertFalse(MarkerID.isValid(""))
  }

  func testMarkerIDFormattingAndParsing() {
    XCTAssertEqual(MarkerID.string(for: 0), "CD-000")
    XCTAssertEqual(MarkerID.string(for: 17), "CD-017")
    XCTAssertEqual(MarkerID.number(in: "CD-017"), 17)
    XCTAssertNil(MarkerID.number(in: "IG-017"))
  }

  func testVector3FiniteCheck() {
    XCTAssertTrue(Vector3(1, 2, 3).isFinite)
    XCTAssertFalse(Vector3(1, .nan, 3).isFinite)
    XCTAssertFalse(Vector3(1, 2, .infinity).isFinite)
  }
}
