import Foundation
import XCTest

@testable import CadastreCore

final class SessionLayoutTests: XCTestCase {
  private let sessionID = SessionID("20261103-141502_main_kitchen_electrical_k3x7qa")!

  func testPathsMatchTheDocumentedLayout() {
    let layout = SessionLayout(root: URL(fileURLWithPath: "/tmp/s"))
    XCTAssertEqual(layout.manifest.lastPathComponent, "manifest.json")
    XCTAssertEqual(layout.frames.lastPathComponent, "frames.jsonl")
    XCTAssertEqual(layout.stills.lastPathComponent, "stills.jsonl")
    XCTAssertEqual(layout.markers.lastPathComponent, "markers.jsonl")
    XCTAssertEqual(layout.landmarks.lastPathComponent, "landmarks.jsonl")
    XCTAssertEqual(layout.log.lastPathComponent, "log.txt")
    XCTAssertEqual(layout.mesh.lastPathComponent, "mesh.obj")
    XCTAssertEqual(layout.meshClasses.lastPathComponent, "mesh_classes.u8")
    XCTAssertEqual(layout.meshSummary.lastPathComponent, "mesh.json")
  }

  func testSessionLivesUnderSessionsProjectID() {
    let layout = SessionLayout(
      documents: URL(fileURLWithPath: "/Documents"), project: "our-house", sessionID: sessionID)
    XCTAssertTrue(
      layout.root.path.hasSuffix(
        "/Documents/sessions/our-house/20261103-141502_main_kitchen_electrical_k3x7qa"),
      layout.root.path)
  }

  func testKeyframeFilesAreZeroPaddedInTheRightDirectories() {
    let layout = SessionLayout(root: URL(fileURLWithPath: "/tmp/s"))
    XCTAssertEqual(layout.rgb(keyframe: 123).lastPathComponent, "000123.jpg")
    XCTAssertEqual(layout.depth(keyframe: 123).lastPathComponent, "000123.f32")
    XCTAssertEqual(layout.confidence(keyframe: 123).lastPathComponent, "000123.u8")
    XCTAssertEqual(layout.rgb(keyframe: 0).deletingLastPathComponent().lastPathComponent, "rgb")
    XCTAssertEqual(layout.depth(keyframe: 0).deletingLastPathComponent().lastPathComponent, "depth")
    XCTAssertEqual(
      layout.confidence(keyframe: 0).deletingLastPathComponent().lastPathComponent, "conf")
    XCTAssertEqual(layout.still(7).lastPathComponent, "007.jpg")
    XCTAssertEqual(layout.still(7).deletingLastPathComponent().lastPathComponent, "stills")
  }

  func testTheRelativePathsInARecordResolveAgainstTheRoot() {
    // A FrameRecord stores rgb/000123.jpg; the layout must produce the same file.
    let layout = SessionLayout(root: URL(fileURLWithPath: "/tmp/s"))
    let paths = FrameRecord.paths(forKeyframe: 123)
    XCTAssertEqual(
      layout.root.appendingPathComponent(paths.rgb).standardizedFileURL,
      layout.rgb(keyframe: 123).standardizedFileURL)
    XCTAssertEqual(
      layout.root.appendingPathComponent(paths.depth).standardizedFileURL,
      layout.depth(keyframe: 123).standardizedFileURL)
    XCTAssertEqual(
      layout.root.appendingPathComponent(paths.conf).standardizedFileURL,
      layout.confidence(keyframe: 123).standardizedFileURL)
  }

  func testCreateDirectoriesMakesEverythingButDerived() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("cadastre-layout-\(UUID().uuidString)", isDirectory: true)
    let layout = SessionLayout(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    try layout.createDirectories()
    for directory in layout.requiredDirectories {
      var isDirectory: ObjCBool = false
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
        directory.lastPathComponent)
      XCTAssertTrue(isDirectory.boolValue)
    }
    // derived/ belongs to the pipeline; the app must not create it.
    XCTAssertFalse(FileManager.default.fileExists(atPath: layout.derived.path))
  }

  func testCreateDirectoriesIsSafeToRepeat() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("cadastre-layout-\(UUID().uuidString)", isDirectory: true)
    let layout = SessionLayout(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    try layout.createDirectories()
    XCTAssertNoThrow(try layout.createDirectories())
  }
}
