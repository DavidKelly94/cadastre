import Foundation
import XCTest

@testable import VividHomeCore

/// The protocol's stills table as data, and the leave check built from it,
/// the placement and the walls' coverage.
final class StillsChecklistTests: XCTestCase {
  func testAPhaseListsTheCommonItemsThenItsOwn() {
    let electrical = StillsChecklist.items(for: [.electrical]).map(\.id)
    XCTAssertEqual(
      electrical,
      ["wall", "boxes", "panel", "home-runs", "nail-plates", "low-voltage", "smoke-co", "exterior-penetrations"])
    XCTAssertEqual(StillsChecklist.items(for: [.other]).map(\.id), ["wall"])
  }

  func testAPassWithTwoTradesListsEachItemOnceInTradeOrder() {
    let items = StillsChecklist.items(for: [.electrical, .plumbing]).map(\.id)
    XCTAssertEqual(items.count, 1 + 7 + 8)
    XCTAssertEqual(Set(items).count, items.count)
    XCTAssertEqual(items[1], "boxes")
    XCTAssertEqual(items[8], "supply")
  }

  func testIdsAreUniqueAcrossEveryPhaseAndNamesHaveNoCommas() {
    let all = StillsChecklist.all
    XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    for item in all {
      XCTAssertFalse(item.name.contains(","), item.name)
      XCTAssertEqual(StillsChecklist.name(for: item.id), item.name)
    }
    XCTAssertEqual(StillsChecklist.name(for: "not-an-item"), "not-an-item")
  }

  func testProgressTicksAnItemOnceAndIgnoresStillsWithNoPick() {
    let items = StillsChecklist.items(for: [.electrical])
    let progress = StillsChecklist.progress(items: items, taken: ["panel", nil, "panel", "boxes", "not-an-item"])
    XCTAssertEqual(progress.done, 2)
    XCTAssertEqual(progress.total, 8)
    XCTAssertEqual(
      progress.missing.map(\.id),
      ["wall", "home-runs", "nail-plates", "low-voltage", "smoke-co", "exterior-penetrations"])
    XCTAssertFalse(progress.complete)
    XCTAssertTrue(StillsChecklist.progress(items: items, taken: items.map(\.id)).complete)
  }

  // MARK: - The leave check

  private let room: [(label: String, x: Double, z: Double)] = [
    ("corner-nw", 0, -4), ("corner-ne", 4, -4), ("corner-se", 4, 0), ("corner-sw", 0, 0),
  ]

  private func placed() throws -> PlanAlignment.Solution {
    // An exact fit: a shift by (1, 2), so the verdict is placed at 0 cm.
    let pairs = [
      PlanAlignment.Pair(label: "corner-nw", sessionXZ: (0, 0), houseXZ: (1, 2)),
      PlanAlignment.Pair(label: "corner-ne", sessionXZ: (1, 0), houseXZ: (2, 2)),
      PlanAlignment.Pair(label: "corner-se", sessionXZ: (1, 1), houseXZ: (2, 3)),
    ]
    return try XCTUnwrap(PlanAlignment.solve(pairs: pairs, floorY: 0, floorSource: "x", floorHeight: 0))
  }

