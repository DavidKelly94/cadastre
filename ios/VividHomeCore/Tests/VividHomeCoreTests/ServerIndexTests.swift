import Foundation
import XCTest

@testable import VividHomeCore

/// Section 14 of the format is the one contract the app reads from the PC, so
/// the example in the document is what the reader is checked against.
final class ServerIndexTests: XCTestCase {
  private let example = """
    {
      "vividhome": "0.1.0",
      "generated_at": "2026-09-30T18:04:11Z",
      "store": "vividhome-data",
      "projects": [
        {
          "slug": "our-house",
          "levels": [
            { "level": "main", "plan": "plans/main.png", "calibrated": true,
              "inspect": "inspect/main.html",
              "sessions": ["20261103-141502_main_kitchen_k3x7qa"] },
            { "level": "upper", "plan": "plans/upper.png", "calibrated": false,
              "inspect": null, "sessions": [] }
          ],
          "sessions": [
            { "session_id": "20261103-141502_main_kitchen_k3x7qa",
              "path": "sessions/our-house/20261103-141502_main_kitchen_k3x7qa",
              "level": "main", "aligned": true, "validated": true },
            { "session_id": "20261104-090000_upper_hall_bbbbbb",
              "path": "sessions/our-house/20261104-090000_upper_hall_bbbbbb",
              "level": "upper", "aligned": false, "validated": null,
              "something_newer": 1 }
          ]
        }
      ],
      "note": "readers ignore this"
    }
    """

  func testTheDocumentedExampleDecodes() throws {
    let index = try JSONDecoder().decode(ServerIndex.self, from: Data(example.utf8))
    XCTAssertEqual(index.vividhome, "0.1.0")
    XCTAssertEqual(index.store, "vividhome-data")
    XCTAssertEqual(index.projects.count, 1)
    XCTAssertEqual(index.sessionCount, 2)
    XCTAssertEqual(index.renderedLevelCount, 1)

    let project = try XCTUnwrap(index.project("our-house"))
    XCTAssertEqual(project.levels.map(\.level), ["main", "upper"])
    XCTAssertEqual(project.levels[0].inspect, "inspect/main.html")
    XCTAssertNil(project.levels[1].inspect)
    XCTAssertEqual(project.sessions[0].validated, true)
    XCTAssertNil(project.sessions[1].validated, "null means no report, not false")
    XCTAssertFalse(project.sessions[1].aligned)
    XCTAssertNil(index.project("cabin"))
  }

  func testThePageForALevelIsFoundOrAbsent() throws {
    let index = try JSONDecoder().decode(ServerIndex.self, from: Data(example.utf8))
    XCTAssertEqual(index.inspectPage(project: "our-house", level: "main"), "inspect/main.html")
    XCTAssertNil(index.inspectPage(project: "our-house", level: "upper"))
    XCTAssertNil(index.inspectPage(project: "cabin", level: "main"))
  }

  func testTheAgeComesFromGeneratedAt() throws {
    let index = try JSONDecoder().decode(ServerIndex.self, from: Data(example.utf8))
    let generated = try XCTUnwrap(index.generated)
    XCTAssertEqual(index.age(now: generated.addingTimeInterval(90)), 90)
    var stale = index
    stale.generatedAt = "sometime"
    XCTAssertNil(stale.age(now: Date()))
  }

  func testTypedAddressesBecomeBaseURLs() {
    XCTAssertEqual(PCAddress.url(from: "192.168.1.20")?.absoluteString, "http://192.168.1.20:8765")
    XCTAssertEqual(PCAddress.url(from: " 192.168.1.20:9000 ")?.absoluteString, "http://192.168.1.20:9000")
    XCTAssertEqual(PCAddress.url(from: "pc.local")?.absoluteString, "http://pc.local:8765")
    XCTAssertEqual(
      PCAddress.url(from: "http://pc.local:8765/inspect/main.html")?.absoluteString,
      "http://pc.local:8765", "a pasted page path is dropped")
    XCTAssertEqual(
      PCAddress.url(from: "https://pc.example")?.absoluteString, "https://pc.example",
      "https with no port is a tailnet name on 443, not the pipeline's 8765")
    XCTAssertEqual(
      PCAddress.url(from: "https://pc.tail1234.ts.net/inspect/main.html")?.absoluteString,
      "https://pc.tail1234.ts.net")
    XCTAssertEqual(
      PCAddress.url(from: "https://pc.example:8443")?.absoluteString, "https://pc.example:8443")
    XCTAssertNil(PCAddress.url(from: ""))
    XCTAssertNil(PCAddress.url(from: "   "))
    XCTAssertNil(PCAddress.url(from: "ftp://pc.local"))
    XCTAssertNil(PCAddress.url(from: "http://"))
  }

  func testThePCsWordOnASessionIsValidatedHeldOrAbsent() throws {
    let index = try JSONDecoder().decode(ServerIndex.self, from: Data(example.utf8))
    XCTAssertEqual(index.holding(of: "20261103-141502_main_kitchen_k3x7qa"), .validated)
    XCTAssertEqual(
      index.holding(of: "20261104-090000_upper_hall_bbbbbb"), .held,
      "ingested but never validated is not safe to delete")
    XCTAssertEqual(index.holding(of: "20261105-000000_main_x_cccccc"), .absent)
    XCTAssertEqual(index.validatedSessionIDs, ["20261103-141502_main_kitchen_k3x7qa"])

    var failed = index
    failed.projects[0].sessions[0].validated = false
    XCTAssertEqual(failed.holding(of: "20261103-141502_main_kitchen_k3x7qa"), .held)
    XCTAssertEqual(failed.validatedSessionIDs, [])
  }
}
