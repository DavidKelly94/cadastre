import Foundation
import XCTest

@testable import VividHomeCore

/// Projects on the phone (ADR-0033): made by naming, renamed without moving
/// anything, and removed whole.
final class ProjectCatalogTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("projects-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
  }

  /// A capture is a folder with a manifest in it; a plan is a JSON under plans/.
  private func addCapture(_ id: String, to slug: String) throws {
    let folder = root.appendingPathComponent(slug).appendingPathComponent(id)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("manifest.json"))
  }

  private func addPlan(_ level: String, to slug: String) throws {
    let folder = root.appendingPathComponent(slug).appendingPathComponent("plans")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("\(level).json"))
    try Data().write(to: folder.appendingPathComponent("\(level).png"))
  }

  func testAProjectIsMadeByNamingIt() throws {
    XCTAssertEqual(ProjectCatalog.list(in: root), [])
    let made = try ProjectCatalog.create(
      name: "  Rehearsal at Home ", in: root, at: Date(timeIntervalSince1970: 1_793_733_302))
    XCTAssertEqual(made.slug, "rehearsal-at-home")
    XCTAssertEqual(made.name, "Rehearsal at Home")
    XCTAssertEqual(made.captures, [])
    XCTAssertEqual(made.ref, SlugRef(slug: "rehearsal-at-home", name: "Rehearsal at Home"))

    let file = root.appendingPathComponent("rehearsal-at-home/project.json")
    let info = try JSONDecoder().decode(ProjectCatalog.Info.self, from: Data(contentsOf: file))
    XCTAssertEqual(info.name, "Rehearsal at Home")
    XCTAssertNotNil(info.createdAt)

    XCTAssertThrowsError(try ProjectCatalog.create(name: "rehearsal at home", in: root)) {
      XCTAssertEqual($0 as? ProjectCatalog.Failure, .exists("rehearsal-at-home"))
    }
    XCTAssertThrowsError(try ProjectCatalog.create(name: "!!!", in: root)) {
      XCTAssertEqual($0 as? ProjectCatalog.Failure, .unusableName)
    }
  }

  func testTheListCountsWhatEachProjectHolds() throws {
    try ProjectCatalog.create(name: "Our House", in: root)
    try ProjectCatalog.create(name: "Rehearsal", in: root)
    try addCapture("20261113-104450_level-2_room_aaaaaa", to: "our-house")
    try addCapture("20261114-090000_main_kitchen_bbbbbb", to: "our-house")
    try addPlan("main-floor", to: "our-house")
    // Things that are not projects: a stray file, a hidden folder.
    try Data().write(to: root.appendingPathComponent("notes.txt"))
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".Trash"), withIntermediateDirectories: true)

    let list = ProjectCatalog.list(in: root)
    XCTAssertEqual(list.map(\.slug), ["our-house", "rehearsal"])
    XCTAssertEqual(
      list[0].captures,
      ["20261114-090000_main_kitchen_bbbbbb", "20261113-104450_level-2_room_aaaaaa"], "newest first")
    XCTAssertEqual(list[0].plans, 1, "the plan, not its raster")
    XCTAssertEqual(list[1].captures, [])
  }

  func testAFolderFromBeforeProjectsReadsUnderItsSlug() throws {
    try addCapture("20261113-104450_level-2_room_aaaaaa", to: "our-house")
    let found = try XCTUnwrap(ProjectCatalog.project("our-house", in: root))
    XCTAssertEqual(found.name, "Our House")
    XCTAssertEqual(found.captures.count, 1)
    XCTAssertNil(ProjectCatalog.project("elsewhere", in: root))
    XCTAssertNil(ProjectCatalog.project("../sessions", in: root))
  }

  func testRenamingChangesTheNameAndNothingElse() throws {
    try ProjectCatalog.create(name: "Rehearsal", in: root)
    try addCapture("20261113-104450_level-2_room_aaaaaa", to: "rehearsal")
    try ProjectCatalog.rename("rehearsal", to: "Practice run", in: root)
    let renamed = try XCTUnwrap(ProjectCatalog.project("rehearsal", in: root))
    XCTAssertEqual(renamed.name, "Practice run")
    XCTAssertEqual(renamed.slug, "rehearsal", "the folder, the manifests and the PC all keep the slug")
    XCTAssertEqual(renamed.captures.count, 1)
    XCTAssertThrowsError(try ProjectCatalog.rename("rehearsal", to: "  ", in: root))
    XCTAssertThrowsError(try ProjectCatalog.rename("nowhere", to: "x", in: root)) {
      XCTAssertEqual($0 as? ProjectCatalog.Failure, .missing("nowhere"))
    }
  }

  func testDeletingRemovesTheProjectWholeAndSaysWhatThePCDoesNotHold() throws {
    try ProjectCatalog.create(name: "Rehearsal", in: root)
    try ProjectCatalog.create(name: "Our House", in: root)
    try addCapture("20261113-104450_level-2_room_aaaaaa", to: "rehearsal")
    try addCapture("20261113-120000_level-2_room_bbbbbb", to: "rehearsal")
    try addPlan("level-2", to: "rehearsal")
    let rehearsal = try XCTUnwrap(ProjectCatalog.project("rehearsal", in: root))

    // The PC has confirmed one of the two.
    XCTAssertEqual(
      ProjectCatalog.unconfirmed(rehearsal, validatedOnPC: ["20261113-104450_level-2_room_aaaaaa"]),
      ["20261113-120000_level-2_room_bbbbbb"])
    XCTAssertEqual(ProjectCatalog.unconfirmed(rehearsal, validatedOnPC: []).count, 2)

    try ProjectCatalog.delete("rehearsal", in: root)
    XCTAssertEqual(ProjectCatalog.list(in: root).map(\.slug), ["our-house"])
    XCTAssertThrowsError(try ProjectCatalog.delete("rehearsal", in: root))
    XCTAssertThrowsError(try ProjectCatalog.delete("..", in: root), "never a path")
  }
}
