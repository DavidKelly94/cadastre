import Foundation

/// The corners of a room, found in the phone's own scan (ADR-0034,
/// `capture-guidance-design.md` section 2).
///
/// A corner is the vertical line where two walls meet, so it is found from
/// wall planes and reported as a point on the plan with the heights it was
/// seen over. That is what lets a ceiling corner stand in for a floor corner
/// hidden behind furniture, and what gives open framing a chance: the plates
/// and stud faces of one wall lie in one plane.
///
/// `CornerSnap` does this within half a meter of a tap. This is the whole
/// room, with nobody tapping. What it returns are candidates, to be matched
/// to the outline by `CornerMatch` and then shown to the owner as proposals:
/// nothing here places a capture.
public enum CornerFinder {
  /// A wall plane smaller than this is furniture, a door or a column.
  public static let minimumWallArea = 0.5
  /// With less wall-classed surface than this, ARKit has not recognized the
  /// walls (open framing), and every vertical face is used instead.
  public static let minimumClassedArea = 2.0

  /// Where two walls meet, in the frame the faces were in.
  public struct Candidate: Equatable, Sendable {
    public var x: Double
    public var z: Double
    /// The lowest and highest the two walls were seen at: the floor end and
    /// the ceiling end of the corner, as far as the scan reaches.
    public var bottom: Double
    public var top: Double
    /// The smaller of the two walls' areas: how much stands behind it.
    public var support: Double

    public init(x: Double, z: Double, bottom: Double, top: Double, support: Double) {
      self.x = x
      self.z = z
      self.bottom = bottom
      self.top = top
      self.support = support
    }
  }

  /// Every corner the faces show, best supported first.
  public static func candidates(faces: [CornerSnap.Face]) -> [Candidate] {
    var walls = CornerSnap.findWalls(faces).filter { $0.area >= minimumWallArea }
    if walls.reduce(0, { $0 + $1.area }) < minimumClassedArea {
      walls = CornerSnap.findWalls(faces, anyClass: true).filter { $0.area >= minimumWallArea }
    }
    var out: [Candidate] = []
    for i in walls.indices {
      for j in walls.indices where j > i {
        guard let point = CornerSnap.intersection(walls[i], walls[j]) else { continue }
        out.append(
          Candidate(
            x: point.x, z: point.z, bottom: min(walls[i].bottom, walls[j].bottom),
            top: max(walls[i].top, walls[j].top), support: min(walls[i].area, walls[j].area)))
      }
    }
    return out.sorted { $0.support > $1.support }
  }
}

/// Matching the corners found in a scan to a room's outline (ADR-0034).
///
/// A capture sits on its plan by a turn and a shift, never a mirror, and two
/// matched corners fix both. So every pair of candidates is tried against
/// every pair of outline corners the same distance apart, and the motion
/// that lands the most candidates on outline corners wins. A rectangular
/// room fits two ways round, a square four: those are reported as
/// alternatives for the owner to choose between, never chosen here.
public enum CornerMatch {
  /// How close a candidate must land to an outline corner to be it.
  public static let tolerance = 0.15
  /// Fits whose errors differ by less than this are equally good.
  public static let sameFit = 0.03

  /// A candidate named for the outline corner it would be.
  public struct Mark: Equatable, Sendable {
    public var label: String
    /// The candidate's position, in the frame the scan was in.
    public var x: Double
    public var z: Double
    public var bottom: Double
    public var top: Double
  }

  /// One way the scan fits the outline.
  public struct Fit: Equatable, Sendable {
    /// In the outline's order.
    public var marks: [Mark]
    public var rms: Double
  }

  public struct Proposal: Equatable, Sendable {
    /// The best fit.
    public var fit: Fit
    /// Outline corners the scan did not find: the ones to tap by hand.
    public var missing: [String]
    /// Other ways round that fit as well. Empty for a room that only fits
    /// one way; when not, the owner is asked.
    public var alternatives: [Fit]

