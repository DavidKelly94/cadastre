import XCTest

@testable import VividHomeCore

/// Undo on the outline screen (build 78: "undo keeps removing corners").
final class EditHistoryTests: XCTestCase {
  func testUndoPutsBackWhatWasThereBeforeEachChange() {
    var history = EditHistory<[Int]>()
    var corners = [1, 2, 3, 4]
    XCTAssertFalse(history.canUndo(from: corners), "nothing done yet")

    // Drag the second corner: the count does not change, the undo still works.
    history.record(corners)
    corners[1] = 20
    // Add a fifth.
    history.record(corners)
    corners.append(5)

    XCTAssertTrue(history.canUndo(from: corners))
    corners = history.undo(from: corners) ?? corners
    XCTAssertEqual(corners, [1, 20, 3, 4])
    corners = history.undo(from: corners) ?? corners
    XCTAssertEqual(corners, [1, 2, 3, 4], "back to what the screen opened with")
    XCTAssertFalse(history.canUndo(from: corners))
    XCTAssertNil(history.undo(from: corners), "and no further: the corners that were there stay")
  }

  func testATouchThatChangesNothingIsNotAStep() {
    var history = EditHistory<[Int]>()
    var corners = [1, 2, 3]
    history.record(corners)
    corners.append(4)
    // Two taps on a corner without moving it.
    history.record(corners)
    history.record(corners)
    XCTAssertEqual(history.undo(from: corners), [1, 2, 3])
  }

  func testClearingCanBeUndone() {
    var history = EditHistory<[Int]>()
    var corners = [1, 2, 3]
    history.record(corners)
    corners = []
    XCTAssertEqual(history.undo(from: corners), [1, 2, 3])
  }

  func testTheHistoryIsBounded() {
    var history = EditHistory<Int>()
    for value in 0..<(EditHistory<Int>.limit + 50) { history.record(value) }
    var steps = 0
    var current = -1
    while let previous = history.undo(from: current) {
      current = previous
      steps += 1
    }
    XCTAssertEqual(steps, EditHistory<Int>.limit)
  }
}
