import Foundation
import XCTest

@testable import CadastreCore

final class SessionIDTests: XCTestCase {
  /// The worked example from docs/session-format.md §1.
  private let example = "20261103-141502_main_kitchen_k3x7qa"

  func testParsesTheDocumentedExample() {
    let id = SessionID(example)
    XCTAssertNotNil(id)
    XCTAssertEqual(id?.timestamp, "20261103-141502")
    XCTAssertEqual(id?.level, "main")
    XCTAssertEqual(id?.room, "kitchen")
    XCTAssertEqual(id?.id6, "k3x7qa")
  }

  func testRoundTripsThroughStringValue() {
    XCTAssertEqual(SessionID(example)?.stringValue, example)
  }

  func testRejectsMalformedIdentifiers() {
    let bad = [
      "",
      "20261103-141502_main_kitchen",  // too few parts
      "20261103-141502_main_kitchen_k3x7qa_extra",  // too many
      // A version 1 id, which carried the phase. It has five parts, so it is
      // rejected as malformed rather than silently read as a version 2 id with
      // a room called "kitchen" and a phase where the id6 should be.
      "20261103-141502_main_kitchen_electrical_k3x7qa",
      "2026113-141502_main_kitchen_k3x7qa",  // short timestamp
      "20261103141502_main_kitchen_k3x7qa",  // missing hyphen
      "20261103-141502_Main_kitchen_k3x7qa",  // uppercase slug
      "20261103-141502_main_kitchen_k3x7q",  // id6 too short
      "20261103-141502_main_kitchen_k3x7q1",  // 1 is not in a-z2-7
      "20261103-141502__kitchen_k3x7qa",  // empty slug
    ]
    for raw in bad {
      XCTAssertNil(SessionID(raw), "should reject \(raw)")
    }
  }

  func testSlugifiesTypedNames() {
    XCTAssertEqual(SessionID.slug("Main Floor"), "main-floor")
    XCTAssertEqual(SessionID.slug("Kitchen"), "kitchen")
    XCTAssertEqual(SessionID.slug("  Guest   Bath  "), "guest-bath")
    XCTAssertEqual(SessionID.slug("Bed/Bath #2"), "bed-bath-2")
    XCTAssertEqual(SessionID.slug("---Attic---"), "attic")
  }

  func testSlugRejectsNamesThatLeaveNothing() {
    XCTAssertNil(SessionID.slug(""))
    XCTAssertNil(SessionID.slug("!!!"))
    XCTAssertNil(SessionID.slug("   "))
  }

  func testSlugTruncatesToTwentyFourCharactersWithoutTrailingHyphen() {
    let slug = SessionID.slug("Extraordinarily Long Room Name That Keeps Going")
    XCTAssertNotNil(slug)
    XCTAssertLessThanOrEqual(slug!.count, SessionID.maxSlugLength)
    XCTAssertFalse(slug!.hasSuffix("-"))
    XCTAssertTrue(SessionID.isValidSlug(slug!))
  }

  func testBuildsFromTypedNamesAtAFixedDate() {
    // 2026-11-03T14:15:02Z, formatted in UTC so the expectation is stable.
    let date = Date(timeIntervalSince1970: 1_793_715_302)
    let id = SessionID(
      date: date,
      timeZone: TimeZone(identifier: "UTC")!,
      levelName: "Main Floor",
      roomName: "Kitchen",
      id6: "k3x7qa")
    XCTAssertEqual(id?.stringValue, "20261103-141502_main-floor_kitchen_k3x7qa")
  }

  func testBuildFailsWhenANameSlugifiesToNothing() {
    XCTAssertNil(
      SessionID(
        date: Date(), levelName: "!!!", roomName: "Kitchen", id6: "k3x7qa"))
  }

  func testGeneratedID6IsAlwaysValid() {
    for _ in 0..<200 {
      let id6 = SessionID.makeID6()
      XCTAssertTrue(SessionID.isValidID6(id6), "generated invalid id6: \(id6)")
    }
  }

  func testGeneratedID6UsesOnlyTheBaseThirtyTwoAlphabet() {
    // The alphabet is a-z plus 2-7, so 0, 1, 8 and 9 are the excluded digits.
    XCTAssertEqual(SessionID.id6Alphabet.count, 32)
    for included in Array("234567") {
      XCTAssertTrue(SessionID.id6Alphabet.contains(included))
    }
    for excluded in Array("0189") {
      XCTAssertFalse(SessionID.id6Alphabet.contains(excluded))
    }
  }

  /// A room slug that happens to read like a phase is still a room slug.
  ///
  /// Worth pinning: under version 1 the fourth segment was the phase, so an id
  /// like this one used to mean something else entirely. Now there is no phase
  /// segment and "electrical" here is simply a room called electrical.
  func testAPhaseNameIsNoLongerSpecialInAnID() {
    let id = SessionID("20261103-141502_main_electrical_k3x7qa")
    XCTAssertEqual(id?.room, "electrical")
    XCTAssertEqual(id?.id6, "k3x7qa")
  }
}
