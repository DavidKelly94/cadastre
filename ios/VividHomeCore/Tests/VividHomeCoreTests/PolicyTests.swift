import Foundation
import XCTest

@testable import VividHomeCore

final class KeyframePolicyTests: XCTestCase {
  private func pose(x: Double = 0, y: Double = 0, z: Double = 0, yaw: Double = 0) -> Transform {
    let c = cos(yaw)
    let s = sin(yaw)
    return Transform(elements: [
      c, 0, -s, 0,
      0, 1, 0, 0,
      s, 0, c, 0,
      x, y, z, 1,
    ])!
  }

  func testTheFirstFrameIsAlwaysKept() {
    var policy = KeyframePolicy()
    XCTAssertTrue(policy.shouldKeep(time: 0, pose: pose()))
  }

  func testRateCapRejectsFramesArrivingTooSoon() {
    var policy = KeyframePolicy()
    XCTAssertTrue(policy.shouldKeep(time: 0, pose: pose()))
    // Well past the translation gate, but only 0.05 s later.
    XCTAssertFalse(policy.shouldKeep(time: 0.05, pose: pose(x: 5)))
  }

  func testTranslationGateKeepsAFrameOnceTheCapHasElapsed() {
    var policy = KeyframePolicy()
    XCTAssertTrue(policy.shouldKeep(time: 0, pose: pose()))
    XCTAssertFalse(policy.shouldKeep(time: 0.2, pose: pose(x: 0.05)))
    XCTAssertTrue(policy.shouldKeep(time: 0.4, pose: pose(x: 0.10)))
  }

  func testRotationGateAloneIsEnough() {
    // Turning on the spot reveals new geometry without any translation.
    var policy = KeyframePolicy()
    XCTAssertTrue(policy.shouldKeep(time: 0, pose: pose()))
    XCTAssertFalse(policy.shouldKeep(time: 0.2, pose: pose(yaw: 2 * .pi / 180)))
    XCTAssertTrue(policy.shouldKeep(time: 0.4, pose: pose(yaw: 6 * .pi / 180)))
  }

  func testAStationaryPhoneProducesNoFurtherKeyframes() {
    var policy = KeyframePolicy()
    XCTAssertTrue(policy.shouldKeep(time: 0, pose: pose()))
    for step in 1...100 {
      XCTAssertFalse(policy.shouldKeep(time: Double(step) * 0.1, pose: pose()))
    }
  }

  func testGatesAreMeasuredFromTheLastKeptFrameNotTheLastOffered() {
    // Ten 3 cm steps: each is below the gate, but the tenth is 30 cm from the
    // last kept frame and must be kept.
    var policy = KeyframePolicy()
    XCTAssertTrue(policy.shouldKeep(time: 0, pose: pose()))
    var kept = 0
    for step in 1...10 where policy.shouldKeep(time: Double(step) * 0.2, pose: pose(x: Double(step) * 0.03)) {
      kept += 1
    }
    XCTAssertGreaterThan(kept, 0, "drift below the gate must still accumulate")
  }

  func testResetMakesTheNextFrameAKeyframe() {
    var policy = KeyframePolicy()
    XCTAssertTrue(policy.shouldKeep(time: 0, pose: pose()))
    XCTAssertFalse(policy.shouldKeep(time: 0.2, pose: pose()))
    policy.reset()
    XCTAssertTrue(policy.shouldKeep(time: 0.3, pose: pose()))
  }

  func testTheRateCapBoundsTheKeyframeRate() {
    // Section 10: at most ten keyframes a second, however fast the phone moves.
    var policy = KeyframePolicy()
    var kept = 0
    for step in 0..<1000 where policy.shouldKeep(time: Double(step) * 0.001, pose: pose(x: Double(step))) {
      kept += 1
    }
    XCTAssertLessThanOrEqual(kept, 11, "one second at 1 kHz must not exceed the cap")
  }

  func testDocumentedDefaultsMatchTheSpecification() {
    XCTAssertEqual(KeyframePolicy.documentedDefault.minDt, 0.1)
    XCTAssertEqual(KeyframePolicy.documentedDefault.minTranslation, 0.10)
    XCTAssertEqual(KeyframePolicy.documentedDefault.minRotationDegrees, 5.0)
  }
}

final class HealthPolicyTests: XCTestCase {
  func testStartThresholdIsTwoGigabytes() {
    XCTAssertTrue(HealthPolicy.canStart(freeBytes: 2_000_000_000))
    XCTAssertTrue(HealthPolicy.canStart(freeBytes: 8_000_000_000))
    XCTAssertFalse(HealthPolicy.canStart(freeBytes: 1_999_999_999))
  }

  func testStartRefusalExplainsItself() {
    XCTAssertNil(HealthPolicy.startRefusal(freeBytes: 4_000_000_000))
    let refusal = HealthPolicy.startRefusal(freeBytes: 1_000_000_000)
    XCTAssertNotNil(refusal)
    XCTAssertTrue(refusal!.contains("1.0 GB free"))
    XCTAssertTrue(refusal!.contains("2.0 GB needed"))
  }

  func testStopsWhenSpaceRunsOut() {
    guard case .stop = HealthPolicy.verdict(freeBytes: 500_000_000, thermal: .nominal) else {
      return XCTFail("500 MB must stop the session")
    }
    guard case .stop = HealthPolicy.verdict(freeBytes: 10_000_000, thermal: .nominal) else {
      return XCTFail("almost no space must stop the session")
    }
  }

  func testDiskIsCheckedBeforeHeat() {
    // Running out of space corrupts what is being written; heat only degrades
    // the frames still to come. So a full disk reports the disk, not the heat.
    let verdict = HealthPolicy.verdict(freeBytes: 100_000_000, thermal: .critical)
    guard case .stop(let reason) = verdict else { return XCTFail("expected a stop") }
    XCTAssertTrue(reason.contains("space"), "expected the disk reason, got: \(reason)")
  }

  func testThermalStates() {
    guard case .stop = HealthPolicy.verdict(freeBytes: 8_000_000_000, thermal: .critical) else {
      return XCTFail("critical must stop")
    }
    guard case .warn = HealthPolicy.verdict(freeBytes: 8_000_000_000, thermal: .serious) else {
      return XCTFail("serious must warn")
    }
    XCTAssertEqual(HealthPolicy.verdict(freeBytes: 8_000_000_000, thermal: .fair), .ok)
    XCTAssertEqual(HealthPolicy.verdict(freeBytes: 8_000_000_000, thermal: .nominal), .ok)
  }

  func testLowButUsableSpaceWarns() {
    guard case .warn(let reason) = HealthPolicy.verdict(
      freeBytes: 1_500_000_000, thermal: .nominal)
    else {
      return XCTFail("below the start threshold but above the stop threshold must warn")
    }
    XCTAssertTrue(reason.contains("1.5 GB"))
  }
}
