import SwiftUI
import VividHomeCore

/// The room's outline with the walk on it, while the room is being captured
/// (ADR-0031, design §3): the first level view, the one the owner looks at
/// standing in the room.
///
/// Drawn from the outline in house metres and, once the capture is placed,
/// the keyframe path, the tapped corners and the camera moved into the house
/// frame by the live fit. Before two corners are tapped only the outline shows,
/// which is itself the reminder of what to do.
struct PlanInsetView: View {
  let room: CaptureCoordinator.GuidedRoom
  let guidance: CaptureCoordinator.Guidance
  let placement: PlanAlignment.Solution?
  let coverage: [WallCoverage.Wall]?
  let walk: [(x: Double, z: Double)]
  let landmarks: [PlacedLandmark]
  let camera: (x: Double, z: Double)?

  static let side: CGFloat = 132
  private static let margin: Double = 12

  var body: some View {
    Canvas { context, size in
      guard
        let fit = InsetFit(
          points: room.corners.map { (x: $0.x, z: $0.z) }, width: size.width, height: size.height,
          margin: Self.margin)
      else { return }
      func at(_ x: Double, _ z: Double) -> CGPoint {
        let point = fit.point(x: x, z: z)
        return CGPoint(x: point.x, y: point.y)
      }

      // The outline.
      var outline = Path()
      for (index, corner) in room.corners.enumerated() {
        let point = at(corner.x, corner.z)
        if index == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
      }
      outline.closeSubpath()
      context.fill(outline, with: .color(Tokens.ink.opacity(0.06)))
      context.stroke(outline, with: .color(Tokens.ink.opacity(0.8)), lineWidth: 1.5)

      // Each wall shaded by how much of it the keyframes have photographed
      // (design §4): grey nothing, amber some, green most.
      if let coverage {
        for wall in coverage {
          guard let a = room.corners.first(where: { $0.label == wall.start }),
            let b = room.corners.first(where: { $0.label == wall.end })
          else { continue }
          var segment = Path()
          segment.move(to: at(a.x, a.z))
          segment.addLine(to: at(b.x, b.z))
          context.stroke(segment, with: .color(Self.shade(wall.fraction)), lineWidth: 4)
        }
      }

      if let placement {
        // The walk so far, in the house frame.
        var path = Path()
        for (index, step) in walk.enumerated() {
          let house = placement.houseXZ(sessionX: step.x, z: step.z)
          let point = at(house.x, house.z)
          if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(Tokens.accentWarm), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        // The tapped corners, where the fit puts them.
        for landmark in landmarks where landmark.kind == .corner {
          let house = placement.houseXZ(sessionX: landmark.position.x, z: landmark.position.z)
          let point = at(house.x, house.z)
          let dot = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
          context.fill(dot, with: .color(Tokens.ok))
        }

        // The camera now.
        if let camera {
          let house = placement.houseXZ(sessionX: camera.x, z: camera.z)
          let point = at(house.x, house.z)
          let dot = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
          context.fill(dot, with: .color(.white))
          context.stroke(dot, with: .color(Tokens.accentWarm), lineWidth: 1.5)
        }
      }

      // The outline's corners: ticked, lit, or waiting.
      for corner in room.corners {
        let point = at(corner.x, corner.z)
        let placed = guidance.placed.contains(corner.label)
        let next = guidance.next == corner.label
        let ring = Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
        if placed {
          context.stroke(ring, with: .color(Tokens.ok), lineWidth: 1.5)
        } else if next {
          context.fill(ring, with: .color(Tokens.accentCool))
        } else {
          context.stroke(ring, with: .color(Tokens.inkSecondary), lineWidth: 1)
        }
      }
    }
    .frame(width: Self.side, height: Self.side)
    .background(Tokens.scrim, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.hairline, lineWidth: 1))
    .overlay(alignment: .bottomLeading) {
      Text(caption)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Tokens.inkSecondary)
        .padding(6)
    }
  }

  private var caption: String {
    guard placement != nil else { return "tap 2 corners" }
    guard let coverage, !coverage.isEmpty else { return "" }
    let done = coverage.filter { $0.fraction >= 0.7 }.count
    return "walls \(done)/\(coverage.count)"
  }

  /// Three bands, not a gradient, like the coverage pins on the plan screen.
  static func shade(_ fraction: Double) -> Color {
    if fraction >= 0.7 { return Tokens.ok }
    if fraction >= 0.3 { return Tokens.warn }
    return Tokens.inkSecondary.opacity(0.6)
  }
}
