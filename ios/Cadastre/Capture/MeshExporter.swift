import ARKit
import Foundation

import CadastreCore

/// Writing ARKit's scene mesh to `mesh.obj`, `mesh_classes.u8` and `mesh.json`.
///
/// The mesh is exported once, at stop, from whatever `ARMeshAnchor`s the session
/// has accumulated. It is not the product's source of truth — ADR-0009 gives that
/// to the posed photos and depth — but it is what makes a room navigable in the
/// viewer, and the per-face classification is what lets a wall be told from a
/// floor without asking a model.
///
/// A room is typically 50k–300k faces, so this is the one write in the app that
/// is measured in tens of megabytes. It runs on the writer queue with a progress
/// callback, because the owner is looking at a "finishing" overlay while it goes.
enum MeshExporter {

  struct Summary: Codable, Equatable {
    var anchors: Int
    var vertices: Int
    var faces: Int
    var classHistogram: [String: Int]

    enum CodingKeys: String, CodingKey {
      case anchors
      case vertices
      case faces
      case classHistogram = "class_histogram"
    }
  }

  /// Export every mesh anchor into session coordinates.
  ///
  /// Vertices are transformed by the anchor transform on the way out, so the OBJ
  /// is in the same world frame as every pose in `frames.jsonl`. Face indices are
  /// 1-based and offset per anchor, because OBJ numbers vertices across the whole
  /// file rather than per object.
  @discardableResult
  static func export(
    anchors: [ARMeshAnchor],
    to layout: SessionLayout,
    progress: ((Double) -> Void)? = nil
  ) throws -> Summary {
    var obj = Data()
    var classes = Data()
    var histogram: [String: Int] = [:]
    var vertexOffset = 0
    var totalVertices = 0
    var totalFaces = 0

    // Built up as text and appended in chunks. Accumulating one Data and writing
    // once would hold the whole mesh twice in memory at the moment it is written;
    // a room's OBJ is tens of megabytes and the phone is already warm.
    let handle = try Self.makeFile(at: layout.mesh)
    defer { try? handle.close() }

    for (position, anchor) in anchors.enumerated() {
      let geometry = anchor.geometry
      let transform = anchor.transform

      var chunk = ""
      chunk.reserveCapacity(geometry.vertices.count * 24)

      for index in 0..<geometry.vertices.count {
        let local = Self.vertex(geometry.vertices, at: index)
        let world = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
        chunk += "v \(world.x) \(world.y) \(world.z)\n"
      }
      obj.removeAll(keepingCapacity: true)
      obj.append(Data(chunk.utf8))
      try handle.write(contentsOf: obj)

      chunk = ""
      let faces = geometry.faces
      chunk.reserveCapacity(faces.count * 20)
      let classification = geometry.classification

      for face in 0..<faces.count {
        let triangle = Self.face(faces, at: face)
        // OBJ is 1-based, and vertices are numbered across the whole file.
        let a = Int(triangle.0) + vertexOffset + 1
        let b = Int(triangle.1) + vertexOffset + 1
        let c = Int(triangle.2) + vertexOffset + 1
        chunk += "f \(a) \(b) \(c)\n"

        // One byte per face, in face order. Zero when ARKit offers no
        // classification, which is what the format calls "none".
        let raw = classification.map { Self.classification($0, at: face) } ?? 0
        classes.append(raw)
        histogram[Self.className(raw), default: 0] += 1
      }
      obj.removeAll(keepingCapacity: true)
      obj.append(Data(chunk.utf8))
      try handle.write(contentsOf: obj)

      vertexOffset += geometry.vertices.count
      totalVertices += geometry.vertices.count
      totalFaces += faces.count
      progress?(Double(position + 1) / Double(max(1, anchors.count)))
    }

    try handle.synchronize()
    try classes.write(to: layout.meshClasses, options: .atomic)

    let summary = Summary(
      anchors: anchors.count,
      vertices: totalVertices,
      faces: totalFaces,
      classHistogram: histogram)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
    try encoder.encode(summary).write(to: layout.meshSummary, options: .atomic)
    return summary
  }

  // MARK: - Geometry access

  /// Read one vertex, honouring the source's stride and offset.
  ///
  /// ARKit does not promise tightly packed vertices, and assuming it does is the
  /// classic way to get a mesh that looks almost right — sheared, or scaled along
  /// one axis — rather than obviously broken.
  private static func vertex(_ source: ARGeometrySource, at index: Int) -> SIMD3<Float> {
    let pointer = source.buffer.contents()
      .advanced(by: source.offset + source.stride * index)
    return pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
  }

  private static func face(_ element: ARGeometryElement, at index: Int)
    -> (UInt32, UInt32, UInt32)
  {
    let perFace = element.indexCountPerPrimitive
    let pointer = element.buffer.contents()
      .advanced(by: index * perFace * element.bytesPerIndex)
      .assumingMemoryBound(to: UInt32.self)
    return (pointer[0], pointer[1], pointer[2])
  }

  private static func classification(_ source: ARGeometrySource, at index: Int) -> UInt8 {
    source.buffer.contents()
      .advanced(by: source.offset + source.stride * index)
      .assumingMemoryBound(to: UInt8.self).pointee
  }

  /// The format's names for ARKit's raw classification values.
  private static func className(_ raw: UInt8) -> String {
    switch raw {
    case 1: return "wall"
    case 2: return "floor"
    case 3: return "ceiling"
    case 4: return "table"
    case 5: return "seat"
    case 6: return "window"
    case 7: return "door"
    default: return "none"
    }
  }

  private static func makeFile(at url: URL) throws -> FileHandle {
    let manager = FileManager.default
    if manager.fileExists(atPath: url.path) {
      try manager.removeItem(at: url)
    }
    guard manager.createFile(atPath: url.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return try FileHandle(forWritingTo: url)
  }
}
