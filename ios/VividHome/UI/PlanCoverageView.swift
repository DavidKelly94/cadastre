import SwiftUI
import UIKit
import VividHomeCore

/// The plan for a level, with each room where the owner put it, shaded by what
/// has been captured.
///
/// This is the screen the plan work exists for. Coverage was previously a count
/// — `Kitchen 2/6` — and a count cannot tell you the far corner of the great
/// room was never walked. Standing in the building is the only moment that gap
/// can still be closed.
///
/// **Nothing here is a measurement.** A placement is a fingertip on a drawing,
/// it carries no accuracy claim, and it is never an input to alignment
/// (`docs/session-format.md` §13). The drag is loose on purpose: a control that
/// snapped or showed coordinates would imply a precision this does not have.
struct PlanCoverageView: View {
  @ObservedObject var store: PlanStore
  let level: String
  /// Room slug to captured-phase count, from the sessions on disk.
  let coverage: [String: (done: Int, total: Int)]
  let onDone: () -> Void

  @State private var dragging: String?
  @State private var dragPoint: CGPoint = .zero

  private static let space = "plan"

  private var plan: PlanFile? { store.plans[level] }

  var body: some View {
    NavigationStack {
      Group {
        if let plan, let image = store.image(for: plan) {
          content(plan: plan, image: image)
        } else {
          ContentUnavailableView(
            "No plan for this level", systemImage: "map",
            description: Text("Add one and captures on this level can be placed on it."))
        }
      }
      .navigationTitle(plan?.level.capitalized ?? "Level")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
    }
  }

  private func content(plan: PlanFile, image: UIImage) -> some View {
    VStack(spacing: 0) {
      GeometryReader { outer in
        // The raster is drawn to fit and letterboxed, so a pin's position is the
        // box's own offset plus the stored plan pixel scaled. Every conversion
        // goes through this one scale, which is why a placement stored in plan
        // pixels stays correct at any display size.
        let fitted = Self.fit(image.size, into: outer.size)
        let originX = (outer.size.width - fitted.width) / 2
        let originY = (outer.size.height - fitted.height) / 2
        let scale = image.size.width == 0 ? 1 : fitted.width / image.size.width

        ZStack(alignment: .topLeading) {
          Image(uiImage: image)
            .resizable().scaledToFit()
            .frame(width: fitted.width, height: fitted.height)
            .offset(x: originX, y: originY)

          ForEach(plan.rooms, id: \.room) { room in
            pin(room, image: image, scale: scale, origin: CGPoint(x: originX, y: originY))
          }
        }
        .frame(width: outer.size.width, height: outer.size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
      }
      .background(Color(.secondarySystemBackground))

      footer
    }
  }

  private func pin(_ room: PlanRoom, image: UIImage, scale: CGFloat, origin: CGPoint) -> some View {
    let resting = CGPoint(x: origin.x + room.x * scale, y: origin.y + room.y * scale)
    let shown = dragging == room.room ? dragPoint : resting
    let done = coverage[room.room]?.done ?? 0
    let total = coverage[room.room]?.total ?? 0
    let fraction = total == 0 ? 0 : Double(done) / Double(total)

    return VStack(spacing: 3) {
      Circle()
        .fill(Self.shade(fraction))
        .overlay(Circle().strokeBorder(Self.ring(fraction), lineWidth: 2.5))
        .frame(width: 18, height: 18)
        .scaleEffect(dragging == room.room ? 1.25 : 1)
      Text(total == 0 ? room.room : "\(room.room) \(done)/\(total)")
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
    }
    // A 44 pt target around an 18 pt dot: the dot is the mark, the target is
    // for a thumb.
    .frame(width: 44, height: 44)
    .contentShape(Rectangle())
    .position(shown)
    .gesture(
      // Named space, so the drag reports where the finger is on the plan rather
      // than inside the pin it started on.
      DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
        .onChanged { value in
          dragging = room.room
          dragPoint = value.location
        }
        .onEnded { value in
          dragging = nil
          guard scale > 0 else { return }
          let stored = CGPoint(
            x: (value.location.x - origin.x) / scale,
            y: (value.location.y - origin.y) / scale)
          // Out of bounds is refused by PlanFile.place, so a room dragged off
          // the sheet stays where it was rather than being written somewhere
          // validate would reject.
          try? store.place(room: room.room, at: stored, on: level, size: image.size)
        })
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 16) {
        legend("Most phases", Self.shade(0.9), Self.ring(0.9))
        legend("Some", Self.shade(0.5), Self.ring(0.5))
        legend("Barely", Self.shade(0.1), Self.ring(0.1))
      }
      Text("Drag a room to where it actually is. A placement says which room is which — "
        + "it is never used to align a capture.")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.bar)
  }

  private func legend(_ text: String, _ fill: Color, _ ring: Color) -> some View {
    HStack(spacing: 6) {
      Circle().fill(fill).overlay(Circle().strokeBorder(ring, lineWidth: 2)).frame(width: 12, height: 12)
      Text(text).font(.caption).foregroundStyle(.secondary)
    }
  }

  // MARK: - Helpers

  /// Three bands, not a gradient. A continuous shade invites reading a precision
  /// off a colour that is really "two of six trades, which two unstated".
  static func shade(_ fraction: Double) -> Color {
    if fraction >= 0.75 { return Color(red: 0.12, green: 0.62, blue: 0.35) }
    if fraction >= 0.30 { return Color(red: 0.18, green: 0.50, blue: 0.82) }
    return Color(.systemBackground)
  }

  static func ring(_ fraction: Double) -> Color {
    if fraction >= 0.75 { return Color(red: 0.12, green: 0.62, blue: 0.35) }
    if fraction >= 0.30 { return Color(red: 0.18, green: 0.50, blue: 0.82) }
    return Color(red: 0.47, green: 0.54, blue: 0.60)
  }

  static func fit(_ image: CGSize, into box: CGSize) -> CGSize {
    guard image.width > 0, image.height > 0 else { return .zero }
    let scale = min(box.width / image.width, box.height / image.height)
    return CGSize(width: image.width * scale, height: image.height * scale)
  }
}
