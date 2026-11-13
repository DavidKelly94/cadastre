import Foundation

/// What the capture screen shows of a `CornerMatch` (ADR-0034): which way
/// round, which marks, which corners are left for a hand.
///
/// The rules here are the owner's: a proposal is never a placement, a corner
/// marked by hand always wins, and a proposal that changes its mind between
/// one look and the next is worse than none. The ARKit layer draws what this
/// returns and decides nothing.
public enum CornerProposal {
  /// A fit's mark must be this close to a hand-placed mark of the same name
  /// for the fit to agree with it.
  public static let agreeMeters = 0.3
  /// The method recorded in `landmarks.jsonl` for a mark the scan proposed
  /// and the owner confirmed.
  public static let method = "mesh_corner_proposed"

  /// What to draw and say.
  public struct Shown: Equatable, Sendable {
    /// Marks for corners nobody has marked yet.
    public var marks: [CornerMatch.Mark]
    /// How many corners the outline has.
    public var total: Int
    /// Corners neither marked nor proposed: the ones to tap by hand.
    public var missing: [String]
    /// How many ways round still fit. More than one means the owner is asked.
    public var ways: Int
    /// The height to place confirmed marks at: the lowest the walls of this
    /// fit were seen, which is the floor wherever a wall reaches it.
    public var floor: Double
  }

  /// The fits that agree with every corner already marked by hand. A tapped
  /// corner settles which way round a symmetric room goes; a fit that puts
  /// that corner's name somewhere else is dropped.
  public static func consistent(
    _ fits: [CornerMatch.Fit], with marked: [String: (x: Double, z: Double)]
  ) -> [CornerMatch.Fit] {
    fits.filter { fit in
      fit.marks.allSatisfy { mark in
        guard let hand = marked[mark.label] else { return true }
        let dx = hand.x - mark.x, dz = hand.z - mark.z
        return (dx * dx + dz * dz).squareRoot() <= agreeMeters
      }
    }
  }

  /// Which of `fits` to show, given what was on screen a moment ago: the one
  /// that names the most corners the same way, so a room that fits two ways
  /// does not turn round by itself between refreshes. The first when nothing
  /// was shown.
  public static func steady(_ fits: [CornerMatch.Fit], previous: [CornerMatch.Mark]) -> Int {
    guard !previous.isEmpty else { return 0 }
    var best = 0
    var bestCount = -1
    for (index, fit) in fits.enumerated() {
      var count = 0
      for mark in fit.marks {
        guard let before = previous.first(where: { $0.label == mark.label }) else { continue }
        let dx = before.x - mark.x, dz = before.z - mark.z
        if (dx * dx + dz * dz).squareRoot() <= agreeMeters { count += 1 }
      }
      if count > bestCount {
        best = index
        bestCount = count
      }
    }
    return best
  }

  /// What to show of one fit. Nil when it proposes nothing new.
  public static func shown(
    fit: CornerMatch.Fit, ways: Int, corners: [String], placed: Set<String>
  ) -> Shown? {
    let open = fit.marks.filter { !placed.contains($0.label) }
    guard !open.isEmpty else { return nil }
    let named = placed.union(open.map(\.label))
    let floor = fit.marks.map(\.bottom).min() ?? 0
    return Shown(
      marks: open, total: corners.count, missing: corners.filter { !named.contains($0) }, ways: ways,
      floor: floor)
  }
}
