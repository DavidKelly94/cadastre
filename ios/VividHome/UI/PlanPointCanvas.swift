import SwiftUI
import UIKit
import VividHomeCore

/// A drawing with points on it, for the Scale and Outline screens.
///
/// Pinch zooms, a one-finger drag on empty plan pans, a tap places the next
/// point, and dragging a point moves it under a loupe, because a dimension tick
/// or a wall corner is a few pixels wide and a fingertip is forty. Points are
/// plan pixels throughout; the zoom and pan apply to the whole drawing, so a
/// point's position is a pixel times one scale whatever the zoom.
struct PlanPointCanvas: View {
  /// Not `Shape`: that name is SwiftUI's.
  enum Figure {
    /// A line between the first two points (a known distance).
    case segment
    /// Lines between consecutive points, closed once there are three (a room).
    case polygon
    /// Points only, each standing for something else (a landmark's place).
    case points
  }

  let image: UIImage
  @Binding var points: [CGPoint]
  /// Nil for as many as the owner taps.
  let maxPoints: Int?
  let figure: Figure
  let colour: (Int) -> Color
  /// A label beside each point, by index; shorter than `points` is fine.
  let labels: [String]

  @State private var dragging: Int?
  @State private var zoom: CGFloat = 1
  @State private var steadyZoom: CGFloat = 1
  @State private var pan: CGSize = .zero
  @State private var steadyPan: CGSize = .zero

  private static let space = "plan-point-canvas"
  private static let loupeSize: CGFloat = 132

  var body: some View {
    GeometryReader { outer in
      let fitted = PlanCoverageView.fit(image.size, into: outer.size)
      let scale = image.size.width == 0 ? 1 : fitted.width / image.size.width
      ZStack {
        ZStack(alignment: .topLeading) {
          Image(uiImage: image)
            .resizable()
            .frame(width: fitted.width, height: fitted.height)
            .onTapGesture { point in
              guard maxPoints.map({ points.count < $0 }) ?? true, scale > 0 else { return }
              points.append(CGPoint(x: point.x / scale, y: point.y / scale))
            }
          lines(scale: scale)
          ForEach(points.indices, id: \.self) { index in
            mark(index, scale: scale)
          }
        }
        .frame(width: fitted.width, height: fitted.height)
        .coordinateSpace(name: Self.space)
        .scaleEffect(zoom)
        .offset(pan)

        if let dragging, dragging < points.count {
          loupe(pixel: points[dragging], fitted: fitted, scale: scale, container: outer.size)
        }

        if zoom != 1 || pan != .zero {
          VStack {
            Spacer()
            HStack {
              Spacer()
              Button("Fit") {
                zoom = 1; steadyZoom = 1; pan = .zero; steadyPan = .zero
              }
              .font(.footnote.weight(.semibold))
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(.regularMaterial, in: Capsule())
              .padding(10)
            }
          }
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
  }

  @ViewBuilder
  private func lines(scale: CGFloat) -> some View {
    switch figure {
    case .segment:
      if points.count >= 2 {
        Path { path in
          path.move(to: CGPoint(x: points[0].x * scale, y: points[0].y * scale))
          path.addLine(to: CGPoint(x: points[1].x * scale, y: points[1].y * scale))
        }
        .stroke(colour(0), lineWidth: 1.5 / zoom)
        .allowsHitTesting(false)
      }
    case .polygon:
      if points.count >= 2 {
        Path { path in
          path.move(to: CGPoint(x: points[0].x * scale, y: points[0].y * scale))
          for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
          }
          if points.count >= 3 { path.closeSubpath() }
        }
        .stroke(colour(0), style: StrokeStyle(lineWidth: 1.5 / zoom, lineJoin: .round))
        .allowsHitTesting(false)
      }
    case .points:
      EmptyView()
    }
  }

  /// A placed point: a 44 pt target around a small ring, draggable under the loupe.
  private func mark(_ index: Int, scale: CGFloat) -> some View {
    let tone = colour(index)
    return ZStack {
      Circle().strokeBorder(tone, lineWidth: 2 / zoom).frame(width: 14 / zoom, height: 14 / zoom)
      Circle().fill(tone).frame(width: 3 / zoom, height: 3 / zoom)
      if index < labels.count {
        Text(labels[index])
          .font(.system(size: 9 / zoom, weight: .semibold))
          .padding(.horizontal, 3 / zoom).padding(.vertical, 1 / zoom)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3 / zoom))
          .offset(y: 15 / zoom)
          .fixedSize()
      }
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
  private func loupe(pixel: CGPoint, fitted: CGSize, scale: CGFloat, container: CGSize) -> some View {
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
        .offset(x: size / 2 - local.x * magnification, y: size / 2 - local.y * magnification)
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
}
