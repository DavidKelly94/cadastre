import Foundation
import XCTest

@testable import VividHomeCore

/// The phone's fit is read by the PC as its own, so every number here is the
/// one `umeyama_2d` and `embed_se2` produced for the same points.
final class PlanAlignmentTests: XCTestCase {
  // A 4 x 3 m room, corners NW, NE, SE, SW in house metres (north is -z), and
  // where the phone saw them: rotated 25°, shifted, with a few centimetres of
  // tap noise.
  private let session: [(x: Double, z: Double)] = [
    (-2.386007, -1.651842), (1.199224, -3.282315), (2.497079, -0.593392), (-1.178153, 1.067081),
  ]
  private let house: [(x: Double, z: Double)] = [(0, -3), (4, -3), (4, 0), (0, 0)]
  private let labels = ["corner-nw", "corner-ne", "corner-se", "corner-sw"]

  private var pairs: [PlanAlignment.Pair] {
    zip(zip(labels, session), house).map { PlanAlignment.Pair(label: $0.0, sessionXZ: $0.1, houseXZ: $1) }
  }

  func testTheFitMatchesThePipeline() {
    let fit = Umeyama2D.fit(from: session, to: house)
    XCTAssertEqual(fit.c, 0.909564405031, accuracy: 1e-9)
    XCTAssertEqual(fit.s, 0.415562983313, accuracy: 1e-9)
    XCTAssertEqual(fit.tx, 1.506550510444, accuracy: 1e-9)
    XCTAssertEqual(fit.tz, -0.499457704181, accuracy: 1e-9)
    XCTAssertEqual(fit.rms, 0.028493743914, accuracy: 1e-9)
  }

  func testTwoPointsFitToo() {
    let fit = Umeyama2D.fit(from: Array(session.prefix(2)), to: Array(house.prefix(2)))
    XCTAssertEqual(fit.c, 0.910287786994, accuracy: 1e-9)
    XCTAssertEqual(fit.s, 0.413976019655, accuracy: 1e-9)
    XCTAssertEqual(fit.tx, 1.51884569775, accuracy: 1e-9)
    XCTAssertEqual(fit.tz, -0.508598720627, accuracy: 1e-9)
    XCTAssertEqual(fit.rms, 0.030715642226, accuracy: 1e-9)
  }

  func testTheSolutionIsTheFileThePipelineWrites() throws {
    let solution = try XCTUnwrap(
      PlanAlignment.solve(pairs: pairs, floorY: -0.25, floorSource: "lowest-landmark", floorHeight: 0))
    let expected: [Double] = [
      0.909564405031, 0, 0.415562983313, 0, 0, 1, 0, 0, -0.415562983313, 0, 0.909564405031, 0,
      1.506550510444, 0.25, -0.499457704181, 1,
    ]
    for (got, want) in zip(solution.tHs, expected) {
      XCTAssertEqual(got, want, accuracy: 1e-9)
    }
    XCTAssertEqual(solution.yawDegrees, -24.554775226, accuracy: 1e-6)
    XCTAssertEqual(solution.rms, 0.028493743914, accuracy: 1e-9)
    XCTAssertEqual(solution.maxResidual, 0.040931403561, accuracy: 1e-9)
    XCTAssertEqual(solution.residuals[1], 0.040931403561, accuracy: 1e-9)
    XCTAssertEqual(solution.verdict, .placed)
    XCTAssertEqual(solution.summary, "Placed on the plan, 3 cm")
    // The transform applied to a session point lands on its house point.
    let moved = solution.houseXZ(sessionX: session[2].x, z: session[2].z)
    XCTAssertEqual(moved.x, 4, accuracy: 0.03)
    XCTAssertEqual(moved.z, 0, accuracy: 0.03)
  }

  func testVerdictsFollowTheDesignsThresholds() throws {
    // Corners swapped: NW tapped where NE is, so the fit cannot be good.
    var swapped = pairs
    swapped[0].houseXZ = house[1]
    swapped[1].houseXZ = house[0]
    let bad = try XCTUnwrap(PlanAlignment.solve(pairs: swapped, floorY: 0, floorSource: "assumed-zero", floorHeight: 0))
    XCTAssertEqual(bad.verdict, .notPlaced)
    XCTAssertTrue(bad.summary.hasPrefix("Not placed"))
    XCTAssertNil(PlanAlignment.solve(pairs: [pairs[0]], floorY: 0, floorSource: "x", floorHeight: 0))
  }

  func testTheFloorIsTheFloorLandmarksElseTheLowestOne() {
    let tagged = PlanAlignment.floorY(landmarks: [(.corner, -1.2), (.floor, -1.31), (.floor, -1.29), (.door, -1.25)])
    XCTAssertEqual(tagged.y, -1.30, accuracy: 1e-12)
    XCTAssertEqual(tagged.source, "floor-landmarks")
    let lowest = PlanAlignment.floorY(landmarks: [(.corner, -1.2), (.corner, -1.33)])
    XCTAssertEqual(lowest.y, -1.33)
    XCTAssertEqual(lowest.source, "lowest-landmark")
    XCTAssertEqual(PlanAlignment.floorY(landmarks: []).source, "assumed-zero")
  }

  func testTheFileCarriesThePipelinesKeysAndSaysItIsTheApps() throws {
    let solution = try XCTUnwrap(
      PlanAlignment.solve(pairs: pairs, floorY: -0.25, floorSource: "lowest-landmark", floorHeight: 0))
    let file = AlignmentFile(
      sessionID: "20261103-141502_main_kitchen_k3x7qa", level: "main", solution: solution,
      at: Date(timeIntervalSince1970: 1_793_733_302))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(file), as: UTF8.self)
    for key in [
      "\"session_id\"", "\"level\"", "\"T_hs\"", "\"pairs\"", "\"session_xz\"", "\"house_xz\"",
      "\"rms_m\":0.028494", "\"max_residual_m\":0.040931", "\"method\":\"guided\"",
      "\"floor_source\":\"lowest-landmark\"", "\"created_at\":\"2026-11-03T19:15:02Z\"",
      "\"source\":\"app\"", "\"source\":\"landmark\"",
    ] {
      XCTAssertTrue(json.contains(key), "missing \(key) in \(json)")
    }
    let back = try JSONDecoder().decode(AlignmentFile.self, from: Data(json.utf8))
    XCTAssertEqual(back, file)
    XCTAssertEqual(back.tHs.count, 16)
    XCTAssertEqual(back.pairs.count, 4)
  }

  func testTheFileIsWrittenBesidePlans() throws {
    let project = FileManager.default.temporaryDirectory
      .appendingPathComponent("vividhome-align-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: project) }
    let solution = try XCTUnwrap(
      PlanAlignment.solve(pairs: pairs, floorY: 0, floorSource: "assumed-zero", floorHeight: 0))
    let file = AlignmentFile(sessionID: "20261103-141502_main_kitchen_k3x7qa", level: "main", solution: solution)
    let url = AlignmentFile.url(projectDirectory: project, sessionID: file.sessionID)
    XCTAssertEqual(url.lastPathComponent, "20261103-141502_main_kitchen_k3x7qa.json")
    XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "alignments")
    try file.write(to: url)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }
}
