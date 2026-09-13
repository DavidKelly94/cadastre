import Dispatch
import Foundation
import XCTest

@testable import CadastreCore

/// Backpressure is where a capture either drops one frame or dies holding all of
/// them, so it is tested deterministically rather than by timing.
final class BoundedWriteQueueTests: XCTestCase {
  func testItAcceptsUpToItsDepthAndThenRefuses() {
    let queue = BoundedWriteQueue(label: "test.depth", depth: 2)
    // A gate the jobs block on, so the queue is provably full.
    let gate = DispatchSemaphore(value: 0)

    XCTAssertTrue(queue.enqueue { gate.wait() })
    XCTAssertTrue(queue.enqueue { gate.wait() })
    XCTAssertFalse(queue.enqueue { gate.wait() }, "a third item must be refused, not queued")

    gate.signal()
    gate.signal()
    queue.drain()
  }

  func testASlotIsFreedWhenWorkFinishes() {
    let queue = BoundedWriteQueue(label: "test.reuse", depth: 1)
    let gate = DispatchSemaphore(value: 0)

    XCTAssertTrue(queue.enqueue { gate.wait() })
    XCTAssertFalse(queue.enqueue {})

    gate.signal()
    queue.drain()
    XCTAssertTrue(queue.enqueue {}, "the slot must come back after the work finishes")
    queue.drain()
  }

  func testEveryAcceptedItemRunsExactlyOnceAndInOrder() {
    let queue = BoundedWriteQueue(label: "test.order", depth: 4)
    let lock = NSLock()
    var ran: [Int] = []

    for index in 0..<4 {
      XCTAssertTrue(
        queue.enqueue {
          lock.lock()
          ran.append(index)
          lock.unlock()
        })
    }
    queue.drain()

    XCTAssertEqual(ran, [0, 1, 2, 3], "a serial queue must preserve submission order")
  }

  func testDrainWaitsForWorkToFinish() {
    let queue = BoundedWriteQueue(label: "test.drain", depth: 2)
    let finished = NSLock()
    var done = false

    queue.enqueue {
      Thread.sleep(forTimeInterval: 0.05)
      finished.lock()
      done = true
      finished.unlock()
    }
    queue.drain()

    finished.lock()
    let observed = done
    finished.unlock()
    XCTAssertTrue(observed, "drain returned before the work was done")
  }

  func testEnqueueDoesNotBlockTheCaller() {
    // The caller is the ARKit delegate; holding it up would stall the session.
    let queue = BoundedWriteQueue(label: "test.nonblocking", depth: 1)
    let gate = DispatchSemaphore(value: 0)
    queue.enqueue { gate.wait() }

    let start = Date()
    for _ in 0..<200 {
      _ = queue.enqueue {}
    }
    let elapsed = Date().timeIntervalSince(start)

    gate.signal()
    queue.drain()
    XCTAssertLessThan(elapsed, 1.0, "refusals must be immediate, took \(elapsed)s")
  }

  func testDrainOnAnIdleQueueReturns() {
    let queue = BoundedWriteQueue(label: "test.idle", depth: 2)
    queue.drain()
  }
}
