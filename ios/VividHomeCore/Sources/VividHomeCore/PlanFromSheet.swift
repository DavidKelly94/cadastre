import Foundation

/// Writing a sheet's proposal into the plan (ADR-0032): the same fields the
/// Scale and Outline screens write, so everything downstream reads a plan set
/// up from the drawing exactly as it reads one set up by hand.
extension PlanFile {
  /// What applying a proposal changed.
  public struct SheetApplied: Equatable, Sendable {
    public var scaleSet = false
    /// Rooms that gained a pin, by slug.
    public var pinned: [String] = []
    /// Rooms that gained or replaced an outline, by slug.
    public var outlined: [String] = []
  }

  /// Take the chosen parts of a proposal.
  ///
  /// `pixelsPerPoint` is the plan raster's width over the page's width: the
  /// proposal is in sheet points and the plan stores pixels. The scale is set
  /// only when asked for, only when the sheet's dimensions do not contradict
  /// it, and never over a calibration the plan already has, because captures
  /// aligned to the old one would no longer sit where they were put. A room
  /// already on the plan keeps its pin; its outline is replaced when chosen.
  @discardableResult
  public mutating func apply(
    _ proposal: SheetReader.Proposal, pixelsPerPoint: Double, imageSize: (width: Int, height: Int),
    rooms chosen: Set<String>, setScale: Bool, at date: Date = Date()
  ) -> SheetApplied {
    var applied = SheetApplied()
    guard pixelsPerPoint > 0 else { return applied }

    if setScale, !isCalibrated, let scale = proposal.scale, scale.check != .disagrees {
      // The house's origin is the top-left of its walls: any fixed point
      // serves, and this one is findable on the drawing.
      let origin = proposal.wallBounds.map { (x: $0.minX * pixelsPerPoint, y: $0.minY * pixelsPerPoint) }
        ?? (x: 0.0, y: 0.0)
      let metresPerPixel = scale.metresPerPoint / pixelsPerPoint
      if let calibrated = calibrated(
        scaleFrom: (0, 0), to: (1000, 0), distanceMetres: 1000 * metresPerPixel, origin: origin,
        rotationDegrees: rotationDegrees, floorHeight: floorHeight)
      {
        self = calibrated
        applied.scaleSet = true
      }
    }

    for room in proposal.rooms where chosen.contains(room.slug) {
      if placement(of: room.slug) == nil {
        guard place(
          room: room.slug, x: room.label.x * pixelsPerPoint, y: room.label.y * pixelsPerPoint,
          in: imageSize, at: date)
        else { continue }
        applied.pinned.append(room.slug)
      }
      guard let points = Self.outlinePixels(of: room, pixelsPerPoint: pixelsPerPoint) else { continue }
      // Already as drawn: leave it, and the time it was outlined, alone.
      if sheetState(of: room, pixelsPerPoint: pixelsPerPoint) == .asDrawn { continue }
      if outline(room: room.slug, points: points, in: imageSize, at: date) {
        applied.outlined.append(room.slug)
      }
    }
    return applied
  }

  /// How a room on the plan stands against the same room on the drawing.
  public enum SheetState: Equatable, Sendable {
    /// Not on the plan: never taken from the drawing, or removed since.
    case missing
    /// On the plan with no outline.
    case pinned
    /// Outlined exactly as the drawing has it.
    case asDrawn
    /// Outlined differently: by hand, or the drawing has no outline to give.
    case byHand
  }

  /// The outline a proposal offers for a room, in plan pixels, or nil when
  /// the drawing has no walls round it or more corners than can be tapped.
  public static func outlinePixels(of room: SheetReader.Room, pixelsPerPoint: Double) -> [[Double]]? {
    guard room.status == .outlined, room.outline.count >= RoomOutline.minimumCorners,
      room.outline.count <= SheetReader.maximumCorners
    else { return nil }
    return room.outline.map { [$0.x * pixelsPerPoint, $0.y * pixelsPerPoint] }
  }

  /// Compare a room on the plan with what the drawing proposes for it.
  ///
  /// "As drawn" is corner for corner within a pixel and a half, in the same
  /// order: the names a capture asks for come from the order, so the same
  /// corners started somewhere else are a different outline.
  public func sheetState(of room: SheetReader.Room, pixelsPerPoint: Double) -> SheetState {
    guard let placed = placement(of: room.slug) else { return .missing }
    guard let outline = placed.outline else { return .pinned }
    guard let drawn = Self.outlinePixels(of: room, pixelsPerPoint: pixelsPerPoint),
      drawn.count == outline.count
    else { return .byHand }
    for (mine, theirs) in zip(outline, drawn) {
      guard mine.count == 2, abs(mine[0] - theirs[0]) <= 1.5, abs(mine[1] - theirs[1]) <= 1.5 else {
        return .byHand
      }
    }
    return .asDrawn
  }
}
