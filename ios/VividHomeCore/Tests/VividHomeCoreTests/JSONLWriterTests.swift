import Foundation
import XCTest

@testable import VividHomeCore

final class JSONLWriterTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vividhome-jsonl-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let directory, FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  private func url(_ name: String = "frames.jsonl") -> URL {
    directory.appendingPathComponent(name)
  }

  private func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }

  private func landmark(_ label: String) -> LandmarkRecord {
    LandmarkRecord(
      time: 1.5, index: 2, label: label, kind: .corner, position: Vector3(1.5, 0.5, -2.5),
      method: "raycast-estimatedPlane")
  }

  func testCreatesTheFileAndWritesOneLinePerRecord() throws {
    let target = url()
    let writer = try JSONLWriter(url: target)
    try writer.append(landmark("corner-nw"))
    try writer.append(landmark("corner-ne"))
    try writer.close()

    let text = try contents(of: target)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    // Trailing newline after the last record, so the split yields an empty tail.
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines.last, "")
    XCTAssertTrue(lines[0].contains("corner-nw"))
    XCTAssertTrue(lines[1].contains("corner-ne"))
  }

  func testEveryLineIsIndependentlyDecodable() throws {
    let target = url()
    let writer = try JSONLWriter(url: target)
    try writer.append(contentsOf: (0..<5).map { landmark("corner-\($0)") })
    try writer.close()

    let lines = try contents(of: target)
      .split(separator: "\n", omittingEmptySubsequences: true)
    XCTAssertEqual(lines.count, 5)
    for (index, line) in lines.enumerated() {
      let decoded = try JSONDecoder().decode(LandmarkRecord.self, from: Data(line.utf8))
      XCTAssertEqual(decoded.label, "corner-\(index)")
    }
  }

  func testAppendsToAnExistingFileRatherThanTruncatingIt() throws {
    let target = url()
    let first = try JSONLWriter(url: target)
    try first.append(landmark("corner-nw"))
    try first.close()

    let second = try JSONLWriter(url: target)
    try second.append(landmark("corner-se"))
    try second.close()

    let lines = try contents(of: target).split(separator: "\n", omittingEmptySubsequences: true)
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[0].contains("corner-nw"))
    XCTAssertTrue(lines[1].contains("corner-se"))
  }

  func testSlashesInPathsAreNotEscaped() throws {
    let target = url("frames-paths.jsonl")
    let writer = try JSONLWriter(url: target)
    try writer.append(
      FrameRecord(
        index: 123, time: 1.5, poseWorldFromCamera: .identity,
        intrinsics: Intrinsics(fx: 1451.5, fy: 1451.5, cx: 960.5, cy: 720.5),
        width: 1920, height: 1440, depthWidth: 256, depthHeight: 192,
        exposureDuration: 0.0078125, exposureOffset: 0.5, tracking: .normal, reason: .none,
        thermal: .nominal, rgb: "rgb/000123.jpg", depth: "depth/000123.f32",
        conf: "conf/000123.u8"))
    try writer.close()

    let text = try contents(of: target)
    XCTAssertTrue(text.contains("rgb/000123.jpg"))
    XCTAssertFalse(text.contains("rgb\\/000123.jpg"))
  }

  func testKeysAreSortedSoRunsAreReproducible() throws {
    let target = url("landmarks.jsonl")
    let writer = try JSONLWriter(url: target)
    try writer.append(landmark("corner-nw"))
    try writer.close()

    let line = try contents(of: target).trimmingCharacters(in: .newlines)
    XCTAssertTrue(line.hasPrefix(#"{"i":"#), "sorted keys put i first, got: \(line)")
  }

  func testRecordsSurviveWithoutAnExplicitClose() throws {
    // A session that dies mid-capture must leave readable lines behind.
    let target = url()
    do {
      let writer = try JSONLWriter(url: target)
      try writer.append(landmark("corner-nw"))
      try writer.synchronize()
    }
    let lines = try contents(of: target).split(separator: "\n", omittingEmptySubsequences: true)
    XCTAssertEqual(lines.count, 1)
  }

  func testCloseIsIdempotent() throws {
    let writer = try JSONLWriter(url: url())
    try writer.append(landmark("corner-nw"))
    try writer.close()
    XCTAssertNoThrow(try writer.close())
  }

  func testOpeningInAMissingDirectoryThrows() {
    let bad = directory.appendingPathComponent("no-such-dir/frames.jsonl")
    XCTAssertThrowsError(try JSONLWriter(url: bad))
  }
}
