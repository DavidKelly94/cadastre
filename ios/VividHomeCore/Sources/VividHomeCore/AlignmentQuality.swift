import Foundation

/// How well a set of tapped landmarks would determine a 2D rigid fit.
///
/// [ADR-0027]. The pipeline solves `umeyama_2d`, a rotation and translation from
/// point-to-point correspondences, which needs two. Whether the result is any
/// good depends on how the points are *arranged*, not how many there are:
///
/// - **Spread**, because a short lever arm turns a centimetre of tap error into
///   degrees of rotation error.
/// - **Non-collinearity**, because points along one wall leave the perpendicular
///   direction poorly determined. The solver's reflection guard keeps such a fit
///   a rotation; it does not make it a good one.
///
/// So three taps in one corner score worse than two at opposite ends of a room,
/// which is the opposite of what counting says.
///
/// **This measures geometry, never correctness.** A perfectly conditioned set of
/// points that are all in the wrong place scores full marks. Nothing here can
/// tell whether the owner tapped the corner they meant, and the reading must not
/// be presented as if it could.
///
/// It is also computed in the session frame alone, before any plan pairing
/// exists. A badly chosen pairing on the PC can still ruin a capture that scored
/// well here — this is the cheaper, weaker of the two measures on purpose, and
/// it never reports a residual, which only `align` can compute.
public enum AlignmentQuality {

  public enum Verdict: String, Equatable, Sendable {
    /// Fewer than two points: `umeyama_2d` refuses outright.
    case impossible
    /// A fit exists but its error cannot be checked, or its geometry is weak.
    case weak
    /// Enough spread and enough points to trust the residual `align` reports.
    case good
  }

  public struct Report: Equatable, Sendable {
    public var verdict: Verdict
    /// Largest distance between any two points, in metres. The lever arm.
    public var spread: Double
    /// How far the points are from lying on one line, 0 to 1.
    ///
    /// The ratio of the point cloud's smaller principal spread to its larger:
    /// 0 is a straight line, 1 is as round as the points get. Scale-free, so a
    /// hallway and a great room are judged the same way.
    public var balance: Double
    public var count: Int
    /// What to do next, in the owner's words, or nil when nothing is needed.
    public var advice: String?

    public init(
      verdict: Verdict, spread: Double, balance: Double, count: Int, advice: String?
    ) {
      self.verdict = verdict
      self.spread = spread
      self.balance = balance
      self.count = count
      self.advice = advice
    }
  }

  /// Below this the lever arm is too short for the rotation to survive tap error.
  ///
  /// Tap error is a few centimetres at 1–2 m. Over a 2 m baseline that is around
  /// a degree, which across a 10 m house is more than a stud bay.
  public static let minimumSpread = 2.0

  /// Below this the points are effectively a line and the perpendicular
  /// direction is unconstrained.
  public static let minimumBalance = 0.15

  /// Four is where averaging starts to pay: as-built deviation is 1–2 inches per
  /// wall and roughly independent per wall, so more well-spread points average
  /// that down. Three only makes a residual *visible*; it does not make it small.
  public static let comfortableCount = 4

  /// Judge a set of landmark positions. Only the horizontal plane matters — the
  /// fit is SE(2) plus a z offset ([ADR-0007]), so height is not an input.
  public static func evaluate(_ positions: [Vector3]) -> Report {
    let points = positions.map { (x: $0.x, z: $0.z) }

    guard points.count >= 2 else {
      return Report(
        verdict: .impossible, spread: 0, balance: 0, count: points.count,
        advice: points.isEmpty
          ? "Tap a room corner or a door threshold to start."
          : "One more, as far from the first as the room allows.")
    }

    let spread = Self.spread(points)
    let balance = Self.balance(points)

    if spread < minimumSpread {
      return Report(
        verdict: .weak, spread: spread, balance: balance, count: points.count,
        advice: "These are close together. Add one at the far end of the room.")
    }
    if balance < minimumBalance {
      return Report(
        verdict: .weak, spread: spread, balance: balance, count: points.count,
        advice: "These are nearly in a line. Add one off to the side.")
    }
    if points.count < comfortableCount {
      return Report(
        verdict: .weak, spread: spread, balance: balance, count: points.count,
        advice: "Good spread. One or two more and the alignment can be checked.")
    }
    return Report(
      verdict: .good, spread: spread, balance: balance, count: points.count, advice: nil)
  }

  /// Largest pairwise distance. Exact rather than sampled: a room has a handful
  /// of landmarks, so the quadratic cost is nothing and an approximation here
  /// would be a second thing to be wrong.
  static func spread(_ points: [(x: Double, z: Double)]) -> Double {
    var best = 0.0
    for i in points.indices {
      for j in points.indices where j > i {
        let dx = points[i].x - points[j].x
        let dz = points[i].z - points[j].z
        best = max(best, (dx * dx + dz * dz).squareRoot())
      }
    }
    return best
  }

  /// Smaller principal spread over larger, via the 2x2 covariance eigenvalues.
  ///
  /// Closed form rather than an SVD: for a symmetric 2x2 the eigenvalues are
  /// `mean ± sqrt(gap² + b²)`, which is exact and needs no linear algebra in the
  /// core package. The square root of the eigenvalue ratio is used so the number
  /// is a ratio of *distances*, which is what "how far from a line" means.
  static func balance(_ points: [(x: Double, z: Double)]) -> Double {
    let n = Double(points.count)
    guard n >= 2 else { return 0 }
    let mx = points.reduce(0) { $0 + $1.x } / n
    let mz = points.reduce(0) { $0 + $1.z } / n

    var sxx = 0.0, szz = 0.0, sxz = 0.0
    for p in points {
      let dx = p.x - mx, dz = p.z - mz
      sxx += dx * dx
      szz += dz * dz
      sxz += dx * dz
    }
    sxx /= n
    szz /= n
    sxz /= n

    let mean = (sxx + szz) / 2
    let gap = (sxx - szz) / 2
    let root = (gap * gap + sxz * sxz).squareRoot()
    let larger = mean + root
    let smaller = mean - root
    guard larger > 1e-12 else { return 0 }
    return (max(0, smaller) / larger).squareRoot()
  }
}
