import SwiftUI
import UIKit
import VividHomeCore

/// Setting a level's scale and origin on the phone (ADR-0030, design §2).
///
/// The same three points the PC's page asks for: two ends of a printed
/// dimension, then the house origin. A tap places a point; dragging the point
/// moves it under a loupe, because a dimension tick is a few pixels wide and a
/// fingertip is forty. Pinch zooms the drawing and a one-finger drag on empty
/// plan pans it. Nothing is written until Save.
struct PlanCalibrateView: View {
  @ObservedObject var store: PlanStore
  let level: String

  /// The points placed so far, in plan pixels: scale end, scale end, origin.
  @State private var points: [CGPoint] = []
  /// Which point is being dragged, and where it is right now.
  @State private var dragging: Int?
  @State private var distanceText = ""
  @State private var rotationText = "0"
  @State private var floorText = "0"
  @State private var zoom: CGFloat = 1
  @State private var steadyZoom: CGFloat = 1
  @State private var pan: CGSize = .zero
  @State private var steadyPan: CGSize = .zero
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  private static let space = "calibrate-plan"
  private static let loupeSize: CGFloat = 132
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
  private func preview(imageWidth: Double) -> PlanFile? {
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
        content(plan: plan, image: image)
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

  private func content(plan: PlanFile, image: UIImage) -> some View {
    VStack(spacing: 0) {
      steps
      GeometryReader { outer in
        let fitted = PlanCoverageView.fit(image.size, into: outer.size)
        let scale = image.size.width == 0 ? 1 : fitted.width / image.size.width
        ZStack {
          // The drawing and its marks, in the drawing's own fitted space; the
          // zoom and pan are applied to the whole group, so a mark's position
          // is a plan pixel times one scale whatever the zoom.
          ZStack(alignment: .topLeading) {
            Image(uiImage: image)
              .resizable()
              .frame(width: fitted.width, height: fitted.height)
              .onTapGesture { point in
                guard points.count < 3, scale > 0 else { return }
                points.append(CGPoint(x: point.x / scale, y: point.y / scale))
              }
            if points.count >= 2 {
              Path { path in
                path.move(to: CGPoint(x: points[0].x * scale, y: points[0].y * scale))
                path.addLine(to: CGPoint(x: points[1].x * scale, y: points[1].y * scale))
              }
              .stroke(Color.orange, lineWidth: 1.5 / zoom)
              .allowsHitTesting(false)
            }
            ForEach(points.indices, id: \.self) { index in
              mark(index, scale: scale)
            }
          }
          .frame(width: fitted.width, height: fitted.height)
          .coordinateSpace(name: Self.space)
          .scaleEffect(zoom)
          .offset(pan)

          if let dragging, dragging < points.count {
            loupe(
              image: image, pixel: points[dragging], fitted: fitted, scale: scale,
              container: outer.size)
          }
        }
        .frame(width: outer.size.width, height: outer.size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 12)
            .onChanged { value in
              pan = CGSize(
                width: steadyPan.width + value.translation.width,
                height: steadyPan.height + value.translation.height)
            }
            .onEnded { _ in steadyPan = pan })
        .simultaneousGesture(
          MagnificationGesture()
            .onChanged { value in zoom = min(max(steadyZoom * value, 1), 10) }
            .onEnded { _ in steadyZoom = zoom })
      }
      .background(Color(.secondarySystemBackground))

      fields(plan: plan, image: image)
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

  /// A placed point. A 44 pt target around a small ring, draggable under the loupe.
  private func mark(_ index: Int, scale: CGFloat) -> some View {
    let colour: Color = index == 2 ? .blue : .orange
    return ZStack {
      Circle().strokeBorder(colour, lineWidth: 2 / zoom).frame(width: 14 / zoom, height: 14 / zoom)
      Circle().fill(colour).frame(width: 3 / zoom, height: 3 / zoom)
    }
    .frame(width: 44 / zoom, height: 44 / zoom)
    .contentShape(Rectangle())
    .position(x: points[index].x * scale, y: points[index].y * scale)
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
        .onChanged { value in
          dragging = index
          guard scale > 0 else { return }
          points[index] = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
        }
        .onEnded { _ in dragging = nil })
  }

  /// The drawing magnified around the point being dragged, above the finger.
  private func loupe(
    image: UIImage, pixel: CGPoint, fitted: CGSize, scale: CGFloat, container: CGSize
  ) -> some View {
    // One plan pixel per point in the loupe, at least three times the fitted
    // size: a dimension tick becomes something a thumb can land on.
    let magnification = max(3, 1 / scale)
    let size = Self.loupeSize
    let local = CGPoint(x: pixel.x * scale, y: pixel.y * scale)
    let onScreen = CGPoint(
      x: container.width / 2 + (local.x - fitted.width / 2) * zoom + pan.width,
      y: container.height / 2 + (local.y - fitted.height / 2) * zoom + pan.height)
    let above = CGPoint(x: onScreen.x, y: max(size / 2 + 8, onScreen.y - size * 0.85))
    return ZStack {
      Image(uiImage: image)
        .resizable()
        .frame(width: fitted.width * magnification, height: fitted.height * magnification)
        .offset(
          x: size / 2 - local.x * magnification,
          y: size / 2 - local.y * magnification)
      Path { path in
        path.move(to: CGPoint(x: size / 2, y: 0)); path.addLine(to: CGPoint(x: size / 2, y: size))
        path.move(to: CGPoint(x: 0, y: size / 2)); path.addLine(to: CGPoint(x: size, y: size / 2))
      }
      .stroke(Color.orange.opacity(0.8), lineWidth: 1)
    }
    .frame(width: size, height: size, alignment: .topLeading)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5))
    .shadow(radius: 6)
    .position(above)
    .allowsHitTesting(false)
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
      HStack {
        Button("Start again") {
          points = []
          dragging = nil
        }
        .font(.footnote)
        .disabled(points.isEmpty)
        Spacer()
        Button("Fit") {
          zoom = 1; steadyZoom = 1; pan = .zero; steadyPan = .zero
        }
        .font(.footnote)
        .disabled(zoom == 1 && pan == .zero)
      }
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
    if let preview = preview(imageWidth: imageWidth), let mpp = preview.metresPerPixel,
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
