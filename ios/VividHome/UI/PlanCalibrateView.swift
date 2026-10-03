import SwiftUI
import UIKit
import VividHomeCore

/// Setting a level's scale and origin on the phone (ADR-0030, design §2).
///
/// The same three points the PC's page asks for: two ends of a printed
/// dimension, then the house origin, on a ``PlanPointCanvas``. Nothing is
/// written until Save.
struct PlanCalibrateView: View {
  @ObservedObject var store: PlanStore
  let level: String

  /// The points placed so far, in plan pixels: scale end, scale end, origin.
  @State private var points: [CGPoint] = []
  @State private var distanceText = ""
  @State private var rotationText = "0"
  @State private var floorText = "0"
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  private static let stepTitles = [
    "One end of a printed dimension",
    "The other end of it",
    "The point that is house origin (0, 0)",
  ]

  private var plan: PlanFile? { store.plans[level] }
  private var distanceMetres: Double? {
    PlanDistance.metres(from: distanceText).flatMap { $0 > 0 ? $0 : nil }
  }
  private var canSave: Bool { points.count == 3 && distanceMetres != nil }

  /// What the three points and the typed distance say, before anything is saved.
  private var preview: PlanFile? {
    guard let plan, points.count >= 2, let metres = distanceMetres else { return nil }
    let origin = points.count == 3 ? points[2] : .zero
    return plan.calibrated(
      scaleFrom: (Double(points[0].x), Double(points[0].y)),
      to: (Double(points[1].x), Double(points[1].y)),
      distanceMetres: metres,
      origin: (Double(origin.x), Double(origin.y)))
  }

  var body: some View {
    Group {
      if let plan, let image = store.image(for: plan) {
        VStack(spacing: 0) {
          steps
          PlanPointCanvas(
            image: image, points: $points, maxPoints: 3, figure: .segment,
            colour: { $0 == 2 ? .blue : .orange }, labels: [])
          fields(plan: plan, image: image)
        }
      } else {
        ContentUnavailableView("No plan for this level", systemImage: "map")
      }
    }
    .navigationTitle("Scale and origin")
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

  private var steps: some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(Self.stepTitles.indices, id: \.self) { index in
        HStack(spacing: 8) {
          Image(systemName: index < points.count ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(index < points.count ? Color.green : Color.secondary)
          Text("\(index + 1). \(Self.stepTitles[index])")
            .font(index == points.count ? .footnote.weight(.semibold) : .footnote)
            .foregroundStyle(index == points.count ? Color.primary : Color.secondary)
        }
      }
      Text("Tap to place a point, then drag it to the exact spot. Pinch to zoom, drag the drawing to pan.")
        .font(.caption).foregroundStyle(.secondary)
        .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(.bar)
  }

  private func fields(plan: PlanFile, image: UIImage) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Distance between the first two").font(.footnote).foregroundStyle(.secondary)
        Spacer()
        TextField("25' 0\" or 7.62m", text: $distanceText)
          .textFieldStyle(.roundedBorder)
          .keyboardType(.numbersAndPunctuation)
          .autocorrectionDisabled()
          .frame(width: 150)
      }
      HStack {
        Text("Rotation (°) and floor height (m)").font(.footnote).foregroundStyle(.secondary)
        Spacer()
        TextField("0", text: $rotationText)
          .textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation).frame(width: 66)
        TextField("0", text: $floorText)
          .textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation).frame(width: 76)
      }
      Text(readout(plan: plan, imageWidth: Double(image.size.width)))
        .font(.footnote)
        .foregroundStyle(canSave ? Color.primary : Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("Start again") { points = [] }
        .font(.footnote)
        .disabled(points.isEmpty)
    }
    .padding(16)
    .background(.bar)
  }

  /// What the numbers mean, before Save: the scale and the drawing's width in
  /// metres, which is the sanity check. A house is tens of metres across.
  private func readout(plan: PlanFile, imageWidth: Double) -> String {
    if !distanceText.isEmpty, distanceMetres == nil {
      return "That is not a distance. Try 25' 0\", 11'-6 1/2\" or 7.62m."
    }
    if let preview, let mpp = preview.metresPerPixel,
      let width = preview.widthMetres(imageWidth: imageWidth)
    {
      let scaleText = String(format: "%.1f mm per pixel", mpp * 1000)
      let widthText = String(format: "%.1f m", width)
      return "\(scaleText); the drawing is \(widthText) wide. A house is tens of metres across."
    }
    if let mpp = plan.metresPerPixel, let width = plan.widthMetres(imageWidth: imageWidth) {
      return String(
        format: "Currently %.1f mm per pixel, %.1f m wide. Saving replaces it.", mpp * 1000, width)
    }
    return "No scale yet. Place the three points and type the printed distance."
  }

  private func save() {
    guard points.count == 3, let metres = distanceMetres else { return }
    do {
      try store.calibrate(
        level: level, scaleFrom: points[0], to: points[1], distanceMetres: metres,
        origin: points[2], rotationDegrees: Double(rotationText) ?? 0,
        floorHeight: Double(floorText) ?? 0)
      dismiss()
    } catch {
      failure = error.localizedDescription
    }
  }
}
