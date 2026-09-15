import Foundation
import XCTest

@testable import VividHomeCore

final class SessionLifecycleTests: XCTestCase {
  private let sessionID = SessionID("20261103-141502_main_kitchen_k3x7qa")!

  private func starting() -> Manifest {
    Manifest.starting(
      sessionID: sessionID,
      project: SlugRef(slug: "our-house", name: "Our House"),
      level: LevelRef(slug: "main", name: "Main Floor", index: 1),
      room: SlugRef(slug: "kitchen", name: "Kitchen"),
      phases: [.electrical, .plumbing],
      expectedMarkers: ["VH-012"],
      device: DeviceInfo(
        model: "iPhone16,1", iosVersion: "26.6", appVersion: "0.1.0", appBuild: "37"),
      startedAt: "2026-11-03T14:15:02-05:00",
      videoFormat: VideoFormat(w: 1920, h: 1440, fps: 30),
      keyframePolicy: KeyframePolicy.documentedDefault,
      depth: DepthFormat(w: 256, h: 192),
      jpegQuality: 0.85,
      markerPhysicalWidth: 0.20,
      sceneReconstruction: "meshWithClassification")
  }

  func testTheStartingManifestSaysIncomplete() {
    let manifest = starting()
    XCTAssertEqual(manifest.status, .incomplete)
    XCTAssertNil(manifest.capture.endedAt)
    XCTAssertEqual(manifest.capture.duration, 0)
    XCTAssertEqual(manifest.stats.keyframes, 0)
    // Phases are carried on the manifest, not the id, and a pass can expose
    // more than one trade at a time (ADR-0022).
    XCTAssertEqual(manifest.phases, [.electrical, .plumbing])
    XCTAssertEqual(manifest.formatVersion, 3)
  }

  func testFinalizingFillsInWhatIsKnownAtTheStop() {
    var stats = SessionStats()
    stats.recordKeyframe(bytes: 300_000)
    stats.recordKeyframe(bytes: 300_000)
    stats.recordStill(bytes: 4_000_000)

    let manifest = starting().finalized(
      endedAt: "2026-11-03T14:19:48-05:00", duration: 286.4, stats: stats)

    XCTAssertEqual(manifest.status, .complete)
    XCTAssertEqual(manifest.capture.endedAt, "2026-11-03T14:19:48-05:00")
    XCTAssertEqual(manifest.capture.duration, 286.4)
    XCTAssertEqual(manifest.stats.keyframes, 2)
    XCTAssertEqual(manifest.stats.stills, 1)
    XCTAssertEqual(manifest.stats.bytes, 4_600_000)
  }

  func testRepairIsDistinguishableFromACleanStop() {
    // The pipeline warns on repaired and fails on incomplete, so the three
    // states must not collapse into two.
    let repaired = starting().repaired(endedAt: nil, duration: 12.0, stats: SessionStats())
    XCTAssertEqual(repaired.status, .repaired)
    XCTAssertNotEqual(repaired.status, .complete)
    XCTAssertNotEqual(repaired.status, .incomplete)
  }

  func testTheLifecycleSurvivesEncodingAndDecoding() throws {
    let manifest = starting().finalized(
      endedAt: "2026-11-03T14:19:48-05:00", duration: 1.5, stats: SessionStats(keyframes: 3))
    let data = try JSONLWriter.makeEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(Manifest.self, from: data)
    XCTAssertEqual(decoded, manifest)
    XCTAssertEqual(decoded.status, .complete)
  }
}

final class SessionStatsTests: XCTestCase {
  func testCountersAndBytes() {
    var stats = SessionStats()
    stats.recordKeyframe(bytes: 10)
    stats.recordKeyframe(bytes: 20)
    stats.recordDrop()
    stats.recordStill(bytes: 100)
    stats.recordMarkerObservation()
    stats.recordLandmark()

    XCTAssertEqual(stats.keyframes, 2)
    XCTAssertEqual(stats.dropped, 1)
    XCTAssertEqual(stats.stills, 1)
    XCTAssertEqual(stats.markerObservations, 1)
    XCTAssertEqual(stats.landmarks, 1)
    XCTAssertEqual(stats.bytes, 130)
  }

  func testDropRateIsOverOfferedFramesNotKeptOnes() {
    var stats = SessionStats()
    for _ in 0..<3 { stats.recordKeyframe(bytes: 1) }
    stats.recordDrop()
    XCTAssertEqual(stats.dropRate, 0.25, accuracy: 1e-12)
  }

  func testDropRateOfAnEmptySessionIsZeroNotUndefined() {
    XCTAssertEqual(SessionStats().dropRate, 0)
  }

  func testThermalKeepsTheWorstStateSeen() {
    var stats = SessionStats()
    stats.recordThermal(.fair)
    stats.recordThermal(.critical)
    stats.recordThermal(.nominal)
    XCTAssertEqual(stats.thermalMax, .critical, "cooling down must not erase the peak")
  }

  func testThermalSeverityIsOrdered() {
    let order: [ThermalState] = [.nominal, .fair, .serious, .critical]
    XCTAssertEqual(order.map(\.severity), [0, 1, 2, 3])
  }
}

final class TrackingClockTests: XCTestCase {
  func testItSumsTimeSpentLimitedRatherThanCountingFrames() {
    var clock = TrackingClock()
    clock.record(time: 0.0, tracking: .normal)
    clock.record(time: 1.0, tracking: .limited)  // normal until 1.0
    clock.record(time: 3.0, tracking: .limited)  // limited from 1.0 to 3.0
    clock.record(time: 4.0, tracking: .normal)   // limited from 3.0 to 4.0
    clock.record(time: 9.0, tracking: .normal)

    XCTAssertEqual(clock.limitedSeconds, 3.0, accuracy: 1e-9)
  }

  func testASessionThatNeverLosesTrackingReportsZero() {
    var clock = TrackingClock()
    for step in 0..<10 {
      clock.record(time: Double(step) * 0.1, tracking: .normal)
    }
    XCTAssertEqual(clock.limitedSeconds, 0)
  }

  func testTimeGoingBackwardsIsIgnoredRatherThanSubtracted() {
    var clock = TrackingClock()
    clock.record(time: 5.0, tracking: .limited)
    clock.record(time: 1.0, tracking: .limited)
    XCTAssertEqual(clock.limitedSeconds, 0)
  }

  func testNotAvailableCountsAsLimited() {
    var clock = TrackingClock()
    clock.record(time: 0.0, tracking: .notAvailable)
    clock.record(time: 2.0, tracking: .normal)
    XCTAssertEqual(clock.limitedSeconds, 2.0, accuracy: 1e-9)
  }
}