    public var isAmbiguous: Bool { !alternatives.isEmpty }
  }

  /// Match candidates to an outline given in house meters. Nil with fewer
  /// than two candidates landing on corners: one alone says nothing.
  public static func propose(
    candidates: [CornerFinder.Candidate], outline: [(label: String, x: Double, z: Double)]
  ) -> Proposal? {
    guard candidates.count >= 2, outline.count >= 2 else { return nil }

    struct Scored {
      var assignment: [Int: Int]  // outline index -> candidate index
      var rms: Double
    }
    var seen: Set<String> = []
    var fits: [Scored] = []

    for i in candidates.indices {
      for j in candidates.indices where j != i {
        let cdx = candidates[j].x - candidates[i].x, cdz = candidates[j].z - candidates[i].z
        let between = (cdx * cdx + cdz * cdz).squareRoot()
        guard between > 0.3 else { continue }
        for a in outline.indices {
          for b in outline.indices where b != a {
            let odx = outline[b].x - outline[a].x, odz = outline[b].z - outline[a].z
            let apart = (odx * odx + odz * odz).squareRoot()
            guard abs(apart - between) <= tolerance else { continue }

            // The turn that lines the pair up, and the shift that lays one
            // midpoint on the other.
            let turn = atan2(odz, odx) - atan2(cdz, cdx)
            let c = cos(turn), s = sin(turn)
            let mx = (candidates[i].x + candidates[j].x) / 2, mz = (candidates[i].z + candidates[j].z) / 2
            let tx = (outline[a].x + outline[b].x) / 2 - (c * mx - s * mz)
            let tz = (outline[a].z + outline[b].z) / 2 - (s * mx + c * mz)

            // Each candidate to the nearest outline corner within reach,
            // nearest pairs first, one candidate per corner.
            var pairs: [(distance: Double, corner: Int, candidate: Int)] = []
            for (index, candidate) in candidates.enumerated() {
              let x = c * candidate.x - s * candidate.z + tx
              let z = s * candidate.x + c * candidate.z + tz
              for (corner, point) in outline.enumerated() {
                let distance = ((x - point.x) * (x - point.x) + (z - point.z) * (z - point.z)).squareRoot()
                if distance <= tolerance { pairs.append((distance, corner, index)) }
              }
            }
            pairs.sort { $0.distance < $1.distance }
            var assignment: [Int: Int] = [:]
            var used: Set<Int> = []
            var sum = 0.0
            for pair in pairs where assignment[pair.corner] == nil && !used.contains(pair.candidate) {
              assignment[pair.corner] = pair.candidate
              used.insert(pair.candidate)
              sum += pair.distance * pair.distance
            }
            guard assignment.count >= 2 else { continue }
            let key = assignment.keys.sorted().map { "\($0):\(assignment[$0] ?? -1)" }.joined(separator: ",")
            guard seen.insert(key).inserted else { continue }
            fits.append(Scored(assignment: assignment, rms: (sum / Double(assignment.count)).squareRoot()))
          }
        }
      }
    }

    fits.sort {
      $0.assignment.count != $1.assignment.count ? $0.assignment.count > $1.assignment.count : $0.rms < $1.rms
    }
    guard let best = fits.first else { return nil }

    func fit(_ scored: Scored) -> Fit {
      let marks = scored.assignment.keys.sorted().map { corner -> Mark in
        let candidate = candidates[scored.assignment[corner] ?? 0]
        return Mark(
          label: outline[corner].label, x: candidate.x, z: candidate.z, bottom: candidate.bottom,
          top: candidate.top)
      }
      return Fit(marks: marks, rms: scored.rms)
    }

    let rivals = fits.dropFirst().filter {
      $0.assignment.count == best.assignment.count && $0.rms - best.rms <= sameFit
    }
    let found = Set(best.assignment.keys)
    return Proposal(
      fit: fit(best),
      missing: outline.indices.filter { !found.contains($0) }.map { outline[$0].label },
      alternatives: rivals.map(fit))
  }
}
