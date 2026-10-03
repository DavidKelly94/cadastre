import ARKit
import Foundation

import VividHomeCore

/// The mesh faces around a point, in session coordinates, for the corner snap
/// (ADR-0031). ARKit types stop here; `CornerSnap` in the core package does
/// the geometry and never sees an anchor.
enum MeshProbe {
  /// Every face whose centroid is within `radius` of `point`, with its
  /// classification. Anchors are blocks a metre or two across, so an anchor
  /// whose own origin is far from the point is skipped without reading it.
  static func faces(near point: Vector3, radius: Double, in anchors: [ARMeshAnchor]) -> [CornerSnap.Face] {
    var out: [CornerSnap.Face] = []
    let reach = Float(radius)
    let target = SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z))
    for anchor in anchors {
      let origin = anchor.transform.columns.3
      let distance = simd_distance(SIMD3<Float>(origin.x, origin.y, origin.z), target)
      // An anchor's geometry can extend a few metres from its origin.
      guard distance <= reach + 4 else { continue }

      let geometry = anchor.geometry
      let transform = anchor.transform
      let classification = geometry.classification
      let faces = geometry.faces
      for face in 0..<faces.count {
        let triangle = MeshExporter.face(faces, at: face)
        let a = world(transform, MeshExporter.vertex(geometry.vertices, at: Int(triangle.0)))
        let b = world(transform, MeshExporter.vertex(geometry.vertices, at: Int(triangle.1)))
        let c = world(transform, MeshExporter.vertex(geometry.vertices, at: Int(triangle.2)))
        let centroid = (a + b + c) / 3
        guard simd_distance(centroid, target) <= reach else { continue }
        let raw = classification.map { MeshExporter.classification($0, at: face) } ?? 0
        out.append(
          CornerSnap.Face(
            a: Vector3(Double(a.x), Double(a.y), Double(a.z)),
            b: Vector3(Double(b.x), Double(b.y), Double(b.z)),
            c: Vector3(Double(c.x), Double(c.y), Double(c.z)),
            classification: raw))
      }
    }
    return out
  }

  private static func world(_ transform: simd_float4x4, _ local: SIMD3<Float>) -> SIMD3<Float> {
    let moved = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
    return SIMD3<Float>(moved.x, moved.y, moved.z)
  }
}