  func testAPlacedCaptureWithAGapAndMissingStillsReadsAsTheDesignSays() throws {
    var walls = WallCoverage.walls(outline: room)
    for index in walls.indices { walls[index].photographed = Array(repeating: true, count: walls[index].cells) }
    // The east wall (NE to SE, 4 m): the first metre photographed, the rest not.
    walls[1].photographed = (0..<walls[1].cells).map { $0 < 10 }

    let check = FieldCheck.make(
      guided: true, cornersTapped: 3, placement: try placed(), coverage: walls,
      checklist: StillsChecklist.items(for: [.electrical]),
      taken: ["wall", "boxes", "panel", nil, "home-runs", "nail-plates", "panel"],
      checkedAt: "2026-10-03T18:00:00Z")

    XCTAssertEqual(check.placement, FieldCheck.Placement(status: "placed", rmsM: 0, corners: 3))
    XCTAssertEqual(
      check.walls,
      FieldCheck.Walls(
        photographed: 3, total: 4,
        gaps: [FieldCheck.Walls.Gap(wall: "corner-ne->corner-se", fromM: 1.0, lengthM: 3.0)]))
    XCTAssertEqual(
      check.stills, FieldCheck.Stills(done: 5, total: 8, missing: ["low-voltage", "smoke-co", "exterior-penetrations"]))

    let lines = check.lines
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines[0], FieldCheck.Line(text: "Placed on the plan, 0 cm", ok: true))
    XCTAssertEqual(
      lines[1],
      FieldCheck.Line(
        text: "Walls photographed: 3 of 4; NE–SE wall, 3.0 m not photographed from 1.0 m past NE", ok: false))
    XCTAssertEqual(
      lines[2],
      FieldCheck.Line(
        text: "Stills: 5 of 8 on the list; missing Low-voltage runs, Smoke and CO locations, Exterior penetrations",
        ok: false))
  }

  func testAFreeCaptureIsNotPlacedYetRatherThanFailed() {
    let check = FieldCheck.make(
      guided: false, cornersTapped: 0, placement: nil, coverage: nil, checklist: [], taken: [],
      checkedAt: "2026-10-03T18:00:00Z")
    XCTAssertEqual(check.placement.status, "free")
    XCTAssertNil(check.walls)
    XCTAssertEqual(check.lines[0].text, "Not placed yet: no outline for this room")
    XCTAssertEqual(check.lines[1].text, "Walls photographed: unknown until the capture is placed")
    XCTAssertEqual(check.lines[2], FieldCheck.Line(text: "Stills: no list for these trades", ok: true))
  }

  func testAGuidedCaptureWithOneCornerAsksForTwo() {
    let check = FieldCheck.make(
      guided: true, cornersTapped: 1, placement: nil, coverage: nil,
      checklist: StillsChecklist.items(for: [.framing]), taken: StillsChecklist.items(for: [.framing]).map(\.id),
      checkedAt: "2026-10-03T18:00:00Z")
    XCTAssertEqual(check.placement, FieldCheck.Placement(status: "untapped", rmsM: nil, corners: 1))
    XCTAssertEqual(check.lines[0], FieldCheck.Line(text: "Not placed: tap two corners", ok: false))
    XCTAssertEqual(check.lines[2], FieldCheck.Line(text: "Stills: 10 of 10 on the list", ok: true))
  }

  func testTheFileHasTheDocumentedKeysAndRoundTrips() throws {
    let check = FieldCheck(
      placement: FieldCheck.Placement(status: "check", rmsM: 0.18, corners: 2),
      walls: FieldCheck.Walls(
        photographed: 4, total: 5, gaps: [FieldCheck.Walls.Gap(wall: "corner-nw->corner-ne", fromM: 1.9, lengthM: 0.8)]),
      stills: FieldCheck.Stills(done: 7, total: 11, missing: ["panel", "home-runs", "smoke-co"]),
      checkedAt: "2026-10-03T18:00:00Z")
    let data = try JSONEncoder().encode(check)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(object.keys), ["placement", "walls", "stills", "checked_at"])
    let placement = try XCTUnwrap(object["placement"] as? [String: Any])
    XCTAssertEqual(Set(placement.keys), ["status", "rms_m", "corners"])
    let walls = try XCTUnwrap(object["walls"] as? [String: Any])
    XCTAssertEqual(Set(walls.keys), ["photographed", "total", "gaps"])
    let gap = try XCTUnwrap((walls["gaps"] as? [[String: Any]])?.first)
    XCTAssertEqual(Set(gap.keys), ["wall", "from_m", "length_m"])
    XCTAssertEqual(try JSONDecoder().decode(FieldCheck.self, from: data), check)
    XCTAssertEqual(check.lines[0], FieldCheck.Line(text: "Check the corners: 18 cm off", ok: false))
    XCTAssertEqual(
      check.lines[1].text, "Walls photographed: 4 of 5; NW–NE wall, 0.8 m not photographed from 1.9 m past NW")
  }

  func testAStillNamesItsItemOnlyWhenItHasOne() throws {
    var still = StillRecord(
      stillIndex: 0, index: -1, time: 1.5, poseWorldFromCamera: .identity,
      intrinsics: Intrinsics(elements: [1, 0, 0, 0, 1, 0, 0, 0, 1])!, width: 4032, height: 3024,
      exposureDuration: 0.01, exposureOffset: 0, tracking: .normal, reason: .none, thermal: .nominal,
      path: "stills/000.jpg")
    func keys(_ value: StillRecord) throws -> Set<String> {
      let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(value)) as? [String: Any]
      return Set(object?.keys.map { $0 } ?? [])
    }
    XCTAssertFalse(try keys(still).contains("item"))
    still.item = "panel"
    XCTAssertTrue(try keys(still).contains("item"))
    XCTAssertEqual(try JSONDecoder().decode(StillRecord.self, from: JSONEncoder().encode(still)).item, "panel")
  }

  func testTheManifestCarriesTheCheckOnlyOnceFinalisedWithOne() throws {
    let manifest = Manifest(
      sessionID: "20261103-141502_main_kitchen_k3x7qa", status: .incomplete,
      project: SlugRef(slug: "our-house", name: "Our House"),
      level: LevelRef(slug: "main", name: "Main Floor", index: 1),
      room: SlugRef(slug: "kitchen", name: "Kitchen"), phases: [.electrical],
      device: DeviceInfo(model: "iPhone16,1", iosVersion: "26.6", appVersion: "0.1.0", appBuild: "37"),
      capture: CaptureInfo(
        startedAt: "2026-11-03T14:15:02-05:00", endedAt: nil, duration: 0,
        videoFormat: VideoFormat(w: 1920, h: 1440, fps: 30),
        keyframePolicy: KeyframePolicySettings(minDt: 0.1, minTranslation: 0.1, minRotationDegrees: 5),
        depth: DepthFormat(w: 256, h: 192), jpegQuality: 0.85, markerPhysicalWidth: 0.2,
        sceneReconstruction: "meshWithClassification"))
    func keys(_ value: Manifest) throws -> Set<String> {
      let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(value)) as? [String: Any]
      return Set(object?.keys.map { $0 } ?? [])
    }
    XCTAssertFalse(try keys(manifest).contains("field_check"))
    let plain = manifest.finalized(endedAt: "2026-11-03T14:19:48-05:00", duration: 286, stats: SessionStats())
    XCTAssertFalse(try keys(plain).contains("field_check"), "a capture made before the check has none")
    let check = FieldCheck.make(
      guided: false, cornersTapped: 0, placement: nil, coverage: nil, checklist: [], taken: [],
      checkedAt: "2026-11-03T19:19:48Z")
    let checked = manifest.finalized(
      endedAt: "2026-11-03T14:19:48-05:00", duration: 286, stats: SessionStats(), fieldCheck: check)
    XCTAssertTrue(try keys(checked).contains("field_check"))
    XCTAssertEqual(try JSONDecoder().decode(Manifest.self, from: JSONEncoder().encode(checked)).fieldCheck, check)
  }
}
