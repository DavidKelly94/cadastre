import SwiftUI
import UIKit
import VividHomeCore

/// Marking where a room's corners are on the drawing (ADR-0031, design §2).
///
/// Done at home, before the visit: the outline is what the guided taps in the
/// field are asked against, corner by corner, and what the capture is placed
/// on before the owner leaves the room. Tap the corners in order around the
/// room, drag any under the loupe, Save. Undo steps back through what was
/// done on this screen, and a room the drawing outlines (ADR-0032) can be put
/// back as drawn.
struct PlanOutlineView: View {
  @ObservedObject var store: PlanStore
  let level: String
  let room: String

  @State private var points: [CGPoint] = []
  @State private var history = EditHistory<[CGPoint]>()
  @State private var loaded = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  private var plan: PlanFile? { store.plans[level] }
  private var names: [String] {
    RoomOutline.cornerNames(for: points.map { [Double($0.x), Double($0.y)] })
  }
  /// The room's corners as the drawing has them, when it has been read.
  private var drawn: [CGPoint]? {
    store.drawnOutline(of: room, on: level)?.compactMap {
      $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil
    }
  }
  private var isAsDrawn: Bool {
    guard let drawn, drawn.count == points.count else { return false }
    return zip(drawn, points).allSatisfy { abs($0.x - $1.x) <= 1.5 && abs($0.y - $1.y) <= 1.5 }
  }
  private var canSave: Bool {
    guard let plan, let image = store.image(for: plan) else { return false }
    return RoomOutline.isValid(
      points.map { [Double($0.x), Double($0.y)] },
      in: (width: Int(image.size.width), height: Int(image.size.height)))
  }

  var body: some View {
    Group {
      if let plan, let image = store.image(for: plan) {
        VStack(spacing: 0) {
          header
          PlanPointCanvas(
            image: image, points: $points, maxPoints: nil, figure: .polygon,
            colour: { _ in .blue }, labels: names.map(Self.short),
            willChange: { history.record(points) })
          footer
        }
        .task { _ = await store.sheetReading(for: level) }
        .onAppear {
          guard !loaded else { return }
          loaded = true
          points = (plan.placement(of: room)?.outline ?? []).compactMap {
            $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil
          }
        }
      } else {
        ContentUnavailableView("No plan for this level", systemImage: "map")
      }
    }
    .navigationTitle("Outline \(room)")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(!canSave)
      }
    }
    .alert("Could not save", isPresented: .constant(failure != nil)) {
      Button("OK") { failure = nil }
    } message: {
      Text(failure ?? "")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(points.isEmpty
        ? "Tap each corner of \(room), in order around the room."
        : "\(points.count) corner\(points.count == 1 ? "" : "s") so far. Keep going around, then Save.")
        .font(.footnote.weight(.semibold))
      Text(drawn == nil
        ? "Inside corners, where two walls meet. Drag a point under the loupe to fix it. Pinch to zoom."
        : "Drag a point under the loupe to fix it. Pinch to zoom. As drawn puts back the walls on the drawing.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(.bar)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(names.isEmpty
        ? "Three corners minimum. The names come from where each corner sits: NW, NE, SE, SW."
        : "Corners: " + names.map(Self.short).joined(separator: ", ")
          + ". These are what the capture will ask you to tap.")
        .font(.footnote).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        // Undo puts back what was there before the last change, whatever
        // it was; it never goes past what the screen opened with.
        Button("Undo") {
          if let previous = history.undo(from: points) { points = previous }
        }
        .font(.footnote).disabled(!history.canUndo(from: points))
        Spacer()
        if let drawn {
          Button("As drawn") {
            history.record(points)
            points = drawn
          }
          .font(.footnote).disabled(isAsDrawn)
          Spacer()
        }
        Button("Start again") {
          history.record(points)
          points = []
        }
        .font(.footnote).disabled(points.isEmpty)
      }
    }
    .padding(16)
    .background(.bar)
  }

  /// `corner-ne2` as `NE2`, for a label beside a point.
  static func short(_ name: String) -> String {
    name.replacingOccurrences(of: "corner-", with: "").uppercased()
  }

  private func save() {
    guard let plan, let image = store.image(for: plan) else { return }
    do {
      try store.outline(
        room: room, on: level, points: points.map { [Double($0.x), Double($0.y)] },
        size: image.size)
      dismiss()
    } catch {
      failure = error.localizedDescription
    }
  }
}
