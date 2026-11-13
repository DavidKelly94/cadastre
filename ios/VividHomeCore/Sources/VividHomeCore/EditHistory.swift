import Foundation

/// What an editor looked like before each change, so Undo puts back the last
/// thing done rather than deleting the last thing made.
///
/// Build 78's outline screen had "Undo last" remove the final corner whatever
/// had just happened: drag a corner of a room read off the drawing, undo, and
/// a different corner was gone. The editor records its state before every
/// change (a tap, the start of a drag, a clear), and undo steps back through
/// those. It stops at the state the screen opened with.
public struct EditHistory<Value: Equatable> {
  private var earlier: [Value] = []
  /// Enough for any outline; a bound so a long session cannot grow it forever.
  public static var limit: Int { 200 }

  public init() {}

  /// Call with the current value just before changing it.
  public mutating func record(_ value: Value) {
    // A touch that changes nothing (a tap on a corner without a drag) records
    // the same state twice; keep one.
    if earlier.last == value { return }
    earlier.append(value)
    if earlier.count > Self.limit { earlier.removeFirst(earlier.count - Self.limit) }
  }

  /// Whether there is an earlier state that differs from the current one.
  public func canUndo(from current: Value) -> Bool {
    earlier.contains { $0 != current }
  }

  /// The most recent earlier state that differs from the current one, or nil
  /// when there is nothing to step back to.
  public mutating func undo(from current: Value) -> Value? {
    while let previous = earlier.popLast() {
      if previous != current { return previous }
    }
    return nil
  }
}
