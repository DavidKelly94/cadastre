import Dispatch
import Foundation

/// A serial background queue that drops work rather than growing without limit.
///
/// The capture loop hands off a keyframe roughly thirty times a second, and
/// encoding one takes about as long as the gap between them. If the phone falls
/// behind — thermal throttling, a slow write, a burst of motion — something has
/// to give. An unbounded queue would spend memory holding pixel buffers until the
/// app is killed, losing the whole session; dropping a keyframe loses one frame
/// and says so in the statistics.
///
/// So `enqueue` never blocks and never queues past `depth`. It returns whether
/// the work was accepted, and the caller counts the refusals.
///
/// Dispatch is part of Foundation on Linux, so this is tested in CI rather than
/// only on a phone.
public final class BoundedWriteQueue {
  private let queue: DispatchQueue
  private let slots: DispatchSemaphore

  /// How many items may be outstanding at once, queued or running.
  public let depth: Int

  public init(label: String, depth: Int, qos: DispatchQoS = .utility) {
    precondition(depth >= 1, "a depth below 1 would accept nothing")
    self.depth = depth
    self.queue = DispatchQueue(label: label, qos: qos)
    self.slots = DispatchSemaphore(value: depth)
  }

  /// Submit work, or refuse it if the queue is already full.
  ///
  /// Returns false when the item was dropped. The check is a zero-timeout wait,
  /// so a caller on the ARKit delegate thread is never held up.
  @discardableResult
  public func enqueue(_ work: @escaping @Sendable () -> Void) -> Bool {
    guard slots.wait(timeout: .now()) == .success else {
      return false
    }
    queue.async { [slots] in
      work()
      slots.signal()
    }
    return true
  }

  /// Block until everything submitted so far has finished.
  ///
  /// Used at stop, before the manifest is rewritten: the statistics have to
  /// describe files that are actually on disk.
  public func drain() {
    queue.sync {}
  }
}
