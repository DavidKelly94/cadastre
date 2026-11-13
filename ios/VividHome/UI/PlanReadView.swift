import SwiftUI
import UIKit
import VividHomeCore

/// What the drawing says about itself, for the owner to accept (ADR-0032).
///
/// A plan imported from a CAD PDF already carries its scale, its room names
/// and its walls. This reads them, shows the scale with how many of the
/// sheet's own dimensions bear it out, draws the outline it found for each
/// room over the drawing, and writes what the owner leaves ticked. Nothing is
/// written before Apply, and the Scale and Outline screens remain for
/// whatever this gets wrong.
struct PlanReadView: View {
  @ObservedObject var store: PlanStore
  let level: String

  @State private var reading: PlanStore.SheetReading?
  @State private var loading = true
  @State private var chosen: Set<String> = []
  @State private var useScale = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  private var plan: PlanFile? { store.plans[level] }

  var body: some View {
    Group {
      if loading {
        VStack(spacing: 12) {
          ProgressView().controlSize(.large)
          Text("Reading the drawing").font(.footnote).foregroundStyle(.secondary)
        }
      } else if let reading, let plan, let image = store.image(for: plan) {
        content(reading, plan: plan, image: image)
      } else {
        ContentUnavailableView(
          "This drawing cannot be read", systemImage: "doc.questionmark",
          description: Text(
            "It needs the original PDF, as exported from the architect's software. "
              + "A scan or a photo is set up by hand: Scale, then the rooms."))
      }
    }
    .navigationTitle("Read the drawing")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Apply", action: apply).disabled(reading == nil || (chosen.isEmpty && !useScale))
      }
    }
    .task { await load() }
    .alert("Could not apply", isPresented: .constant(failure != nil)) {
      Button("OK") { failure = nil }
    } message: {
      Text(failure ?? "")
    }
  }

  // MARK: - Content

  private func content(_ reading: PlanStore.SheetReading, plan: PlanFile, image: UIImage) -> some View {
    VStack(spacing: 0) {
      overlay(reading, image: image)
        .frame(maxHeight: 280)
        .background(Color(.secondarySystemBackground))
      List {
        Section {
          scaleRows(reading, plan: plan)
        } header: {
          Text("Scale")
        }
        Section {
          ForEach(reading.proposal.rooms, id: \.slug) { room in
            Toggle(isOn: binding(for: room.slug)) {
              VStack(alignment: .leading, spacing: 2) {
                Text(room.name.capitalized)
                Text(detail(room, reading: reading, plan: plan))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text("Rooms")
        } footer: {
          Text(
            "Green rooms get their corners from the walls on the drawing. Amber ones share a space "
              + "with no wall between and are pinned only; outline those by hand, as one room or several. "
              + "Read \(reading.proposal.textRuns) pieces of text, \(reading.proposal.dimensions) dimensions "
              + "and \(reading.proposal.wallShapes) wall shapes.")
        }
      }
    }
  }

  /// The drawing with what was found drawn over it.
  private func overlay(_ reading: PlanStore.SheetReading, image: UIImage) -> some View {
    GeometryReader { outer in
      let fitted = PlanCoverageView.fit(image.size, into: outer.size)
      let scale = image.size.width == 0 ? 1 : fitted.width / image.size.width
      let k = scale * reading.pixelsPerPoint
      ZStack(alignment: .topLeading) {
        Image(uiImage: image).resizable().frame(width: fitted.width, height: fitted.height)
        Canvas { context, _ in
          for room in reading.proposal.rooms where room.outline.count >= 3 {
            var path = Path()
            for (index, corner) in room.outline.enumerated() {
              let point = CGPoint(x: corner.x * k, y: corner.y * k)
              if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            let tone: Color = room.status == .outlined ? .green : .orange
            let on = chosen.contains(room.slug)
            context.fill(path, with: .color(tone.opacity(on ? 0.22 : 0.06)))
            context.stroke(path, with: .color(tone.opacity(on ? 0.95 : 0.4)), lineWidth: 1.5)
          }
          for room in reading.proposal.rooms {
            let point = CGPoint(x: room.label.x * k, y: room.label.y * k)
            let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
            context.fill(dot, with: .color(.blue))
          }
        }
        .frame(width: fitted.width, height: fitted.height)
        .allowsHitTesting(false)
      }
      .frame(width: outer.size.width, height: outer.size.height)
    }
  }

  @ViewBuilder
  private func scaleRows(_ reading: PlanStore.SheetReading, plan: PlanFile) -> some View {
    if let scale = reading.proposal.scale {
      let across = (reading.proposal.wallBounds?.width ?? 0) * scale.metresPerPoint
      VStack(alignment: .leading, spacing: 4) {
        Text(scale.note).font(.body.monospaced())
        switch scale.check {
        case .agrees:
          Label(
            "\(scale.agreement.agreeing) of \(scale.agreement.tested) dimensions on the sheet agree",
            systemImage: "checkmark.circle.fill"
          )
          .font(.footnote).foregroundStyle(.green)
        case .unchecked:
          Label(
            "Could not be checked against the sheet's dimensions",
            systemImage: "questionmark.circle.fill"
          )
          .font(.footnote).foregroundStyle(.orange)
        case .disagrees:
          Label(
            "Only \(scale.agreement.agreeing) of \(scale.agreement.tested) dimensions fit this. "
              + "The page was probably resized. Set the scale by hand.",
            systemImage: "xmark.octagon.fill"
          )
          .font(.footnote).foregroundStyle(.red)
        }
        if across > 0, scale.check != .disagrees {
          Text(
            "That makes the building \(Self.feet(across)) (\(String(format: "%.1f", across)) m) across its walls.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      if plan.isCalibrated {
        Text("This plan already has a scale, and it is kept: captures may be aligned to it.")
          .font(.footnote).foregroundStyle(.secondary)
      } else if scale.check != .disagrees {
        Toggle("Use this scale", isOn: $useScale)
      }
    } else {
      Text("No scale note was found on the sheet. Set the scale by hand.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private func detail(_ room: SheetReader.Room, reading: PlanStore.SheetReading, plan: PlanFile) -> String {
    let had = plan.placement(of: room.slug)?.outline != nil ? " Replaces the outline it has." : ""
    switch room.status {
    case .outlined:
      guard room.outline.count <= SheetReader.maximumCorners else {
        return "\(room.outline.count) corners is too many to tap round: pinned only."
      }
      var text = "\(room.outline.count) corners"
      if let scale = reading.proposal.scale, scale.check != .disagrees {
        let squareFeet = room.areaPoints * pow(scale.metresPerPoint / 0.3048, 2)
        text += " · \(Int(squareFeet.rounded())) sq ft"
      }
      return text + "." + had
    case .openPlan:
      return "Open to \(room.sharedWith.joined(separator: ", ")): pinned, not outlined."
    case .notEnclosed:
      return "Not enclosed by walls on the drawing: pinned only."
    }
  }

  private func binding(for slug: String) -> Binding<Bool> {
    Binding(
      get: { chosen.contains(slug) },
      set: { on in
        if on { chosen.insert(slug) } else { chosen.remove(slug) }
      })
  }

  static func feet(_ metres: Double) -> String {
    let inches = (metres / 0.0254).rounded()
    return "\(Int(inches) / 12) ft \(Int(inches) % 12) in"
  }

  // MARK: - Work

  private func load() async {
    guard reading == nil else { return }
    guard let plan, let source = store.sheetSource(for: level), let image = store.image(for: plan) else {
      loading = false
      return
    }
    let width = Double(image.size.width)
    let found = await Task.detached(priority: .userInitiated) {
      PlanStore.readSheet(at: source.url, page: source.page, rasterWidth: width)
    }.value
    reading = found
    if let found {
      // Everything on, except an outline that would replace one drawn by hand.
      chosen = Set(
        found.proposal.rooms.filter { plan.placement(of: $0.slug)?.outline == nil }.map(\.slug))
      useScale = !plan.isCalibrated && found.proposal.scale?.check == .agrees
    }
    loading = false
  }

  private func apply() {
    guard let reading, let plan, let image = store.image(for: plan) else { return }
    do {
      try store.apply(reading, to: level, rooms: chosen, setScale: useScale, size: image.size)
      dismiss()
    } catch {
      failure = error.localizedDescription
    }
  }
}
