import Foundation
import XCTest

@testable import VividHomeCore

/// The conversion that was missing when the app shipped: `ARFrame.timestamp` is
/// time since boot, and the format's `t` is time since session start.
final class SessionTimelineTests: XCTestCase {

  /// A real value from the capture that exposed this: a phone up for about
  /// 31 hours, in a session lasting well under a minute.
  private let boot = 113_885.284590708

  func testTheFirstFrameBecomesZero() {
    var timeline = SessionTimeline()
    XCTAssertEqual(timeline.adopt(boot), 0, accuracy: 1e-9)
    XCTAssertEqual(timeline.origin, boot)
  }

  func testLaterFramesAreSecondsSinceThatFrame() {
    var timeline = SessionTimeline()
    _ = timeline.adopt(boot)
    XCTAssertEqual(timeline.adopt(boot + 3.4), 3.4, accuracy: 1e-9)
    XCTAssertEqual(timeline.adopt(boot + 41.25), 41.25, accuracy: 1e-9)
  }

  func testTheOriginIsAdoptedOnceAndNeverMoves() {
    var timeline = SessionTimeline()
    _ = timeline.adopt(boot)
    _ = timeline.adopt(boot + 10)
    XCTAssertEqual(timeline.origin, boot, "a later frame must not become the new zero")
    XCTAssertEqual(timeline.adopt(boot + 20), 20, accuracy: 1e-9)
  }

  func testAbsoluteTimestampsWouldFailValidationRule2() {
    // The bug, stated as the rule it broke: t must be within [0, duration + 1].
    var timeline = SessionTimeline()
    _ = timeline.adopt(boot)
    let duration = 41.0
    let converted = timeline.time(for: boot + duration)
    XCTAssertLessThanOrEqual(converted, duration + 1)
    XCTAssertGreaterThan(boot, duration + 1, "the raw timestamp is what failed")
  }

  func testStillsAndLandmarksShareTheKeyframeOrigin() {
    // Every t in a session must be measured from one zero, or a still lands in
    // the trajectory at the wrong moment.
    var timeline = SessionTimeline()
    _ = timeline.adopt(boot)
    XCTAssertEqual(timeline.time(for: boot + 7.5), 7.5, accuracy: 1e-9)
  }

  func testTimeForDoesNotAdoptAnOrigin() {
    // The session starts when recording starts, not when the owner first taps.
    var timeline = SessionTimeline()
    XCTAssertEqual(timeline.time(for: boot), 0)
    XCTAssertFalse(timeline.hasBegun)
    XCTAssertNil(timeline.origin)

    _ = timeline.adopt(boot + 100)
    XCTAssertEqual(timeline.origin, boot + 100)
  }

  func testAnEventBeforeTheFirstKeyframeClampsToZero() {
    // A still can be taken before the first keyframe — the format gives it
    // index -1 — and a negative t would fail rule 2 for something legal.
    var timeline = SessionTimeline()
    _ = timeline.adopt(boot)
    XCTAssertEqual(timeline.time(for: boot - 0.4), 0, accuracy: 1e-12)
  }

  func testBeforeAnyFrameEverythingIsZero() {
    let timeline = SessionTimeline()
    XCTAssertFalse(timeline.hasBegun)
    XCTAssertEqual(timeline.time(for: boot), 0)
  }
}
