import ARKit
import SceneKit

/// ARKit's reconstruction mesh as SceneKit geometry, for the HUD's mesh
/// toggle. `ARSCNView` has no debug option that draws the mesh (the RealityKit
/// view does, which is what build 71's toggle was reaching for), so each mesh
/// anchor becomes a wireframe node in the anchor's own frame.
extension SCNGeometry {
  static func wireframe(from mesh: ARMeshGeometry) -> SCNGeometry {
    let vertices = mesh.vertices
    let source = SCNGeometrySource(
      buffer: vertices.buffer, vertexFormat: vertices.format, semantic: .vertex,
      vertexCount: vertices.count, dataOffset: vertices.offset, dataStride: vertices.stride)

    let faces = mesh.faces
    let byteCount = faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex
    // Copied: the element outlives the frame it was read in, and ARKit rewrites
    // the anchor's buffers as the mesh refines.
    let indices = Data(bytes: faces.buffer.contents(), count: byteCount)
    let element = SCNGeometryElement(
      data: indices, primitiveType: .triangles, primitiveCount: faces.count,
      bytesPerIndex: faces.bytesPerIndex)

    let geometry = SCNGeometry(sources: [source], elements: [element])
    let material = SCNMaterial()
    material.fillMode = .lines
    material.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.8)
    material.isDoubleSided = true
    material.lightingModel = .constant
    geometry.materials = [material]
    return geometry
  }
}
